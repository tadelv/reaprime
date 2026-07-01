---
description: "AWS RDS PostgreSQL best practices - database configuration, connection management, authentication, backup, and performance optimization standards"
globs: ["**/*rds*.tf", "**/*rds*.yml", "**/*database*.tf", "**/*postgres*.tf"]
alwaysApply: false
---

## Persona: AWS RDS Database Specialist
- **Role:** Database infrastructure expert. **Philosophy:** "Security first, performance optimized, backups automated."
- **Traits:** Security-focused (encryption, private subnets), Performance-aware (connection pooling, indexing), Reliability-obsessed (backups, Multi-AZ)

---

# AWS RDS Best Practices

This file contains RDS PostgreSQL-specific anti-patterns and best practices for managed database services on AWS.

**For general AWS patterns:** See `aws-general-best-practices.mdc`
**For project-specific RDS patterns:** See project-specific rules file or project-conventions.md
**For universal anti-patterns:** See `general-llm-anti-patterns.mdc`

---

## Category 1: Database Configuration Anti-Patterns (CRIT)

### 1.1 Unencrypted RDS Instances (CRIT)

**CRITICAL:** RDS instances must have encryption at rest enabled. This is non-negotiable for privacy-preserving applications.

❌ Bad: RDS instance without encryption at rest (`StorageEncrypted: false`), using default encryption keys instead of customer-managed KMS keys
✅ Good: Enable encryption at rest with customer-managed KMS keys (`StorageEncrypted: true, KmsKeyId: !Ref DatabaseKmsKey`), encryption enabled during instance creation (cannot be enabled after), KMS key rotation enabled, encrypted automated backups
⚠️ Why: Unencrypted databases expose sensitive data if storage is compromised; encryption at rest required for compliance; customer-managed keys provide control
🔧 Fix: Enable encryption at rest during RDS creation, use customer-managed KMS keys, enable key rotation, ensure backups are encrypted
📍 See: `aws-general-best-practices.mdc` section 1.3

**Detect:** RDS instances with `StorageEncrypted = false`, instances without KMS key configuration, unencrypted database snapshots, default KMS keys used, KMS key rotation disabled

---

### 1.2 Publicly Accessible RDS Instances (CRIT)

**CRITICAL:** RDS instances must not be publicly accessible. They must be in private subnets with no public IP.

❌ Bad: RDS instance with `PubliclyAccessible = true`, RDS in public subnet, security groups allowing `0.0.0.0/0` access
✅ Good: RDS in private subnet, `PubliclyAccessible = false`, security groups restrict to application subnet CIDR blocks or security group references, Network ACLs as additional layer
⚠️ Why: Publicly accessible databases exposed to internet; attackers can attempt brute force attacks and exploit vulnerabilities; private subnets provide network isolation
🔧 Fix: Deploy RDS in private subnets, set `PubliclyAccessible = false`, restrict security groups to application subnets only, use network ACLs for additional protection
📍 See: `aws-general-best-practices.mdc` section 1.2

**Detect:** RDS instances with `PubliclyAccessible = true`, RDS in public subnets, security groups with `0.0.0.0/0` ingress rules, database accessible from internet, missing DB subnet group configuration

---

### 1.3 Missing Multi-AZ Deployment (CRIT)

**CRITICAL:** Production RDS instances must use Multi-AZ deployment for high availability and automatic failover.

❌ Bad: Single-AZ RDS instances in production, no automatic failover, manual backup procedures, Multi-AZ disabled to save costs
✅ Good: Multi-AZ deployment enabled for production databases (`MultiAZ: true`), automatic failover configured (synchronous replication), failover tested (documented procedures), read replicas for read scaling (if needed)
⚠️ Why: Single-AZ deployments have single points of failure; Multi-AZ provides automatic failover and data durability; synchronous replication ensures data consistency
🔧 Fix: Enable Multi-AZ deployment for production databases, use read replicas for read scaling, test failover procedures, document recovery procedures
📍 See: `aws-general-best-practices.mdc` section 2.1

**Detect:** Production RDS instances with `MultiAZ = false`, single-AZ deployments for production, no failover testing procedures, missing DB subnet group (required for Multi-AZ), no documentation for failover procedures

---

### 1.4 Missing Automated Backups (CRIT)

**CRITICAL:** RDS instances must have automated backups enabled with appropriate retention periods.

