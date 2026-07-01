---
description: "AWS CloudWatch best practices - logging, metrics, alarms, dashboards, and CloudTrail standards"
globs: ["**/*cloudwatch*.tf", "**/*cloudwatch*.yml", "**/*logging*.py", "**/*metrics*.py"]
alwaysApply: false
---

## Persona: AWS Observability Specialist
- **Role:** Monitoring and logging expert. **Philosophy:** "Monitor everything, alert on what matters, log for compliance."
- **Traits:** Observability-obsessed (comprehensive monitoring), Security-aware (PII redaction), Cost-conscious (log retention)

---

# AWS CloudWatch Best Practices

This file contains CloudWatch-specific anti-patterns and best practices for monitoring, logging, and alerting on AWS.

**For general AWS patterns:** See `aws-general-best-practices.mdc`
**For project-specific CloudWatch patterns:** See project-specific rules file or project-conventions.md
**For universal anti-patterns:** See `general-llm-anti-patterns.mdc`

---

## Category 1: Logging Anti-Patterns (CRIT)

### 1.1 Sensitive Data in CloudWatch Logs (CRIT)

**CRITICAL:** Never log sensitive data (passwords, API keys, PII, database credentials) to CloudWatch Logs.

❌ Bad: `logger.info(f"Database password: {password}")`, `logger.debug(f"Post content: {post.content}")` (PII exposed)
✅ Good: Redact sensitive data before logging, structured logging (JSON format), hash instance URLs
⚠️ Why: CloudWatch Logs accessible to multiple IAM users/roles; sensitive data in logs violates compliance
🔧 Fix: Redact sensitive data in application code, use log filtering, implement data masking, review log content
📍 See: `aws-general-best-practices.mdc` section 1.5

**Detect:** Passwords in logs, API keys in logs, PII in log messages, credentials in stack traces, no log redaction

---

### 1.2 Unstructured Logging (CRIT)

**CRITICAL:** All logs must be structured (JSON format) for parsing and querying with CloudWatch Logs Insights.

❌ Bad: `print("Error occurred")`, `logger.info("Processing request for user " + username)` (unstructured)
✅ Good: Structured logging (JSON format) with CloudWatchJSONFormatter, consistent format across services
⚠️ Why: Unstructured logs difficult to parse/query; structured logs enable efficient searching with CloudWatch Logs Insights
🔧 Fix: Use JSON formatters for all logs, include consistent context fields, structure logs for querying
📍 See: `general-llm-anti-patterns.mdc` section 11.1

**Detect:** Plain text logs, inconsistent log formats, missing log context, CloudWatch Logs Insights queries ineffective

---

### 1.3 Excessive Logging (CRIT)

**CRITICAL:** Avoid excessive logging that causes high costs. Use appropriate log levels and retention policies.

❌ Bad: DEBUG level logging in production, no log retention policies (logs never expire)
✅ Good: Appropriate log levels (INFO for operations, DEBUG only in dev), log retention policies (DEBUG: 7 days dev, INFO: 30 days, ERROR: 90+ days)
⚠️ Why: Excessive logging increases costs significantly; appropriate retention balances compliance and cost
🔧 Fix: Use appropriate log levels, configure retention policies, implement log filtering, monitor CloudWatch Logs costs
📍 See: `aws-general-best-practices.mdc` section 4.3

**Detect:** DEBUG level in production, no retention policies, high CloudWatch Logs costs, excessive log volume, missing log level filtering

---

### 1.4 Unencrypted CloudWatch Logs (CRIT)

**CRITICAL:** CloudWatch Logs must be encrypted at rest using KMS.

❌ Bad: CloudWatch log groups without encryption, using default encryption keys
✅ Good: CloudWatch log groups encrypted with customer-managed KMS keys (`KmsKeyId: !Ref LogsKmsKey`)
⚠️ Why: Unencrypted logs expose sensitive information; encryption at rest required for compliance
🔧 Fix: Enable encryption for CloudWatch log groups, use customer-managed KMS keys, restrict KMS key access, enable key rotation
📍 See: `aws-general-best-practices.mdc` section 1.3

**Detect:** Log groups without encryption, default encryption keys used, missing KMS key configuration, KMS key rotation disabled

