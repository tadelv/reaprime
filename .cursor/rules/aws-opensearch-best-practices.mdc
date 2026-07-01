---
description: "AWS OpenSearch best practices - domain configuration, index management, query optimization, access control, and audit logging standards"
globs: ["**/*opensearch*.tf", "**/*opensearch*.yml", "**/*elasticsearch*.tf"]
alwaysApply: false
---

## Persona: AWS OpenSearch Specialist
- **Role:** Search infrastructure expert. **Philosophy:** "Secure by design, optimized for performance, audited for compliance."
- **Traits:** Security-focused (VPC, FGAC, encryption), Performance-aware (sharding, ILM), Compliance-obsessed (audit logging)

---

# AWS OpenSearch Best Practices

This file contains OpenSearch-specific anti-patterns and best practices for managed search services on AWS.

**For general AWS patterns:** See `aws-general-best-practices.mdc`
**For project-specific OpenSearch patterns:** See project-specific rules file or project-conventions.md
**For universal anti-patterns:** See `general-llm-anti-patterns.mdc`

---

## Category 1: Domain Configuration Anti-Patterns (CRIT)

### 1.1 Unencrypted OpenSearch Domains (CRIT)

**CRITICAL:** OpenSearch domains must have encryption at rest and node-to-node encryption enabled.

❌ Bad: OpenSearch domain without encryption at rest, node-to-node encryption disabled, using default encryption keys instead of customer-managed KMS keys
✅ Good: Encryption at rest enabled with customer-managed KMS keys (`EncryptionAtRestOptions.Enabled: true, KmsKeyId: !Ref OpenSearchKmsKey`), node-to-node encryption enabled (`NodeToNodeEncryptionOptions.Enabled: true`), encryption enabled during domain creation (cannot be enabled after), KMS key rotation enabled
⚠️ Why: Unencrypted search indices expose sensitive data; encryption protects data at rest and in transit; privacy-preserving applications require encryption everywhere
🔧 Fix: Enable encryption at rest during domain creation, enable node-to-node encryption, use customer-managed KMS keys, enable key rotation
📍 See: `aws-general-best-practices.mdc` section 1.3

**Detect:** OpenSearch domains with `EncryptionAtRestOptions.Enabled = false`, `NodeToNodeEncryptionOptions.Enabled = false`, default KMS keys used, missing encryption configuration, encryption not enabled during creation

---

### 1.2 Publicly Accessible OpenSearch Domains (CRIT)

**CRITICAL:** OpenSearch domains must not be publicly accessible. Use VPC deployment with fine-grained access control.

❌ Bad: OpenSearch domain with public access, no VPC configuration, access policy allowing `Principal: "*"`, domain accessible from internet
✅ Good: OpenSearch in VPC (`VPCOptions` with SecurityGroupIds and SubnetIds in private subnets), fine-grained access control enabled with IAM (`AdvancedSecurityOptions.Enabled: true`), access policies with specific IAM roles (not `Principal: "*"`), no public endpoints
⚠️ Why: Public OpenSearch domains exposed to internet; attackers can access sensitive search data; VPC deployment provides network isolation
🔧 Fix: Deploy OpenSearch in VPC, disable public access, enable fine-grained access control, use IAM for access, restrict security groups to application subnets
📍 See: `aws-general-best-practices.mdc` section 1.2

**Detect:** OpenSearch domains with `VPCOptions` missing, public access enabled, access policies with `Principal: "*"`, domain accessible from internet, missing security group configuration, OpenSearch domain in public subnet

---

### 1.3 Missing Fine-Grained Access Control (CRIT)

**CRITICAL:** OpenSearch domains must use fine-grained access control (FGAC) to restrict access to indices and operations.

❌ Bad: OpenSearch without fine-grained access control, using only resource-based policies (no FGAC), master user credentials stored in application code, no distinction between read-only (web service) and read-write (crawler service) access
✅ Good: Fine-grained access control enabled with IAM (`AdvancedSecurityOptions.Enabled: true, InternalUserDatabaseEnabled: false`), IAM-based access for OpenSearch, separate IAM roles for web service (read-only) and crawler service (read-write), index-level permissions configured
⚠️ Why: Without FGAC, all users with domain access can read/write all indices; FGAC provides granular permissions; separate roles enable least privilege
🔧 Fix: Enable fine-grained access control, configure IAM roles for access, create roles with specific index permissions, use IAM roles instead of master user
📍 See: `aws-general-best-practices.mdc` section 1.1

