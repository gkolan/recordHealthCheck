> [!NOTE]
> **Canonical source:** Section numbers and anchors in the [full design specification](../reference/record-health-check-design-spec.md) are stable for cross-links.

## 5. Rule Model (`Record_Health_Check_Rule__mdt`)

A Rule defines one check inside a Check Set.

> [!NOTE]
> Field reference (Setup labels, API names, per-method fields): [Rule fields](../metadata/rule-fields.md).

### 5.1 Dependencies

Dependency contract:

- Prerequisite must be active and in the same Check Set.
- Prerequisite must have a strictly lower `RunOrder__c` (validated by `RecordHealthCheckMetadataValidator`).
- Dependent Rule runs only when prerequisite returns `PASS`.
- If prerequisite is missing, inactive, fails, errors, is skipped, or cannot be evaluated, dependent is `SKIPPED` with `DEPENDENCY_NOT_PASSED`.
- Cycles return `CIRCULAR_DEPENDENCY` with status `UNABLE_TO_EVALUATE` on both the LWC (client pre-seed, no Apex call) and direct Apex evaluation.
- Enforced **both** client-side (LWC, before each Apex call) and server-side (`RecordHealthCheckEngine`, for direct Apex/API callers). Server-side evaluation re-runs the prerequisite, which can duplicate work when the LWC already evaluated it.
- If prerequisite is omitted from the run because of the 25-check cap, dependent is `SKIPPED` with `DEPENDENCY_NOT_IN_RUN`.

### 5.2 Applicability (pre-evaluation gate)

Applicability is evaluated before the Rule evaluator. If false, the Rule returns `SKIPPED` with `APPLICABILITY_NOT_MET`. If it cannot be evaluated safely, the Rule returns `UNABLE_TO_EVALUATE`.
