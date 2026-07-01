---
description: "AWS Well-Architected Framework best practices - general security, reliability, performance, cost optimization, and operational excellence standards"
globs: ["**/infrastructure/**", "**/*.tf", "**/*.yml", "**/*.yaml", "**/*.json"]
alwaysApply: false
---

## Persona: AWS Solutions Architect
- **Role:** Senior Cloud Architect specializing in secure, scalable, privacy-preserving applications. **Philosophy:** "Security by design, defense in depth, least privilege."
- **Traits:** Security-first mindset, compliance-aware, automation-focused, cost-conscious without compromising security, observability-obsessed

---

# AWS General Best Practices

This file contains general AWS best practices aligned with the [AWS Well-Architected Framework](https://pages.awscloud.com/rs/112-TZM-766/images/AWS_Well-Architected_Framework.pdf). These practices apply across all AWS services and infrastructure.

**For service-specific patterns:** See `aws-fargate-best-practices.mdc`, `aws-rds-best-practices.mdc`, `aws-opensearch-best-practices.mdc`, `aws-cloudwatch-best-practices.mdc`

**For project-specific AWS patterns:** See project-specific rules file or project-conventions.md

**For universal anti-patterns:** See `general-llm-anti-patterns.mdc`

**CRITICAL:** Security and Operational Excellence are generally not traded-off against other pillars.

---

## Category 1: Security Pillar (CRITICAL)

### 1.1 Identity and Access Management (IAM) (CRIT)

**CRITICAL:** Implement least privilege access control. Never use long-term credentials in application code.

❌ Bad: `AWS_ACCESS_KEY_ID = "AKIA..."` (hardcoded), Fargate tasks using IAM users with access keys, IAM policies with `"Action": "*"`, `"Resource": "*"`
✅ Good: IAM roles for Fargate tasks (task execution role + task role), least privilege policies (specific actions/resources), MFA required for console access, quarterly access reviews
⚠️ Why: Credentials in code exposed in version control/logs/container images; overly permissive policies increase attack surface; missing MFA enables credential theft
🔧 Fix: Use IAM task roles for Fargate, AWS Secrets Manager for secrets, grant only required permissions, enable MFA for all users, review access quarterly
📍 See: `general-llm-anti-patterns.mdc` section 5.1

**Detect:** Hardcoded `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`, access keys in environment variables, `"Action": "*"` policies, no MFA enforcement, IAM roles with excessive permissions, unused access keys (>90 days)

---

### 1.2 Network Security (CRIT)

**CRITICAL:** All resources must be in private subnets within a VPC. Public access must be explicitly blocked unless absolutely necessary.

❌ Bad: RDS `PubliclyAccessible = true`, OpenSearch domain without VPC configuration, Fargate tasks in public subnets, security groups with `0.0.0.0/0` ingress (except ALB from specific sources)
✅ Good: All resources in private subnets, security groups with least privilege (specific IPs/CIDR or security group references), RDS `PubliclyAccessible = false`, OpenSearch domain in VPC, VPC endpoints for AWS services (S3, CloudWatch Logs, Secrets Manager)
⚠️ Why: Public subnets expose resources to internet; open security groups allow unauthorized access; VPC endpoints keep traffic within AWS network for privacy/security
🔧 Fix: Deploy resources in private subnets, disable public accessibility, restrict security groups to specific sources, use VPC endpoints for AWS service access
📍 See: `general-llm-anti-patterns.mdc` section 5.2
**Detect:** Resources with public IPs, security groups with `0.0.0.0/0` ingress, OpenSearch domains without VPC config, RDS `PubliclyAccessible = true`, Fargate tasks in public subnets, missing VPC endpoints

---

### 1.3 Data Encryption (CRIT)

**CRITICAL:** All data must be encrypted at rest and in transit. For privacy-preserving applications, encryption is non-negotiable.

❌ Bad: RDS without encryption at rest, OpenSearch without encryption at rest, unencrypted connections (no TLS/SSL), default AWS managed keys instead of customer-managed KMS keys
✅ Good: RDS encryption at rest with customer-managed KMS key, OpenSearch encryption at rest with customer-managed KMS key, all connections use TLS 1.2+ (RDS, OpenSearch, ALB), ALB with SSL/TLS certificates (ACM), CloudWatch Logs encryption enabled, KMS key rotation enabled
⚠️ Why: Unencrypted data vulnerable to unauthorized access; encryption protects data if storage compromised; customer-managed keys provide control/auditability
🔧 Fix: Enable encryption at rest during resource creation (cannot enable after for RDS), enable TLS for all connections, use customer-managed KMS keys, enable key rotation
📍 See: `general-llm-anti-patterns.mdc` section 5.1
**Detect:** RDS `StorageEncrypted = false`, OpenSearch domains without encryption settings, non-HTTPS connections to ALB, missing TLS in connection strings, default KMS keys used, CloudWatch log groups without encryption, KMS key rotation disabled

---

### 1.4 Secrets Management (CRIT)

**CRITICAL:** Never store secrets (passwords, API keys, tokens) in code, environment variables, or configuration files. Use AWS Secrets Manager or Parameter Store.

❌ Bad: `DATABASE_PASSWORD = os.environ.get('DB_PASSWORD')` (secrets in env vars), secrets hardcoded in Dockerfiles/container images, secrets in version control
✅ Good: AWS Secrets Manager for database credentials, IAM task role has permission to read specific secrets only, automatic secret rotation (RDS master password), secrets versioned and audited
⚠️ Why: Hardcoded secrets are security vulnerabilities; Secrets Manager provides encryption/rotation/audit logging; environment variables visible in task definitions/logs
🔧 Fix: Migrate all secrets to AWS Secrets Manager, use IAM roles to access secrets, enable automatic rotation, never commit secrets to version control
📍 See: `general-llm-anti-patterns.mdc` section 5.1

**Detect:** Secrets in environment variables, secrets in code/config files, secrets in Dockerfiles/build artifacts, missing IAM permissions for Secrets Manager, secrets in CloudWatch Logs, secrets without rotation, secrets in git history

---

### 1.5 Monitoring and Auditing (CRIT)

**CRITICAL:** All API calls and resource changes must be logged and monitored. Security events must trigger alerts.

❌ Bad: CloudTrail disabled or single-region only, CloudWatch Logs not encrypted, no alarms for failed authentication attempts, log retention <90 days, CloudTrail log file validation disabled
✅ Good: CloudTrail enabled in all regions (multi-region trail), CloudTrail log file validation enabled, CloudWatch Logs encryption enabled, CloudWatch alarms for security events (failed IAM auth, unauthorized API calls, root account usage), log retention 90 days minimum (1 year for compliance), SNS topics for security alerts
⚠️ Why: CloudTrail provides audit trail of all AWS API calls; missing logs prevent security monitoring/compliance; alarms enable rapid response to security events
🔧 Fix: Enable CloudTrail for all regions, enable log file validation, encrypt logs, create security alarms, configure SNS notifications, enable AWS Config
📍 See: `general-llm-anti-patterns.mdc` section 11.4
**Detect:** CloudTrail disabled or single-region only, missing CloudWatch alarms for security events, log retention <90 days, no log encryption, missing AWS Config rules, CloudTrail log file validation disabled

---

## Category 2: Reliability Pillar

### 2.1 High Availability (HA) Configuration (CRIT)

**CRITICAL:** Production workloads must be highly available with automated failover capabilities.

❌ Bad: RDS single-AZ deployment in production, Fargate service with desired count = 1, OpenSearch domain with single availability zone, no automated backups
✅ Good: RDS Multi-AZ deployment enabled for production, Fargate service minimum desired count = 2 (across AZs), OpenSearch domain with 2+ availability zones, RDS automated backups enabled (7-day minimum retention), RDS point-in-time recovery (PITR) enabled
⚠️ Why: Single-AZ deployments have single points of failure; Multi-AZ provides automatic failover and data durability; multiple availability zones prevent regional failures
🔧 Fix: Enable Multi-AZ for production databases, deploy services across multiple AZs, configure automated backups, test failover procedures
📍 See: `aws-rds-best-practices.mdc`, `aws-fargate-best-practices.mdc`

**Detect:** RDS `MultiAZ = false` in production, Fargate services with `desiredCount = 1`, single-AZ OpenSearch domains, missing automated backups, resources in single availability zone, no failover testing procedures

---

### 2.2 Health Checks and Auto Recovery (CRIT)

**CRITICAL:** All services must have health checks and automatic recovery mechanisms.

❌ Bad: Fargate tasks without health checks, health check endpoints returning 200 OK without actual checks, no automatic task replacement on health check failure, no deployment circuit breaker
✅ Good: Fargate task health checks configured (HTTP or command-based), application health check endpoint validates (database connectivity, OpenSearch connectivity, critical dependencies), ALB health checks configured, Fargate service auto-scaling based on health metrics, CloudWatch alarms for service health, deployment circuit breaker enabled
⚠️ Why: Without health checks, unhealthy services continue serving traffic; automatic recovery prevents extended outages; circuit breakers prevent cascading failures
🔧 Fix: Configure health checks in task definitions, implement application health endpoints, configure auto-scaling, enable circuit breaker, test health check behavior
📍 See: `aws-fargate-best-practices.mdc`

**Detect:** Missing health check configuration, health checks that don't validate dependencies, no auto-scaling configured, missing CloudWatch alarms, no deployment circuit breaker, health check grace period too short (<60 seconds)

---

### 2.3 Backup and Recovery (CRIT)

**CRITICAL:** Automated backups must be enabled with tested recovery procedures.

❌ Bad: Manual backup process, backups stored in same region as primary data (no disaster recovery), no backup restoration testing, backup retention period too short (<7 days), backups not encrypted
✅ Good: RDS automated backups with 7-day retention (minimum), RDS manual snapshots before major changes, OpenSearch automated snapshots to S3 (daily), backup restoration tested quarterly, disaster recovery plan documented, backup encryption enabled
⚠️ Why: Backups essential for disaster recovery/compliance; automated backups ensure consistency; tested recovery procedures ensure backups work when needed
🔧 Fix: Enable automated backups, set appropriate retention (7+ days), enable backup encryption, test restore procedures quarterly, document recovery procedures
📍 See: `aws-rds-best-practices.mdc`, `aws-opensearch-best-practices.mdc`

**Detect:** No automated backups configured, missing backup retention policies, no backup restoration testing records, backups only in single region, backup retention <7 days, unencrypted backups, missing backup monitoring alarms

---

## Category 3: Performance Efficiency Pillar

### 3.1 Resource Right-Sizing (CRIT)

**CRITICAL:** Resources must be right-sized based on actual usage patterns. Over-provisioning wastes money; under-provisioning causes failures.

❌ Bad: Fargate tasks with excessive CPU/memory (not based on metrics), RDS instance types chosen without performance testing, no CloudWatch metrics to guide sizing decisions, static resource allocation without auto-scaling
✅ Good: Start with minimum viable resources, scale up based on metrics, CloudWatch metrics monitored (CPU utilization target 70%, memory utilization target 80%), auto-scaling configured for Fargate services, RDS instance sizing based on utilization metrics, performance testing before production deployment
⚠️ Why: Over-provisioning wastes costs; under-provisioning causes failures and poor performance; right-sizing optimizes cost and performance
🔧 Fix: Profile application resource usage, monitor CloudWatch metrics, set CPU/memory based on actual needs, configure auto-scaling, review resource usage quarterly
📍 See: `aws-fargate-best-practices.mdc`, `aws-rds-best-practices.mdc`

**Detect:** Resources with consistently low utilization (<30%), resources with high utilization (>90%) causing throttling, no CloudWatch metrics dashboard, missing auto-scaling configuration, resources sized without metrics, no performance testing records

---

### 3.2 Connection Pooling and Caching (CRIT)

**CRITICAL:** Database connections must be pooled. Frequently accessed data should be cached.

❌ Bad: Creating new database connection per request, no connection pooling configured, OpenSearch queries without caching, no application-level caching, RDS connection limit reached
✅ Good: Database connection pooling (SQLAlchemy pool: `pool_size=10, max_overflow=20, pool_pre_ping=True`), RDS `max_connections` parameter tuned for instance type, OpenSearch query result caching enabled where appropriate, application-level caching for frequently accessed data
⚠️ Why: Creating connections per request is inefficient and can exhaust connection limits; connection pooling reuses connections; caching reduces database/API load
🔧 Fix: Use connection pools (SQLAlchemy, psycopg2 pool), configure pool size based on concurrency, monitor connection pool usage, implement application-level caching
📍 See: `aws-rds-best-practices.mdc`

**Detect:** New connection created per request, no connection pool configuration, RDS connection errors in logs, missing caching layer, RDS connection count at maximum, no connection pool monitoring

---

## Category 4: Cost Optimization Pillar

### 4.1 Resource Tagging and Cost Allocation (CRIT)

**CRITICAL:** All resources must be tagged for cost allocation and management.

❌ Bad: Resources without tags, inconsistent tag naming conventions, no cost allocation tags (Environment, Project, Team), resources from different environments mixed (dev/staging/prod in same account)
✅ Good: Consistent tagging strategy (`Environment: dev/staging/prod`, `Project: project-name`, `Service: web/crawler/indexer`), all resources tagged, cost allocation tags enabled in AWS Cost Explorer, regular cost reviews (monthly), cost anomaly detection enabled
⚠️ Why: Tags enable cost allocation, resource management, and compliance reporting; untagged resources are unmanaged; cost anomaly detection identifies unauthorized usage
🔧 Fix: Define tagging strategy, enforce tags via AWS Config, use consistent tag keys/values, review regularly, enable cost allocation tags
**Detect:** Untagged resources, inconsistent tag names/values, no cost allocation reports, missing cost monitoring, resources without required tags (Environment, Project)

---

### 4.2 Reserved Capacity and Savings Plans (CRIT)

**CRITICAL:** For predictable workloads, use Reserved Instances or Savings Plans to reduce costs.

❌ Bad: All resources on-demand (no reserved capacity), Reserved Instances purchased without usage analysis, no cost optimization review process
✅ Good: Analyze usage patterns before purchasing Reserved Instances, use Reserved Instances for RDS instances (1-year or 3-year terms), Compute Savings Plans for Fargate (if applicable), start with on-demand, purchase Reserved Instances after usage patterns established (3-6 months)
⚠️ Why: Reserved capacity provides significant cost savings (up to 72% discount); on-demand is expensive for steady workloads; purchasing without analysis wastes money
🔧 Fix: Analyze workload patterns, purchase Reserved Instances for steady workloads, use Savings Plans for flexibility, review utilization regularly
**Detect:** 100% on-demand usage for stable workloads, no Reserved Instance purchases after 6+ months of stable usage, missing cost optimization reviews, Reserved Instances with low utilization

---

### 4.3 Data Transfer Cost Optimization (CRIT)

**CRITICAL:** Minimize data transfer costs by using VPC endpoints and optimizing data flow.

❌ Bad: Internet egress for AWS service calls (S3, CloudWatch Logs), unnecessary data transfer between regions, OpenSearch queries fetching full documents instead of just IDs
✅ Good: VPC endpoints for S3 Gateway endpoint (free), CloudWatch Logs Interface endpoint, Secrets Manager Interface endpoint, application optimizations (OpenSearch returns only post IDs, batch operations where possible), monitor data transfer costs in Cost Explorer
⚠️ Why: Internet egress charges add up quickly; VPC endpoints reduce data transfer costs and improve security; optimizing queries reduces data transfer
🔧 Fix: Create VPC endpoints for required AWS services, optimize application queries, use CloudFront for static content, monitor data transfer costs

**Detect:** Missing VPC endpoints causing internet egress, high data transfer costs in billing, inefficient query patterns (fetching full documents from OpenSearch), no data transfer cost monitoring

---

## Category 5: Operational Excellence Pillar

### 5.1 Infrastructure as Code (IaC) (CRIT)

**CRITICAL:** All infrastructure must be defined as code. Manual changes are forbidden.

❌ Bad: Manual infrastructure changes via AWS Console, infrastructure not version controlled, no infrastructure change review process, hardcoded values in IaC (region, account IDs), missing infrastructure documentation
✅ Good: All infrastructure defined in Terraform or CloudFormation, infrastructure code in version control (Git), infrastructure changes via pull requests with review, parameterized IaC (variables for regions, environments), infrastructure documentation (README.md in infra repo), Terraform state stored in S3 with DynamoDB locking
⚠️ Why: Manual changes are not reproducible, not auditable, and lead to configuration drift; IaC ensures consistency and enables version control
🔧 Fix: Define all resources in IaC, commit to version control, use IaC for all changes, document infrastructure, use CI/CD for deployments
**Detect:** Manual console changes, infrastructure not in version control, hardcoded values in IaC, missing infrastructure documentation, no CI/CD pipeline for infrastructure changes, Terraform state not in S3/DynamoDB

---

### 5.2 Deployment Automation (CRIT)

**CRITICAL:** Deployments must be automated with rollback capabilities.

❌ Bad: Manual deployments (SSH into containers, manual updates), no deployment pipeline, no blue/green or canary deployment strategy, no rollback mechanism, deployments during business hours without testing
✅ Good: CI/CD pipeline for deployments (GitHub Actions, GitLab CI, AWS CodePipeline), automated testing before deployment, blue/green or canary deployment strategy for Fargate, automated rollback on health check failures, deployment during low-traffic windows, deployment runbooks documented
⚠️ Why: Manual deployments are error-prone; automation ensures consistency and enables rollback; blue/green deployments reduce risk
🔧 Fix: Implement CI/CD pipeline, use blue/green deployments, automate testing and rollback, schedule deployments during low-traffic periods, document procedures
📍 See: `aws-fargate-best-practices.mdc`

**Detect:** Manual deployment processes, no CI/CD pipeline, missing deployment strategies, no rollback capability, deployments during business hours, missing deployment documentation

---

### 5.3 Monitoring and Alerting (CRIT)

**CRITICAL:** Comprehensive monitoring and alerting must be in place before production deployment.

❌ Bad: No CloudWatch dashboards, missing alarms for critical metrics, alert fatigue (too many alarms, no action taken), no application-level metrics (only infrastructure metrics), logs not centralized or searchable
✅ Good: CloudWatch dashboards for service health, database performance, search performance, application metrics, CloudWatch alarms for critical metrics (service down, high error rate >5%, high latency p95 >1s), application-level metrics (request count/latency, error rates by endpoint), structured logging (JSON format), SNS topics for alerts, on-call rotation and escalation procedures
⚠️ Why: Without monitoring, issues go undetected; missing alarms delay incident response; alert fatigue reduces effectiveness; application metrics provide business visibility
🔧 Fix: Create CloudWatch dashboards, set up alarms for critical metrics, implement structured logging, configure SNS notifications, establish on-call procedures
📍 See: `aws-cloudwatch-best-practices.mdc`

**Detect:** Missing CloudWatch dashboards, no alarms configured, logs not structured, missing application metrics, no SNS topic for alerts, no on-call procedures

---

## References

### AWS Documentation
- [AWS Well-Architected Framework](https://pages.awscloud.com/rs/112-TZM-766/images/AWS_Well-Architected_Framework.pdf)
- [AWS IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)
- [VPC Security Best Practices](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_Security.html)
- [RDS Encryption](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Overview.Encryption.html)
- [AWS Secrets Manager Best Practices](https://docs.aws.amazon.com/secretsmanager/latest/userguide/best-practices.html)
- [CloudTrail Best Practices](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/cloudtrail-best-practices.html)
- [ECS Best Practices](https://docs.aws.amazon.com/AmazonECS/latest/bestpracticesguide/intro.html)
- [RDS Best Practices](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_BestPractices.html)
- [CloudWatch Best Practices](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/cloudwatch_best_practices.html)
- [Terraform Best Practices](https://www.terraform.io/docs/cloud/guides/recommended-practices/index.html)

---

*This file consolidates general AWS best practices from the AWS Well-Architected Framework. For service-specific patterns, see the dedicated service files. For project-specific AWS requirements, see project-specific rules file or project-conventions.md.*
