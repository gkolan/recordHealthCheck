# Custom Metadata Types and Fields

Field reference for the two Custom Metadata Types that hold Record Health Check configuration. Setup labels are what appears in the metadata editor; API names are what metadata XML, Apex, and the LLM guide use.

| Plain name | Setup name | API type | Field reference |
| ---------- | ---------- | -------- | --------------- |
| **Check Set** | Record Health Check Set | `Record_Health_Check_Set__mdt` | [Check Set fields](check-set.md) |
| **Rule** | Record Health Check Rule | `Record_Health_Check_Rule__mdt` | [Rule fields](rule-fields.md) |

## How these docs fit together

| Document | Role |
| -------- | ---- |
| [Check Set fields](check-set.md) | Every field on the Check Set type |
| [Rule fields](rule-fields.md) | Every field on the Rule type |
| [Configuration Guide](../guides/configuration-guide.md) | Mental model, walkthroughs, troubleshooting, go-live checklist |
| [Examples index](../examples/index.md) | Copy-paste patterns and per-Check Set install manifests |
| [Design Specification](../reference/record-health-check-design-spec.md) | Formal runtime contract |

For merge tokens, applicability, and evaluator semantics, see the [Configuration Guide](../guides/configuration-guide.md) and [Design spec modules](../spec/index.md).

## Related

- [Configuration Guide](../guides/configuration-guide.md): mental model and walkthroughs
- [Design Specification](../reference/record-health-check-design-spec.md): formal runtime contract
- [Examples index](../examples/index.md): copy-paste patterns