---

### 1.5 Missing Log Group Configuration (CRIT)

**CRITICAL:** CloudWatch log groups must be properly configured with retention policies and encryption.

❌ Bad: Log groups created automatically without configuration, no retention policy (logs never expire)
✅ Good: Log groups created explicitly with configuration, consistent naming (`/ecs/service-name`), retention policies configured, encryption enabled
⚠️ Why: Automatic log group creation uses default settings (no retention, no encryption); explicit configuration ensures proper settings
🔧 Fix: Create log groups explicitly in IaC, configure retention policies, enable encryption, use consistent naming, apply tags
**Detect:** Log groups created automatically, no retention policy configured, missing encryption, inconsistent log group names, missing tags

---

## Category 2: Metrics and Alarms Anti-Patterns (CRIT)

### 2.1 Missing CloudWatch Alarms (CRIT)

**CRITICAL:** Critical security and operational metrics must have CloudWatch alarms configured.

❌ Bad: No alarms for failed authentication, no alarms for API errors, no alarms for service health
✅ Good: CloudWatch alarms for critical metrics (service down, high error rate >5%, high latency p95 >1s, database connection exhaustion), SNS integration for notifications
⚠️ Why: Without alarms, security incidents and operational issues go undetected; alarms enable rapid response
🔧 Fix: Create CloudWatch alarms for critical metrics, configure SNS notifications, set appropriate thresholds, test alarm responses
📍 See: `aws-general-best-practices.mdc` section 5.3

**Detect:** No CloudWatch alarms configured, missing alarms for security events, missing alarms for error rates, no SNS topic for notifications, alarm thresholds not based on metrics

---

### 2.2 Alert Fatigue (CRIT)

**CRITICAL:** Too many alarms or overly sensitive thresholds cause alert fatigue. Alarms should be actionable and meaningful.

❌ Bad: Too many alarms causing alert fatigue, alarm thresholds too sensitive (false positives), no action taken on alarms
✅ Good: Alarms for critical metrics only, alarm thresholds based on historical data, composite alarms for correlated events, alarm acknowledgment process
⚠️ Why: Alert fatigue reduces effectiveness; too many alarms desensitize teams; false positives waste time
🔧 Fix: Review alarms quarterly, remove unused alarms, adjust thresholds based on historical data, use composite alarms
**Detect:** Too many alarms (>20 per service), high false positive rate, no action taken on alarms, missing acknowledgment process, alarms not reviewed regularly

---

### 2.3 Missing Custom Application Metrics (CRIT)

**CRITICAL:** Application-level metrics must be published to CloudWatch for business visibility and monitoring.

❌ Bad: No application-level metrics (only infrastructure metrics), missing business metrics, no performance metrics
✅ Good: Custom application metrics published via `cloudwatch.put_metric_data()` with namespace, application-level metrics (business, performance, error), CloudWatch dashboards for application metrics
⚠️ Why: Infrastructure metrics don't show business health; application metrics provide business visibility
🔧 Fix: Publish custom metrics from application, create CloudWatch dashboards, set alarms on application metrics, monitor business KPIs
📍 See: `aws-general-best-practices.mdc` section 5.3

**Detect:** No custom metrics published, missing business metrics, missing performance metrics, no CloudWatch dashboards for application metrics

---

### 2.4 Missing CloudWatch Dashboards (CRIT)

**CRITICAL:** CloudWatch dashboards must be created for key metrics to enable proactive monitoring.

❌ Bad: No CloudWatch dashboards, dashboards not organized, missing critical metrics on dashboards
✅ Good: CloudWatch dashboards for service health, database performance, search performance, application metrics, dashboards organized by service, shared with team
⚠️ Why: Dashboards provide visibility into system health; missing dashboards prevent proactive monitoring
🔧 Fix: Create CloudWatch dashboards, organize by service, include critical metrics, share dashboards with team, update regularly
📍 See: `aws-general-best-practices.mdc` section 5.3

**Detect:** Missing CloudWatch dashboards, dashboards not organized, missing critical metrics, dashboards not shared, dashboards not updated regularly

---

## Category 3: CloudTrail Anti-Patterns (CRIT)