❌ Bad: Automated backups disabled, short retention periods (< 7 days), backups not encrypted, no backup testing, backup window during peak traffic hours
✅ Good: Automated backups enabled with 7-day retention minimum (`BackupRetentionPeriod: 7`), backup window during low-traffic periods (`PreferredBackupWindow: "03:00-04:00"`), backup encryption enabled (matches instance encryption), point-in-time recovery (PITR) enabled, backup restoration tested quarterly
⚠️ Why: Backups essential for disaster recovery and compliance; automated backups ensure consistency; tested recovery procedures ensure backups work when needed
🔧 Fix: Enable automated backups, set retention to 7+ days, enable backup encryption, test restore procedures quarterly, schedule backups during off-peak hours
📍 See: `aws-general-best-practices.mdc` section 2.3

**Detect:** RDS instances with `BackupRetentionPeriod = 0`, automated backups disabled, unencrypted backups, no backup restoration testing records, backup retention < 7 days, backup window during business hours

---

### 1.5 Database Parameter Groups Not Customized (CRIT)

**CRITICAL:** Use custom parameter groups for RDS instances to optimize performance and security.

❌ Bad: Using default parameter group, connection limit too high (allows connection exhaustion attacks), no parameter tuning for instance type, missing audit logging parameters
✅ Good: Custom parameter groups for optimization (tuned parameters: `shared_buffers`, `max_connections` appropriate for instance type, `rds.force_ssl: "1"` require SSL connections), enhanced monitoring enabled (1-minute granularity), Performance Insights enabled for query analysis
⚠️ Why: Default parameters are generic and may not be optimal; connection limits should match instance capacity; parameter tuning improves performance
🔧 Fix: Create custom parameter groups, tune parameters for instance type, enable enhanced monitoring, enable Performance Insights, review parameter settings quarterly
**Detect:** Using default parameter group, parameters not tuned for instance type, `max_connections` too high (connection exhaustion risk), missing Performance Insights, enhanced monitoring disabled, no parameter review process

---

## Category 2: Connection and Performance Anti-Patterns (CRIT)

### 2.1 Missing Connection Pooling (CRIT)

**CRITICAL:** Database connections must be pooled. Never create new connections per request.

❌ Bad: Creating new database connection per request (`conn = psycopg2.connect(...)` per request), no connection pooling configured, RDS connection limit reached
✅ Good: Connection pooling (SQLAlchemy pool: `pool_size=10, max_overflow=20, pool_pre_ping=True`), connection pool size based on concurrent requests, RDS `max_connections` parameter tuned for instance type, connection pool monitoring (active/idle connections)
⚠️ Why: Creating connections per request is inefficient and can exhaust connection limits; connection pooling reuses connections; proper sizing prevents connection exhaustion
🔧 Fix: Use connection pools (SQLAlchemy, psycopg2 pool), configure pool size based on concurrency, monitor connection pool usage, tune RDS max_connections
📍 See: `aws-general-best-practices.mdc` section 3.2

**Detect:** New connection created per request, no connection pool configuration, RDS connection errors in logs, RDS connection count at maximum, missing connection pool monitoring, connection pool size not based on metrics

---

### 2.2 Missing Database Indexes (CRIT)

**CRITICAL:** Frequently queried columns must have indexes for performance. Missing indexes cause slow queries and poor performance.

❌ Bad: No indexes on frequently queried columns, missing indexes on foreign keys, no index on post lookup columns (id, instance), queries scanning full table (no index usage)
✅ Good: Indexes on frequently queried columns (`CREATE INDEX idx_posts_id ON posts(id); CREATE INDEX idx_posts_instance ON posts(instance);`), indexes on foreign keys (if applicable), composite indexes for multi-column queries, monitor slow queries (Performance Insights), regular index maintenance
⚠️ Why: Missing indexes cause full table scans (slow queries); indexes enable fast lookups; proper indexing improves query performance significantly
🔧 Fix: Create indexes on frequently queried columns, monitor slow queries, use Performance Insights to identify missing indexes, maintain indexes regularly
**Detect:** Queries scanning full table (EXPLAIN ANALYZE shows Seq Scan), missing indexes on lookup columns, slow queries in Performance Insights, no index maintenance process, queries with high execution time (>100ms consistently)

---

### 2.3 Missing Read Replicas for Read-Heavy Workloads (CRIT)

**CRITICAL:** For read-heavy workloads (searches), create read replicas to scale read capacity.

❌ Bad: Single database instance for read-heavy workloads, read queries on primary database (causes contention), no read replica scaling for search workloads
✅ Good: Read replicas for read-heavy workloads (searches), application routes read queries to read replicas, read replicas in different AZs for high availability, connection pooling configured for read replicas, monitor read replica lag
⚠️ Why: Single instance causes read/write contention; read replicas scale read capacity independently; proper routing improves performance
🔧 Fix: Create read replicas for read-heavy workloads, configure application to route reads to replicas, monitor replica lag, scale replicas based on read load
📍 See: `aws-general-best-practices.mdc` section 3.1

