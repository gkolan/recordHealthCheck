/**
 * @author Gautam Kolan (https://github.com/gkolan)
 * SPDX-License-Identifier: Apache-2.0
 */

/**
 * Single source of truth for the framework's valid-value sets and numeric caps.
 *
 * These were previously duplicated, verbatim, in both RecordHealthCheckConfigService
 * (runtime validation) and RecordHealthCheckMetadataValidator (deploy-time audit).
 * Duplication meant adding a new comparator, behavior, or mode required editing
 * several files in lockstep — and missing one let the two validators silently
 * disagree. Centralizing them here removes that drift risk and makes the framework
 * easier to extend: add a value once and every validator sees it.
 *
 * Public Set properties return defensive copies. Callers may safely mutate the
 * returned Set without changing the framework's canonical values for the
 * transaction.
 *
 * Comparator/behavior *logic* (the if-chains in the engine and evaluators)
 * intentionally lives with the code that applies it; only the enumerations of
 * legal values live here.
 */
public with sharing class RecordHealthCheckConstants {
  // ─── Numeric caps ──────────────────────────────────────────────────────────

  /** Maximum active checks the LWC will run for one Check Set. */
  public static final Integer FRAMEWORK_MAX_CHECKS = 25;

  /** Maximum rows any single check query may return before it is rejected. */
  public static final Integer FRAMEWORK_MAX_ROWS = 2000;

  // ─── Check Set level ───────────────────────────────────────────────────────

  private static final Set<String> VALID_DISPLAY_MODES_INTERNAL = new Set<String>{
    'Show',
    'Hide'
  };
  public static Set<String> VALID_DISPLAY_MODES {
    get {
      return new Set<String>(VALID_DISPLAY_MODES_INTERNAL);
    }
  }
  private static final Set<String> VALID_TRIGGER_MODES_INTERNAL = new Set<String>{
    'Automatic',
    'Manual'
  };
  public static Set<String> VALID_TRIGGER_MODES {
    get {
      return new Set<String>(VALID_TRIGGER_MODES_INTERNAL);
    }
  }
  private static final Set<String> VALID_REVEAL_MODES_INTERNAL = new Set<String>{
    'AllAtOnce',
    'OneAtATime'
  };
  public static Set<String> VALID_REVEAL_MODES {
    get {
      return new Set<String>(VALID_REVEAL_MODES_INTERNAL);
    }
  }

  // ─── Rule level ────────────────────────────────────────────────────────────

  private static final Set<String> VALID_CHECK_TYPES_INTERNAL = new Set<String>{
    'Formula',
    'Query',
    'Apex',
    'CompareTwoQueries'
  };
  public static Set<String> VALID_CHECK_TYPES {
    get {
      return new Set<String>(VALID_CHECK_TYPES_INTERNAL);
    }
  }

  private static final Set<String> VALID_COMPARATORS_INTERNAL = new Set<String>{
    'Equals',
    'NotEquals',
    'GreaterThan',
    'GreaterThanOrEqual',
    'LessThan',
    'LessThanOrEqual',
    'Contains',
    'DoesNotContain',
    'IsBlank',
    'IsNotBlank',
    'ListContainsAny',
    'ListDoesNotContainAny',
    'ListsOverlap',
    'ListContainsAll',
    'ExactListMatch'
  };
  public static Set<String> VALID_COMPARATORS {
    get {
      return new Set<String>(VALID_COMPARATORS_INTERNAL);
    }
  }

  /** Comparators valid only on CheckType CompareTwoQueries (list-vs-list). */
  private static final Set<String> DUAL_QUERY_COMPARATORS_INTERNAL = new Set<String>{
    'ListsOverlap',
    'ListContainsAll',
    'ExactListMatch'
  };
  public static Set<String> DUAL_QUERY_COMPARATORS {
    get {
      return new Set<String>(DUAL_QUERY_COMPARATORS_INTERNAL);
    }
  }

  private static final Set<String> VALID_NULL_BEHAVIORS_INTERNAL = new Set<String>{
    'MissingMeansNoMatch',
    'SkipRecordsWithMissingValue',
    'TreatMissingAsBlank'
  };
  public static Set<String> VALID_NULL_BEHAVIORS {
    get {
      return new Set<String>(VALID_NULL_BEHAVIORS_INTERNAL);
    }
  }

  private static final Set<String> VALID_EMPTY_BEHAVIORS_INTERNAL = new Set<String>{
    'Pass',
    'Fail',
    'Skip',
    'UnableToEvaluate'
  };
  public static Set<String> VALID_EMPTY_BEHAVIORS {
    get {
      return new Set<String>(VALID_EMPTY_BEHAVIORS_INTERNAL);
    }
  }

  public static Set<String> VALID_SEVERITIES {
    get {
      return new Set<String>{ 'Error', 'Warning', 'Info' };
    }
  }
  public static Set<String> VALID_COMPARISON_VALUE_SOURCES {
    get {
      return new Set<String>{ 'FixedValue', 'RecordFormula', 'AnotherQuery' };
    }
  }
  public static Set<String> VALID_MULTIPLE_RECORDS_HANDLING {
    get {
      return new Set<String>{
        'OneResult',
        'AnyRowPasses',
        'AllRowsPass',
        'CompareAsLists'
      };
    }
  }

  // ─── Applicability gate ────────────────────────────────────────────────────

  private static final Set<String> VALID_APPLICABILITY_MODES_INTERNAL = new Set<String>{
    'Always',
    'Formula',
    'SOQL'
  };
  public static Set<String> VALID_APPLICABILITY_MODES {
    get {
      return new Set<String>(VALID_APPLICABILITY_MODES_INTERNAL);
    }
  }

  /**
   * Comparators legal on CountOperator__c (SOQL applicability mode).
   * The applicability gate counts rows and compares the count to an integer
   * threshold, so only the ordered/equality comparators apply — not the text or
   * list comparators in VALID_COMPARATORS. Mirrors
   * RecordHealthCheckEngine.applyApplicabilityComparator.
   */
  private static final Set<String> VALID_APPLICABILITY_COMPARATORS_INTERNAL = new Set<String>{
    'Equals',
    'NotEquals',
    'GreaterThan',
    'GreaterThanOrEqual',
    'LessThan',
    'LessThanOrEqual'
  };
  public static Set<String> VALID_APPLICABILITY_COMPARATORS {
    get {
      return new Set<String>(VALID_APPLICABILITY_COMPARATORS_INTERNAL);
    }
  }
}