### 3.1 Missing CloudTrail Logging (CRIT)

**CRITICAL:** CloudTrail must be enabled to log all API calls for security auditing and compliance.

❌ Bad: CloudTrail disabled, CloudTrail not logging all regions, CloudTrail logs not encrypted, no log file validation
✅ Good: CloudTrail enabled for all regions (`IsMultiRegionTrail: true`), log file validation enabled, logs encrypted (KMS), logs stored in separate S3 bucket, MFA delete enabled
⚠️ Why: CloudTrail provides audit trail of all AWS API calls; missing logs hide security events; log file validation detects tampering
🔧 Fix: Enable CloudTrail for all regions, enable log file validation, encrypt logs, use separate S3 bucket, enable MFA delete
📍 See: `aws-general-best-practices.mdc` section 1.5

**Detect:** CloudTrail disabled, single-region CloudTrail only, log file validation disabled, unencrypted CloudTrail logs, CloudTrail logs in same bucket as application data

---

### 3.2 Missing CloudTrail Event Selection (CRIT)

**CRITICAL:** CloudTrail event selectors must be configured to log all necessary events.

❌ Bad: CloudTrail not logging data events (S3, Lambda), CloudTrail not logging management events, event selectors too restrictive
✅ Good: Event selectors configured for management events (all read and write), data events (S3/Lambda if needed for compliance), event selectors reviewed for completeness
⚠️ Why: Missing event types prevent complete audit trail; data events may be required for compliance
🔧 Fix: Configure event selectors for all necessary events, include management events, add data events if needed, review event selectors regularly
**Detect:** CloudTrail not logging management events, missing data events in event selectors, event selectors too restrictive, no event selector configuration

---

## Category 4: Log Retention and Cost Optimization (CRIT)

### 4.1 Missing Log Retention Policies (CRIT)

**CRITICAL:** Configure appropriate log retention periods. Never set "Never Expire" without justification.

❌ Bad: Log groups with "Never Expire" retention (`RetentionInDays: 0`), no retention policy configured, retention period too short for compliance
✅ Good: Retention set based on compliance needs (DEBUG: 7 days dev, INFO: 30 days, ERROR: 90+ days, AUDIT: 1 year), use S3/Glacier for long-term storage if needed
⚠️ Why: Unlimited retention increases costs significantly; appropriate retention balances compliance and cost
🔧 Fix: Set retention based on compliance requirements, use S3/Glacier for long-term storage, configure lifecycle policies, monitor CloudWatch Logs costs
📍 See: `aws-general-best-practices.mdc` section 4.3

**Detect:** Log groups with `RetentionInDays: 0`, no retention policy configured, retention period too short for compliance, excessive storage costs, missing lifecycle policies

---

### 4.2 Missing Log Group Organization (CRIT)

**CRITICAL:** Log groups must be organized with consistent naming and tagging for cost allocation.

❌ Bad: Inconsistent log group naming, log groups without tags, missing cost allocation tags
✅ Good: Consistent naming convention (`/ecs/service-name`, `/opensearch/domain-name`, `/rds/db-instance-name`), tags applied for cost allocation (`Environment`, `Project`, `Service`), log groups organized by service
⚠️ Why: Inconsistent naming makes log groups hard to find; missing tags prevent cost allocation
🔧 Fix: Use consistent naming convention, apply tags to log groups, organize by service, use cost allocation tags, document naming convention
📍 See: `aws-general-best-practices.mdc` section 4.1

**Detect:** Inconsistent log group names, log groups without tags, missing cost allocation tags, log groups not organized by service, no naming convention documented

---

## References

- [CloudWatch Logs Best Practices](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/CloudWatchLogsBestPractices.html)
- [CloudWatch Logs Insights](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/AnalyzingLogData.html)
- [CloudWatch Alarms](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/AlarmThatSendsEmail.html)
- [CloudWatch Dashboards](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch_Dashboards.html)
- [CloudTrail Best Practices](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/cloudtrail-best-practices.html)

---

*This file consolidates CloudWatch-specific best practices. For general AWS patterns, see `aws-general-best-practices.mdc`. For project-specific CloudWatch requirements, see project-specific rules file or project-conventions.md.*