**Detect:** Read-heavy workloads (searches) on primary database, no read replicas configured, high read query latency on primary, read queries causing write contention, missing read replica monitoring

---

### 2.4 No Query Performance Monitoring (CRIT)

**CRITICAL:** Monitor database query performance to identify slow queries and optimization opportunities.

❌ Bad: No Performance Insights enabled, no slow query logging, no query performance analysis, missing CloudWatch metrics for database performance
✅ Good: Performance Insights enabled for query analysis, enhanced monitoring enabled (1-minute granularity), CloudWatch metrics monitored for CPU utilization, database connections, read/write latency, I/O throughput, slow query logging enabled (if needed), regular query performance reviews
⚠️ Why: Without performance monitoring, slow queries go undetected; Performance Insights identifies bottlenecks; monitoring enables data-driven optimization
🔧 Fix: Enable Performance Insights, enable enhanced monitoring, create CloudWatch dashboards, monitor slow queries, review performance regularly
**Detect:** Performance Insights disabled, enhanced monitoring disabled, missing CloudWatch metrics for database, no slow query analysis, no performance review process

---

## Category 3: Authentication Anti-Patterns (CRIT)

### 3.1 Weak Database Authentication (CRIT)

**CRITICAL:** Use strong database authentication. Prefer IAM database authentication or strong password policies.

❌ Bad: Weak database passwords, passwords in connection strings, no password rotation, default database users (postgres, admin), IAM database authentication disabled
✅ Good: IAM database authentication enabled for RDS (preferred), strong password policies if using password auth, password rotation via Secrets Manager (automated), no default users (custom users only), credentials stored in Secrets Manager not code
⚠️ Why: Weak authentication allows unauthorized database access; compromised credentials lead to data breaches; IAM authentication provides temporary credentials and audit logging
🔧 Fix: Enable IAM database authentication, use Secrets Manager for password rotation, enforce strong password policies, remove default users, store credentials securely
📍 See: `aws-general-best-practices.mdc` section 1.4

**Detect:** Weak passwords in connection strings, default database users (postgres, admin), no password rotation policy, IAM database authentication disabled, passwords in code or environment variables, missing Secrets Manager integration

---

### 3.2 Missing SSL/TLS for Database Connections (CRIT)

**CRITICAL:** All database connections must use SSL/TLS encryption in transit.

❌ Bad: RDS allowing non-SSL connections, application not using SSL for database connections, SSL verification disabled
✅ Good: RDS requires SSL connections (`rds.force_ssl = 1` in parameter group), application uses SSL for database connections (`sslmode='require', sslrootcert='rds-ca-bundle.pem'`), SSL certificate verification enabled
⚠️ Why: Unencrypted connections allow data interception; TLS protects data between application and database; SSL verification prevents man-in-the-middle attacks
🔧 Fix: Set `rds.force_ssl = 1` in parameter group, configure application to use SSL, enable certificate verification, use RDS CA bundle
📍 See: `aws-general-best-practices.mdc` section 1.3

**Detect:** RDS `rds.force_ssl` parameter set to `0`, application connections without SSL, SSL verification disabled, missing RDS CA bundle, non-HTTPS database connection strings

---

## Category 4: Backup and Recovery Anti-Patterns (CRIT)

### 4.1 Missing Point-in-Time Recovery (CRIT)

**CRITICAL:** Enable point-in-time recovery (PITR) for RDS instances to recover to any point within retention period.

❌ Bad: PITR disabled, automated backups enabled but PITR not available, no PITR testing
✅ Good: Point-in-time recovery enabled (automatic with automated backups), backup retention sufficient for PITR needs (7+ days), PITR restore tested (quarterly), recovery procedures documented
⚠️ Why: PITR enables recovery to specific points in time; automated backups enable PITR; tested recovery procedures ensure PITR works when needed
🔧 Fix: Enable automated backups (enables PITR), set appropriate retention, test PITR restore procedures, document recovery procedures
**Detect:** Automated backups disabled (PITR unavailable), backup retention too short for PITR needs, no PITR restore testing, missing recovery procedures documentation

---

## References

- [RDS Best Practices](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_BestPractices.html)
- [RDS PostgreSQL User Guide](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_PostgreSQL.html)
- [RDS Performance Insights](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_PerfInsights.html)
- [RDS Connection Management](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_Limits.html#RDS_Limits.MaxConnections)
- [IAM Database Authentication](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.IAMDBAuth.html)

---

*This file consolidates RDS-specific best practices. For general AWS patterns, see `aws-general-best-practices.mdc`. For project-specific RDS requirements, see project-specific rules file or project-conventions.md.*
