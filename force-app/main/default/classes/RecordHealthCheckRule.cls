/**
 * @author Gautam Kolan (https://github.com/gkolan)
 * SPDX-License-Identifier: Apache-2.0
 */

public interface RecordHealthCheckRule {
  RecordHealthCheckResult evaluate(RecordHealthCheckContext context);
}