**Detect:** OpenSearch domains with `AdvancedSecurityOptions.Enabled = false`, no IAM master user configuration, missing role mappings, master user credentials in code, same IAM role used for read and write operations, no distinction between service roles

---

### 1.4 Missing Multi-AZ Deployment (CRIT)

**CRITICAL:** Production OpenSearch domains must be deployed across multiple Availability Zones for high availability.

❌ Bad: OpenSearch domain with single availability zone, domain with less than 2 AZs, no zone awareness enabled
✅ Good: OpenSearch domain across 2+ availability zones, minimum 3 data nodes for multi-AZ (1 per AZ), dedicated master nodes enabled (3 nodes for HA), zone awareness enabled (`ZoneAwarenessEnabled: true, AvailabilityZoneCount: 3`), automated snapshots enabled
⚠️ Why: Single AZ deployments have single points of failure; multi-AZ provides high availability and data durability; zone awareness distributes data across AZs
🔧 Fix: Deploy OpenSearch across 2+ AZs, enable zone awareness, use minimum 3 data nodes, enable dedicated master nodes, configure automated snapshots
📍 See: `aws-general-best-practices.mdc` section 2.1

**Detect:** Single-AZ OpenSearch domains, domains with less than 2 AZs, zone awareness disabled, less than 3 data nodes for multi-AZ deployment, missing automated snapshots

---

### 1.5 Missing Automated Snapshots (CRIT)

**CRITICAL:** OpenSearch domains must have automated snapshots enabled for backup and recovery.

❌ Bad: No automated snapshots configured, manual snapshots only, snapshots not encrypted, no snapshot retention policy
✅ Good: Automated snapshots enabled (daily to S3), snapshots encrypted (KMS), snapshot retention policy configured, snapshot restoration tested (quarterly), S3 bucket for snapshots with lifecycle policies
⚠️ Why: Snapshots essential for disaster recovery; automated snapshots ensure consistency; tested restoration procedures ensure snapshots work when needed
🔧 Fix: Enable automated snapshots, configure S3 bucket, enable snapshot encryption, set retention policies, test restore procedures
📍 See: `aws-general-best-practices.mdc` section 2.3

**Detect:** Automated snapshots disabled, missing S3 bucket for snapshots, unencrypted snapshots, no snapshot retention policy, no snapshot restoration testing

---

## Category 2: Index and Query Anti-Patterns (CRIT)

### 2.1 Fetching Full Documents in Search Queries (CRIT)

**CRITICAL:** Search queries must return only document IDs. Fetch full documents from RDS, not from OpenSearch.

❌ Bad: OpenSearch queries fetching full documents, `_source` field included in search results, returning full post content from OpenSearch
✅ Good: Search queries return only IDs (`_source: false` in search queries), application fetches full documents from RDS using IDs, reduces data transfer costs and improves performance
⚠️ Why: Fetching full documents from OpenSearch is expensive (data transfer, storage); OpenSearch should return IDs only; RDS stores full documents more efficiently
🔧 Fix: Set `_source: false` in search queries, return only document IDs, fetch full documents from RDS, reduce data transfer costs

**Detect:** Search queries returning full documents, `_source` field included in search results, full post content returned from OpenSearch, high data transfer costs from OpenSearch, missing `_source: false` in queries

---

### 2.2 Missing Index Lifecycle Management (ILM) Policies (CRIT)

**CRITICAL:** Implement index lifecycle management (ILM) policies for index retention and optimization.

❌ Bad: No index lifecycle management policies, indices accumulating indefinitely (no retention), no hot/warm/cold tier configuration (if applicable), manual index deletion process
✅ Good: Index lifecycle management for index retention policies (delete old indices), hot/warm/cold tiers if applicable for large datasets, index rollover policies prevent single large indices, automated index deletion based on age
⚠️ Why: Indefinite index accumulation increases storage costs and reduces performance; ILM policies automate retention; old indices can be archived or deleted
🔧 Fix: Configure ILM policies, set index retention (based on compliance), implement index rollover, test ILM policies, monitor index lifecycle
**Detect:** No ILM policies configured, indices accumulating indefinitely, manual index deletion process, missing index retention policies, no index lifecycle monitoring

