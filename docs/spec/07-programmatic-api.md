> [!NOTE]
> **Canonical source:** Section numbers and anchors in the [full design specification](../reference/record-health-check-design-spec.md) are stable for cross-links.

## 13. Programmatic API (`RecordHealthCheck`)

For adoption beyond the record page, `RecordHealthCheck` is the supported Apex entry point. It delegates to the same engine as the LWC. Catchable evaluation failures surface as result statuses (`ERROR`, `UNABLE_TO_EVALUATE`, etc.); uncatchable Apex governor limit exceptions behave like any other Apex API.

### Apex

```apex
RecordHealthCheckResult r = RecordHealthCheck.run(
    'Account_Data_Quality',      // Check Set DeveloperName
    'Account_DQ_BillingCity',    // Rule DeveloperName
    accountId);                  // record under test
```

Optional overload:

```apex
RecordHealthCheck.run(configName, checkName, recordId, 'ticket-12345'); // custom runId
```

| Parameter | Contract |
| --------- | -------- |
| `configName` | Check Set `DeveloperName`: required; scopes the Rule server-side. |
| `checkDeveloperName` | Rule `DeveloperName`: one Rule per call. |
| `recordId` | Record under test. |
| `runId` | Optional correlation id (for example, a ticket or batch-job id) so this run's `[RHC]` log lines group with related work. When blank, the façade generates `api-<timestamp>-<random>`. |

Checks always evaluate with the **running** user's access (`WITH USER_MODE`); to evaluate as another user, run while that user is current or wrap in `System.runAs(thatUser)` in a test.

Each call logs `RUN_INVOKED` and `RUN_COMPLETE` events through `RecordHealthCheckLogger`.

### Flow (not packaged)

There is **no packaged Flow invocable**; it was descoped for governor safety. To call the engine from Flow, build a bulk-designed Apex invocable that groups records and evaluates them within transaction limits, or drive it from scheduled/batch Apex with an intentionally small scope. Do not wrap `run(...)` in a per-record loop.

### Anonymous Apex runner

`scripts/apex/runHealthCheck.apex` loads a Check Set definition and evaluates every Rule in priority order, printing a structured report to the debug log. Set `CONFIG_NAME`, `RECORD_ID`, and optionally `RUN_ID`, then run via `sf apex run --file scripts/apex/runHealthCheck.apex`.
