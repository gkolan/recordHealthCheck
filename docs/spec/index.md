# Design Specification (modular)

Split views of the [Record Health Check Design Specification](../reference/record-health-check-design-spec.md) for focused reading. Section numbers (1-20) match the monolith; deep links elsewhere in the repo point at the monolith anchors.

When updating contracts, edit the canonical monolith first. Contributors: see [Documentation changes](../../CONTRIBUTING.md#documentation-changes) for the regeneration step.

## Files

| File | Sections | What it covers |
| ---- | -------- | -------------- |
| [01-goals-and-architecture.md](01-goals-and-architecture.md) | 1-3 | Goals, non-goals, runtime layout |
| [02-metadata-check-set.md](02-metadata-check-set.md) | 4 | Check Set CMT field reference |
| [03-metadata-rules.md](03-metadata-rules.md) | 5 | Rule CMT field reference |
| [04-check-types-comparators-applicability.md](04-check-types-comparators-applicability.md) | 6-8 | Check Methods, Operators, applicability |
| [05-result-contract-and-reason-codes.md](05-result-contract-and-reason-codes.md) | 9-10 | Result DTO, reason codes |
| [06-soql-safety-and-message-tokens.md](06-soql-safety-and-message-tokens.md) | 11-12 | SOQL safety, message tokens |
| [07-programmatic-api.md](07-programmatic-api.md) | 13 | RecordHealthCheck.run API |
| [08-logging-and-observability.md](08-logging-and-observability.md) | 14 | `[RHC]` logging and Debug Mode |
| [09-lwc-behavior.md](09-lwc-behavior.md) | 15 | LWC contracts (compact UI) |
| [10-validation-and-deployment.md](10-validation-and-deployment.md) | 16-17 | Metadata validator, deployment contents |
| [11-defaults-and-resolved-issues.md](11-defaults-and-resolved-issues.md) | 18-19 | Defaults, resolved bug history |
| [12-limitations-and-roadmap.md](12-limitations-and-roadmap.md) | 20 | Open limitations |

## Suggested reading order

1. **Runtime contract:** [01-goals-and-architecture.md](01-goals-and-architecture.md) → [05-result-contract-and-reason-codes.md](05-result-contract-and-reason-codes.md) → [09-lwc-behavior.md](09-lwc-behavior.md)
2. **Metadata fields (formal):** [02-metadata-check-set.md](02-metadata-check-set.md) + [03-metadata-rules.md](03-metadata-rules.md) → [04-check-types-comparators-applicability.md](04-check-types-comparators-applicability.md)
3. **Programmatic integration:** [07-programmatic-api.md](07-programmatic-api.md) → [08-logging-and-observability.md](08-logging-and-observability.md) → [12-limitations-and-roadmap.md](12-limitations-and-roadmap.md)
4. **Contributing / release:** [10-validation-and-deployment.md](10-validation-and-deployment.md) → [12-limitations-and-roadmap.md](12-limitations-and-roadmap.md)

## Related

- [Design Specification (monolith)](../reference/record-health-check-design-spec.md)
- [Custom Metadata field reference](../metadata/index.md)
- [Documentation authoring standard](../../CONTRIBUTING.md#documentation-changes)
