> [!NOTE]
> **Canonical source:** Section numbers and anchors in the [full design specification](../reference/record-health-check-design-spec.md) are stable for cross-links.

## 16. Validation Rules

`RecordHealthCheckMetadataValidator` (deploy-time) and `RecordHealthCheckConfigService` (runtime) validate overlapping rules. Both alias valid-value sets from `RecordHealthCheckConstants`. The validator is a CI and Anonymous Apex utility; there is no Setup UI wired to it yet.

Both validate Check Set modes, objects/icons, Rule shape and required fields,
severity/source/handling values, scalar applicability COUNT shape and threshold,
query output fields, plugin class/interface/JSON, row caps, and dependencies. The
deploy-time validator warns when the first-25 cap omits rules or prerequisites and
exposes structured JSON through `validateAsJson()` for CI.

Validation must catch: missing required fields, unknown modes and Check Methods, invalid Operator / **If Query Returns Multiple Rows** combinations, invalid **If Query Returns Zero Rows** values, invalid Apex JSON, missing or cyclic dependencies, and row safety values outside framework caps.

## 17. Deployment Contents

- Apex classes and interfaces (including `RecordHealthCheck` façade, `RecordHealthCheckLogger`, `RecordHealthCheckConstants`, `RecordHealthCheckSoqlTemplate`, `RecordHealthCheckValueResolver`)
- Lightning Web Component
- Custom Metadata Type definitions and fields
- Sample Custom Metadata records (10 Check Sets, 88 Rules)
- Layout metadata for Custom Metadata editing
- Permission sets: `Record_Health_Check_User`, `Record_Health_Check_Admin`
- Documentation and anonymous Apex runner script

Deploy via `force-app` or `manifest/package.xml`.
