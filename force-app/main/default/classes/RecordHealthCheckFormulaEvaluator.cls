/**
 * @author Gautam Kolan (https://github.com/gkolan)
 * SPDX-License-Identifier: Apache-2.0
 */

public with sharing class RecordHealthCheckFormulaEvaluator {
  // Compiled once per transaction
  private static final Pattern PATTERN_TOKEN = Pattern.compile(
    '\\{!([A-Za-z0-9_\\.]+)\\}'
  );

  // B6 / RB-07: track FormulaEval calls for the WHOLE Apex transaction to avoid
  // hitting Salesforce's 100-call platform limit, which is itself transaction-wide
  // and uncatchable. This static accumulates for the life of the transaction and
  // is intentionally NEVER reset per check: resetting a framework counter mid
  // transaction made the guard lie when a caller loops evaluate() (Flow, batch,
  // anonymous Apex). Each real LWC request is its own transaction, so the counter
  // naturally starts at zero there without any reset. A 5-call safety margin
  // leaves room for applicability gates on the remaining checks to still resolve.
  // Tests reset this @TestVisible field directly to isolate per-method counts.
  @TestVisible
  private static Integer formulaEvalCallCount = 0;
  private static final Integer FORMULA_EVAL_TX_LIMIT = 100;
  private static final Integer FORMULA_EVAL_SAFETY_MARGIN = 5;

  // SCAN-01: evaluateFormulaAnyType probes up to 8 return types and every failed
  // attempt consumes a real, platform-counted FormulaEval call. When a caller
  // loops evaluate() over many records in one transaction (Flow, batch, anonymous
  // Apex), re-probing the same scalar formula per record multiplies that cost and
  // can exhaust the 100-call budget. Caching the return type that first resolved a
  // given formula (keyed by SObject type + expression) lets the second and later
  // records resolve in a single call. Transaction-scoped, like formulaEvalCallCount.
  @TestVisible
  private static Map<String, formulaeval.FormulaReturnType> resolvedReturnTypeByFormula = new Map<String, formulaeval.FormulaReturnType>();

  /**
   * Evaluates a Formula check (CheckMethod__c = Formula).
   * Also used internally by the SOQL evaluator for:
   *   - RunWhenFormula__c evaluation
   *   - RecordFormulaValue__c (comparison-side resolution, Tier 5/8)
   *   - ValueToTest__c as primary scalar (Tier 6, ListContainsAny/ListDoesNotContainAny)
   */
  public RecordHealthCheckResult evaluate(
    Record_Health_Check_Rule__mdt rule,
    Id recordId,
    SObject record
  ) {
    Long startMs = System.currentTimeMillis();
    RecordHealthCheckResult result = new RecordHealthCheckResult();
    result.checkDeveloperName = rule.DeveloperName;
    result.label = rule.CheckName__c;
    result.priority = rule.RunOrder__c;
    result.evaluatorType = 'Formula';

    try {
      // FLS / accessibility check on fields referenced in the formula
      // FormulaEval will surface an exception if a field is inaccessible;
      // we catch that below and map it to FIELD_NOT_ACCESSIBLE.
      Object evalResult = evaluateFormula(rule.PassFailFormula__c, record);
      result = applyEvaluationResult(rule, record, result, evalResult);
    } catch (Exception ex) {
      result = applyEvaluationException(rule, result, ex);
    }

    result.durationMs = System.currentTimeMillis() - startMs;
    return result;
  }

  @TestVisible
  private RecordHealthCheckResult applyEvaluationException(
    Record_Health_Check_Rule__mdt rule,
    RecordHealthCheckResult result,
    Exception ex
  ) {
    result.status = 'UNABLE_TO_EVALUATE';
    if (ex instanceof System.NoAccessException) {
      result.reasonCode = 'FIELD_NOT_ACCESSIBLE';
    } else if (ex instanceof FormulaEvaluationException) {
      // Preserve the specific reason (e.g. FORMULA_EVAL_LIMIT) so a transaction
      // hitting the FormulaEval budget is not mislabeled as INVALID_FORMULA.
      result.reasonCode = ((FormulaEvaluationException) ex).reasonCode;
    } else {
      result.reasonCode = 'INVALID_FORMULA';
    }
    result.message = safeCannotEvaluateMessage(rule);
    result.detailMessage = ex.getMessage();
    return result;
  }

  @TestVisible
  private RecordHealthCheckResult applyEvaluationResult(
    Record_Health_Check_Rule__mdt rule,
    SObject record,
    RecordHealthCheckResult result,
    Object evalResult
  ) {
    if (evalResult == null) {
      // Null from FormulaEval means the formula could not resolve — typically
      // a null relationship traversal (e.g. Parent.Field when Parent is null)
      // or an inaccessible field. Treating null as FAIL produces false failures,
      // so we surface it as UNABLE_TO_EVALUATE instead.
      result.status = 'UNABLE_TO_EVALUATE';
      result.reasonCode = 'INVALID_FORMULA';
      result.message = safeCannotEvaluateMessage(rule);
      result.detailMessage = 'Formula returned null. The formula may reference a null relationship or an inaccessible field.';
    } else if (evalResult instanceof Boolean) {
      Boolean passed = (Boolean) evalResult;
      // A Formula check has no separable record value vs operand — the condition
      // lives inside the expression. Surface the formula as the expected
      // condition so the row still shows what was required (actualValue stays
      // null; the UI renders only the expected side). Route it through
      // formatValue so the expression is quoted like every other expected value
      // (e.g. Expected "ISBLANK(BillingCity)"), keeping the display uniform.
      result.expectedValue = RecordHealthCheckComparatorEngine.formatValue(
        rule.PassFailFormula__c
      );
      if (passed) {
        result.status = 'PASS';
      } else {
        result.status = 'FAIL';
        result.severity = rule.Severity__c;
        result.message = resolveMergeFields(rule.MessageWhenFailed__c, record);
      }
    } else {
      // Non-boolean result — invalid formula for a Formula check
      result.status = 'UNABLE_TO_EVALUATE';
      result.reasonCode = 'INVALID_FORMULA';
      result.message = safeCannotEvaluateMessage(rule);
      result.detailMessage = 'Formula did not return a Boolean value.';
    }
    return result;
  }

  /**
   * Evaluates the applicability formula for a rule.
   * Returns:
   *   true  — gate passes, main evaluator should run
   *   false — gate fails, return SKIPPED
   *   null  — gate could not be evaluated, return UNABLE_TO_EVALUATE
   *
   * The out-param reasonCode[0] is populated when null is returned.
   */
  public Boolean evaluateApplicabilityFormula(
    String formulaExpression,
    SObject record,
    String[] reasonCodeOut
  ) {
    try {
      Object result = evaluateFormula(formulaExpression, record);
      if (result instanceof Boolean) {
        return (Boolean) result;
      }
      // Non-boolean from applicability formula is a config error
      reasonCodeOut[0] = 'INVALID_FORMULA';
      return null;
    } catch (FormulaEvaluationException fex) {
      // P1-02: preserve the typed reason (e.g. FORMULA_EVAL_LIMIT) instead of
      // re-deriving it from the message, which would collapse it to
      // INVALID_FORMULA and hide the real cause from the admin. Mirrors the
      // resolveScalar path, which already preserves the typed reason code.
      reasonCodeOut[0] = fex.reasonCode;
      return null;
    } catch (Exception ex) {
      reasonCodeOut[0] = classifyFormulaException(ex);
      return null;
    }
  }

  /**
   * Resolves a formula expression to a scalar value for use as the primary
   * operand in Tier 6 (ListContainsAny / ListDoesNotContainAny) checks,
   * or as the comparison value in Tier 5/8 checks.
   *
   * Returns null if the formula resolves to null (blank parent traversal etc.).
   * Throws RecordHealthCheckFormulaException if the formula cannot be evaluated.
   */
  public Object resolveScalar(String formulaExpression, SObject record) {
    return resolveScalar(formulaExpression, record, null);
  }

  /**
   * SCAN-01: overload accepting the admin-declared return type (the
   * ScalarFormulaReturnType__c picklist value). When non-blank and not 'Auto',
   * the formula is evaluated once with that type instead of probing up to eight,
   * saving FormulaEval calls in bulk/Flow loops. An unrecognized or mis-declared
   * type degrades gracefully to the full probe, so a wrong declaration never
   * fails a check that would otherwise resolve.
   */
  public Object resolveScalar(
    String formulaExpression,
    SObject record,
    String declaredReturnType
  ) {
    try {
      return evaluateFormulaAnyType(
        formulaExpression,
        record,
        mapDeclaredReturnType(declaredReturnType)
      );
    } catch (FormulaEvaluationException fex) {
      throw fex;
    } catch (Exception ex) {
      throw new FormulaEvaluationException(
        classifyFormulaException(ex),
        ex.getMessage()
      );
    }
  }

  /**
   * Maps the ScalarFormulaReturnType__c picklist value to a FormulaReturnType,
   * or null for 'Auto'/blank/unrecognized (caller probes all types).
   */
  @TestVisible
  private formulaeval.FormulaReturnType mapDeclaredReturnType(
    String declaredReturnType
  ) {
    if (String.isBlank(declaredReturnType)) {
      return null;
    }
    switch on declaredReturnType {
      when 'Boolean' {
        return formulaeval.FormulaReturnType.BOOLEAN;
      }
      when 'Number' {
        return formulaeval.FormulaReturnType.DECIMAL;
      }
      when 'Date' {
        return formulaeval.FormulaReturnType.DATE;
      }
      when 'DateTime' {
        return formulaeval.FormulaReturnType.DATETIME;
      }
      when 'Text' {
        return formulaeval.FormulaReturnType.STRING;
      }
      when else {
        // 'Auto' and any unrecognized value fall back to full probing.
        return null;
      }
    }
  }

  // ─── Internal evaluation ──────────────────────────────────────────────────

  /**
   * Calls the FormulaEval API (requires API v63.0+, Spring '25 GA).
   * Null parent traversal returns null rather than throwing — the caller
   * is responsible for treating null as false / no-match as appropriate.
   *
   * withReturnType() is required by the FormulaBuilder API; defaults to Boolean
   * for all formula-check and applicability paths.
   */
  private Object evaluateFormula(String formulaExpression, SObject record) {
    return evaluateFormula(
      formulaExpression,
      record,
      formulaeval.FormulaReturnType.BOOLEAN
    );
  }

  private Object evaluateFormula(
    String formulaExpression,
    SObject record,
    formulaeval.FormulaReturnType returnType
  ) {
    // B6 fix: guard against the 100-call-per-transaction FormulaEval platform limit
    if (
      formulaEvalCallCount >= FORMULA_EVAL_TX_LIMIT - FORMULA_EVAL_SAFETY_MARGIN
    ) {
      throw new FormulaEvaluationException(
        'FORMULA_EVAL_LIMIT',
        'FormulaEval transaction limit approaching (' +
          formulaEvalCallCount +
          ' calls used). Split this Check Set or replace formula-based checks with SOQL checks.'
      );
    }
    formulaEvalCallCount++;
    return Formula.builder()
      .withType(record.getSObjectType())
      .withReturnType(returnType)
      .withFormula(formulaExpression)
      .build()
      .evaluate(record);
  }

  /**
   * Attempts to evaluate a formula as any supported return type, trying each
   * in order until one succeeds. Used by resolveScalar where the type is unknown.
   */
  private Object evaluateFormulaAnyType(
    String formulaExpression,
    SObject record
  ) {
    return evaluateFormulaAnyType(formulaExpression, record, null);
  }

  private Object evaluateFormulaAnyType(
    String formulaExpression,
    SObject record,
    formulaeval.FormulaReturnType declaredType
  ) {
    // SCAN-01: try a preferred return type before probing — first the
    // admin-declared type (ScalarFormulaReturnType__c), else the type that
    // already resolved this formula in this transaction. Either way a single
    // call replaces the up-to-eight-call probe for repeated evaluations
    // (bulk/Flow loops). A preferred type can still fail for a particular record
    // (e.g. a value that overflows a numeric type, or a mis-declared type), so
    // fall through to a full probe and re-cache on success.
    String cacheKey =
      String.valueOf(record.getSObjectType()) +
      '|' +
      formulaExpression;
    formulaeval.FormulaReturnType preferredType = declaredType != null
      ? declaredType
      : resolvedReturnTypeByFormula.get(cacheKey);
    if (preferredType != null) {
      try {
        Object value = evaluateFormula(
          formulaExpression,
          record,
          preferredType
        );
        resolvedReturnTypeByFormula.put(cacheKey, preferredType);
        return value;
      } catch (System.NoAccessException nae) {
        throw nae;
      } catch (Exception ex) {
        resolvedReturnTypeByFormula.remove(cacheKey);
      }
    }

    // Order matters: each failed attempt burns a FormulaEval API call (limit 100/tx).
    // BOOLEAN first (most formula checks), DECIMAL next (numbers/currency/percent),
    // DATE/DATETIME before STRING so temporal fields resolve in 3–4 calls rather than 7–8.
    // STRING is a catch-all that can coerce almost any type, so it comes after specifics.
    List<formulaeval.FormulaReturnType> typesToTry = new List<formulaeval.FormulaReturnType>{
      formulaeval.FormulaReturnType.BOOLEAN,
      formulaeval.FormulaReturnType.DECIMAL,
      formulaeval.FormulaReturnType.DATE,
      formulaeval.FormulaReturnType.DATETIME,
      formulaeval.FormulaReturnType.STRING,
      formulaeval.FormulaReturnType.DOUBLE,
      formulaeval.FormulaReturnType.INTEGER,
      formulaeval.FormulaReturnType.LONG
    };
    Exception lastException;
    for (formulaeval.FormulaReturnType rt : typesToTry) {
      try {
        Object value = evaluateFormula(formulaExpression, record, rt);
        resolvedReturnTypeByFormula.put(cacheKey, rt);
        return value;
      } catch (System.NoAccessException nae) {
        throw nae;
      } catch (Exception ex) {
        lastException = ex;
      }
    }
    throw lastException;
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  @TestVisible
  private String classifyFormulaException(Exception fex) {
    String msg = fex.getMessage();
    if (msg != null && msg.containsIgnoreCase('access')) {
      return 'FIELD_NOT_ACCESSIBLE';
    }
    return 'INVALID_FORMULA';
  }

  /**
   * Resolves {!FieldName} merge tokens in a message string using the record's
   * field values. Unresolvable tokens are replaced with an empty string.
   * A bad token never causes the result to change status.
   */
  public String resolveMergeFields(String template, SObject record) {
    if (String.isBlank(template) || record == null) {
      return template;
    }
    String resolved = template;
    Matcher m = PATTERN_TOKEN.matcher(template);
    while (m.find()) {
      String token = m.group(0);
      String fieldPath = m.group(1);
      String value = '';
      try {
        Object raw = resolveFieldPath(record, fieldPath);
        if (raw != null) {
          value = String.valueOf(raw);
          if (value == 'null')
            value = '';
        }
      } catch (Exception ex) {
        value = '';
      }
      resolved = resolved.replace(token, value);
    }
    return resolved;
  }

  @TestVisible
  private Object resolveFieldPath(SObject record, String fieldPath) {
    if (!fieldPath.contains('.')) {
      return record.get(fieldPath);
    }
    List<String> parts = fieldPath.split('\\.');
    SObject current = record;
    for (Integer i = 0; i < parts.size() - 1; i++) {
      current = current.getSObject(parts[i]);
      if (current == null) {
        return null;
      }
    }
    return current.get(parts[parts.size() - 1]);
  }

  @TestVisible
  private String safeCannotEvaluateMessage(Record_Health_Check_Rule__mdt rule) {
    return String.isNotBlank(rule.MessageWhenCannotRun__c)
      ? rule.MessageWhenCannotRun__c
      : 'This check could not be evaluated. Contact your administrator.';
  }

  // ─── Exception for scalar resolution failures ─────────────────────────────

  public class FormulaEvaluationException extends Exception {
    public String reasonCode;
    public FormulaEvaluationException(String reasonCode, String message) {
      this(message);
      this.reasonCode = reasonCode;
    }
  }
}
