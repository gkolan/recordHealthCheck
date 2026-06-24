/**
 * @author Gautam Kolan (https://github.com/gkolan)
 * SPDX-License-Identifier: Apache-2.0
 */

/**
 * Shared evaluator exception carrying a machine-readable reason code.
 *
 * Promoted from the duplicate inner `EvaluatorException` classes that previously
 * lived inside RecordHealthCheckSoqlEvaluator and RecordHealthCheckDualSoqlEvaluator.
 * A single top-level type lets the extracted RecordHealthCheckComparatorEngine throw
 * one exception both evaluators recognize, so their error handlers map the same
 * reason codes to UNABLE_TO_EVALUATE results.
 */
public class RecordHealthCheckEvaluatorException extends Exception {
  public String reasonCode;
  public RecordHealthCheckEvaluatorException(
    String reasonCode,
    String message
  ) {
    this(message);
    this.reasonCode = reasonCode;
  }
}