---

### 2.3 Over-Sharding or Under-Sharding (CRIT)

**CRITICAL:** Configure appropriate number of shards. Over-sharding wastes resources; under-sharding limits performance.

❌ Bad: Too many shards per index (over-sharding), too few shards per index (under-sharding), no sharding strategy, shard count not based on index size or query volume
✅ Good: Appropriate number of shards (1-3 shards per index for small-medium datasets), shard size target: 10-50GB per shard, shard count based on index size and query volume, monitor shard performance and adjust
⚠️ Why: Over-sharding wastes resources (each shard has overhead); under-sharding limits performance (can't parallelize queries); proper sharding optimizes performance and cost
🔧 Fix: Calculate shard count based on index size and query volume, target 10-50GB per shard, monitor shard performance, adjust shard count as needed
**Detect:** Indices with too many shards (>10 for small datasets), indices with too few shards (1 shard for large datasets), shard count not based on metrics, no sharding strategy documentation, shard size > 50GB (under-sharded) or < 1GB (over-sharded)

---

### 2.4 Missing Replica Configuration (CRIT)

**CRITICAL:** Configure appropriate replica count for high availability and query performance.

❌ Bad: No replicas configured (single copy of data), replica count too high (wastes storage), replica count not based on query volume
✅ Good: Appropriate replica count (1-2 replicas for high availability), replica count based on high availability requirements and query volume, replicas distributed across AZs
⚠️ Why: No replicas means single point of failure; appropriate replicas provide high availability and improve read performance; too many replicas waste storage
🔧 Fix: Configure 1-2 replicas for HA, adjust replica count based on query volume, balance availability and cost, distribute replicas across AZs
**Detect:** Indices with 0 replicas (no high availability), replica count too high (>2 without justification), replica count not based on metrics, missing replica configuration

---

### 2.5 Inefficient Query Patterns (CRIT)

**CRITICAL:** Optimize OpenSearch queries for performance. Avoid expensive queries and use filters instead of queries when possible.

❌ Bad: Wildcard queries on analyzed fields, using queries instead of filters (queries calculate relevance, filters are cached), no query result caching, expensive aggregations on large datasets, missing query timeout
✅ Good: Use filters instead of queries when relevance scoring not needed (filters are cached faster), query result caching enabled where appropriate, query timeout configured (prevent long-running queries), avoid wildcard queries on analyzed fields, monitor slow queries (CloudWatch metrics)
⚠️ Why: Filters are cached and faster than queries; wildcard queries are expensive; query timeouts prevent resource exhaustion; inefficient queries cause performance issues
🔧 Fix: Use filters for exact matches, enable query result caching, configure query timeouts, avoid expensive queries, monitor query performance

**Detect:** Queries used instead of filters for exact matches, wildcard queries on analyzed fields, missing query timeout, slow queries in CloudWatch metrics, no query result caching, expensive aggregations on large datasets

---

### 2.6 Missing Query Performance Monitoring (CRIT)

**CRITICAL:** Monitor OpenSearch query performance to identify slow queries and optimization opportunities.

❌ Bad: No slow query logging, missing CloudWatch metrics for query latency, no query performance analysis, missing index performance metrics
✅ Good: Slow query logging enabled (`LogPublishingOptions.INDEX_SLOW_LOGS.Enabled: true, SEARCH_SLOW_LOGS.Enabled: true`), CloudWatch metrics monitored for query latency (p50/p95/p99), indexing rate, cluster health, JVM heap usage, slow query analysis (CloudWatch Logs Insights)
⚠️ Why: Without performance monitoring, slow queries go undetected; slow query logging identifies bottlenecks; CloudWatch metrics enable data-driven optimization
🔧 Fix: Enable slow query logging, create CloudWatch dashboards, monitor query latency metrics, analyze slow queries, review performance regularly
📍 See: `aws-cloudwatch-best-practices.mdc`

**Detect:** Slow query logging disabled, missing CloudWatch metrics for OpenSearch, no query latency monitoring, missing cluster health monitoring, no slow query analysis process

---

## Category 3: Access Control Anti-Patterns (CRIT)

### 3.1 Missing Audit Logging (CRIT)

**CRITICAL:** OpenSearch domains must have audit logging enabled to track access and changes for compliance.

❌ Bad: Audit logging disabled, no CloudWatch log publishing for audit logs, missing audit trail, audit logs not encrypted
✅ Good: Audit logging enabled (`AdvancedSecurityOptions.AuditLogsEnabled: true`), CloudWatch log publishing configured for audit logs, log all API calls and data access, audit log retention configured (90+ days for compliance), audit logs encrypted (KMS)
⚠️ Why: Audit logs required for compliance and security monitoring; without logs, unauthorized access goes undetected; audit trail enables incident response
🔧 Fix: Enable audit logging in OpenSearch, configure CloudWatch log publishing, set appropriate retention, encrypt audit logs, review logs regularly
📍 See: `aws-cloudwatch-best-practices.mdc`

**Detect:** OpenSearch domains with audit logging disabled, no CloudWatch log groups for audit logs, missing audit configuration, audit logs not encrypted, audit log retention < 90 days

---

### 3.2 Missing Role-Based Access Control (CRIT)

**CRITICAL:** Use role-based access control (RBAC) to restrict access to indices and operations per service.

❌ Bad: Same IAM role used for read and write operations, no index-level permissions, web service has write access (should be read-only), crawler service has full access to all indices
✅ Good: Separate IAM roles for web service (read-only: `es:ESHttpGet, es:Describe*`) and crawler service (read-write: `es:ESHttpPost, es:ESHttpGet, es:Describe*`), index-level permissions configured, web service: read-only permissions (searches only), crawler service: read-write permissions (indexing only)
⚠️ Why: Same role for read and write violates least privilege; separate roles enable granular access control; index-level permissions restrict access to specific indices
🔧 Fix: Create separate IAM roles for each service, configure index-level permissions, restrict actions per role (read-only vs read-write), use fine-grained access control
📍 See: `aws-general-best-practices.mdc` section 1.1

**Detect:** Same IAM role used for read and write operations, web service with write access, crawler service with full domain access, missing index-level permissions, no distinction between service roles

---

## Category 4: Instance Sizing and Performance (CRIT)

### 4.1 Right-Sizing OpenSearch Instances (CRIT)

**CRITICAL:** Right-size OpenSearch instance types based on data volume, query load, and performance requirements.

❌ Bad: Instance types chosen without performance testing, instance types oversized for workload, no CloudWatch metrics to guide sizing decisions, static instance allocation without monitoring
✅ Good: Instance types selected based on index size (target 10-50GB per shard), query volume (higher query load requires larger instances), search latency requirements, storage requirements, CloudWatch metrics monitored for CPU utilization, JVM heap usage, query latency, indexing rate, start with minimum viable instances and scale up based on metrics
⚠️ Why: Over-provisioning wastes costs; under-provisioning causes performance issues; right-sizing optimizes cost and performance
🔧 Fix: Profile workload patterns, select instance types based on data volume and query load, monitor CloudWatch metrics, adjust instance types as needed
📍 See: `aws-general-best-practices.mdc` section 3.1

**Detect:** Instance types with consistently low utilization (<30%), instance types with high utilization (>90%) causing throttling, no CloudWatch metrics dashboard, instance sizing not based on metrics, missing performance testing

---

## References

- [OpenSearch Best Practices](https://docs.aws.amazon.com/opensearch-service/latest/developerguide/bp.html)
- [OpenSearch Security](https://docs.aws.amazon.com/opensearch-service/latest/developerguide/security.html)
- [OpenSearch Performance Tuning](https://docs.aws.amazon.com/opensearch-service/latest/developerguide/bp.html#bp-performance)
- [Index Lifecycle Management](https://opensearch.org/docs/latest/im-plugin/ism/index/)
- [OpenSearch Query Optimization](https://opensearch.org/docs/latest/query-dsl/)

---

*This file consolidates OpenSearch-specific best practices. For general AWS patterns, see `aws-general-best-practices.mdc`. For project-specific OpenSearch requirements, see project-specific rules file or project-conventions.md.*
