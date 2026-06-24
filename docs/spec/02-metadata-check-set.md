> [!NOTE]
> **Canonical source:** Section numbers and anchors in the [full design specification](../reference/record-health-check-design-spec.md) are stable for cross-links.

## 4. Check Set Model (`Record_Health_Check_Set__mdt`)

A Check Set defines one group of Rules for one component instance on one object.

> [!NOTE]
> Field reference (Setup labels, API names, picklist values): [Check Set fields](../metadata/check-set.md).

### 4.1 Framework limits (not configurable)

| Limit | Value | Behavior |
| ----- | ----- | -------- |
| Maximum active Rules per Check Set in one run | 25 | First 25 by `RunOrder__c` ascending, then `DeveloperName` ascending. `checksOmittedByLimit` is true when more active Rules exist. `totalAvailableCheckCount` is returned by Apex but **not displayed** in the LWC UI (the header shows a fixed “First 25 shown” badge). |
| Definition reload | Per component load or `recordId` change | `getCheckDefinitions` is **not** cacheable. Metadata edits appear on the next component load. After `connectedCallback`, a change to `recordId` also reloads definitions. A full page refresh reloads record field data as well. |
| Concurrent evaluations | Up to **5 in flight** when `StopOnSystemError__c` is false | The LWC queues all eligible checks (up to 25) but caps concurrent `evaluateCheck` Apex calls at `MAX_CONCURRENT_EVALUATIONS` (5); additional checks wait in a client-side queue. Display order remains priority-ordered via a drain buffer. When `StopOnSystemError__c` is true, checks run **sequentially** (one Apex call at a time). |
| Run isolation | Per run | LWC increments `_runToken` on each run so stale in-flight results from a prior run are discarded. |
