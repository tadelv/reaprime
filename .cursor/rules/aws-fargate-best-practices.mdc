---
description: "AWS Fargate (ECS) best practices - task definitions, service configuration, container security, and logging standards"
globs: ["**/Dockerfile*", "**/docker-compose*.yml", "**/*task-definition*.json", "**/ecs*.tf", "**/fargate*.tf"]
alwaysApply: false
---

## Persona: AWS ECS/Fargate Specialist
- **Role:** Container orchestration expert. **Philosophy:** "Secure by default, right-sized by design."
- **Traits:** Security-first (non-root containers), Performance-aware (resource optimization), Observability-focused (comprehensive logging)

---

# AWS Fargate Best Practices

This file contains Fargate-specific anti-patterns and best practices for container orchestration on AWS.

**For general AWS patterns:** See `aws-general-best-practices.mdc`
**For project-specific Fargate patterns:** See project-specific rules file or project-conventions.md
**For universal anti-patterns:** See `general-llm-anti-patterns.mdc`

---

## Category 1: Task Definition Anti-Patterns (CRIT)

### 1.1 Hardcoded Secrets in Task Definitions (CRIT)

**CRITICAL:** Never pass secrets (database passwords, API keys) via environment variables in task definitions.

❌ Bad: `"environment": [{"name": "DB_PASSWORD", "value": "secret123"}]` (secrets in plaintext)
✅ Good: Use AWS Secrets Manager in task definitions (`"secrets": [{"name": "DATABASE_PASSWORD", "valueFrom": "arn:aws:secretsmanager:..."}]`), IAM task role has permission to read specific secrets only
⚠️ Why: Environment variables visible in task definitions, CloudWatch logs, and container inspection; secrets in plaintext violate security best practices
🔧 Fix: Store secrets in AWS Secrets Manager, reference using `secrets` field in task definition, use IAM permissions to restrict access
📍 See: `aws-general-best-practices.mdc` section 1.4

**Detect:** Secrets in `environment` field, plaintext passwords in CloudFormation/CDK, secrets in container environment variables, missing IAM permissions for Secrets Manager, secrets visible in CloudWatch Logs

---

### 1.2 Missing IAM Task Roles (CRIT)

**CRITICAL:** Fargate tasks must use IAM task roles, not hardcoded credentials or user access keys.

❌ Bad: Fargate task without task role, using root account credentials, passing AWS credentials via environment variables
✅ Good: Configure separate task execution role and task role (`executionRoleArn` for ECR/CloudWatch/Secrets Manager, `taskRoleArn` for application AWS API calls), separate task roles for web service and crawler/indexer service
⚠️ Why: Task execution role has different permissions than task role; separation enables least privilege; long-lived credentials are security risk
🔧 Fix: Create separate IAM roles for task execution and task, attach task role to task definition, grant only required permissions to each role
📍 See: `aws-general-best-practices.mdc` section 1.1

**Detect:** Task definitions without `taskRoleArn`, tasks using `AWS_ACCESS_KEY_ID` environment variables, tasks accessing AWS services without IAM role, task execution role used for application permissions, same IAM role used for multiple services

---

### 1.3 Unencrypted Container Images (CRIT)

**CRITICAL:** Container images must be scanned for vulnerabilities before deployment. Use ECR image scanning.

❌ Bad: Deploying images without vulnerability scanning, using `latest` tags in production, large base images with unnecessary packages
✅ Good: Enable ECR image scanning on push, fail CI/CD pipeline on high/critical vulnerabilities, use specific version tags, minimal base images (Alpine, distroless)
⚠️ Why: Vulnerable container images expose application to known exploits; privacy-preserving apps require strong security; minimal images reduce attack surface
🔧 Fix: Enable ECR image scanning, integrate scan results into CI/CD, use minimal base images, update regularly, fail builds on critical vulnerabilities
📍 See: `general-llm-anti-patterns.mdc` section 5.2

**Detect:** ECR repositories without image scanning enabled, deployments proceeding despite critical vulnerabilities, outdated base images, using `latest` tags in production, large base images (>500MB for simple apps)

---

### 1.4 Container Security (CRIT)

**CRITICAL:** Containers must run as non-root users and use minimal Linux capabilities.

❌ Bad: Container running as root user, unnecessary capabilities (NET_ADMIN, SYS_ADMIN), privileged containers enabled
✅ Good: Containers run as non-root user (`RUN useradd -m -u 1000 appuser; USER appuser`), minimal Linux capabilities, read-only root filesystem where possible, resource limits defined
⚠️ Why: Root containers have full system access; unnecessary capabilities increase attack surface; read-only filesystem prevents modifications
🔧 Fix: Create non-root user in Dockerfile, drop unnecessary capabilities, enable read-only root filesystem, set resource limits, disable privileged mode
📍 See: `general-llm-anti-patterns.mdc` section 5.2

**Detect:** Containers running as root (UID 0), privileged containers enabled, missing resource limits, containers with NET_ADMIN/SYS_ADMIN capabilities, writable root filesystem when read-only would work

---

### 1.5 Resource Limits (CRIT)

**CRITICAL:** Set appropriate CPU and memory limits for Fargate tasks; avoid over-provisioning.

❌ Bad: Tasks with excessive CPU/memory (e.g., 4 vCPU for simple web app), no resource limits defined, CPU/memory not based on profiling
✅ Good: Right-sized resources based on profiling, CPU/memory limits matching requirements, monitor CloudWatch metrics to optimize (CPU target 70%, memory target 80%), auto-scaling configured
⚠️ Why: Over-provisioning wastes costs; under-provisioning causes failures; proper sizing optimizes cost and performance
🔧 Fix: Profile application resource usage, set CPU/memory based on actual needs, use CloudWatch metrics to optimize, configure auto-scaling
📍 See: `aws-general-best-practices.mdc` section 3.1

**Detect:** Tasks with maximum resources (4 vCPU, 30GB memory) without justification, no resource monitoring, cost overruns from over-provisioning, tasks with low utilization (<30%), missing auto-scaling configuration

---

## Category 2: Service Configuration Anti-Patterns (CRIT)

### 2.1 Missing Auto-Scaling (CRIT)

**CRITICAL:** Fargate services must have auto-scaling configured based on metrics.

❌ Bad: Service with no auto-scaling (fixed desired count), auto-scaling based on single metric, no scale-down policy
✅ Good: Auto-scaling configured with target tracking policies, scale based on multiple metrics (CPU, memory, ALB request count, queue depth), scale-down policies configured, minimum desired count = 2
⚠️ Why: Fixed desired count causes over-provisioning during low traffic and under-provisioning during high traffic; auto-scaling optimizes cost and performance
🔧 Fix: Configure target tracking auto-scaling, set appropriate min/max, use multiple metrics, enable scale-down policies, test scaling behavior
📍 See: `aws-general-best-practices.mdc` section 3.1

**Detect:** Services with fixed desired count, missing auto-scaling configuration, auto-scaling disabled, no scale-down policies, desired count = 1

---

### 2.2 Missing Health Checks (CRIT)

**CRITICAL:** Fargate tasks must have health checks configured. Health check endpoints must validate critical dependencies.

❌ Bad: Tasks without health checks, health check endpoints returning 200 OK without actual checks, health checks that don't validate dependencies, health check grace period too short
✅ Good: Fargate task health checks configured (`"healthCheck": {"command": ["CMD-SHELL", "curl -f http://localhost:8888/health || exit 1"], "interval": 30, "timeout": 5, "retries": 3, "startPeriod": 60}`), application health check endpoint validates database connectivity and critical dependencies
⚠️ Why: Without health checks, unhealthy tasks continue serving traffic; health checks validate service health and dependencies; grace period prevents false positives during startup
🔧 Fix: Configure health checks in task definition, implement application health endpoints, set appropriate intervals/timeouts, configure grace period, monitor health check failures
📍 See: `aws-general-best-practices.mdc` section 2.2

**Detect:** Missing health check configuration, health checks that don't validate dependencies, health check grace period too short (<60 seconds), no automatic task replacement on failures, missing CloudWatch alarms

---

### 2.3 Missing Deployment Circuit Breaker (CRIT)

**CRITICAL:** ECS services must have deployment circuit breaker enabled to prevent cascading failures.

❌ Bad: No deployment circuit breaker, deployment continues despite health check failures, all-at-once deployments
✅ Good: Deployment circuit breaker enabled (`"deploymentCircuitBreaker": {"enable": true, "rollback": true}`), gradual rollouts, minimum healthy percent = 100, automatic rollback on deployment failure
⚠️ Why: Circuit breaker prevents cascading failures; automatic rollback prevents bad deployments from reaching production; gradual rollouts reduce risk
🔧 Fix: Enable deployment circuit breaker, configure gradual rollouts, set minimum healthy percent to 100, test rollback procedures
📍 See: `aws-general-best-practices.mdc` section 5.2

**Detect:** Missing deployment circuit breaker configuration, circuit breaker disabled, all-at-once deployments, no automatic rollback on failure, minimum healthy percent = 0

---

### 2.4 Missing Multi-AZ Deployment (CRIT)

**CRITICAL:** Fargate services must deploy tasks across multiple Availability Zones for high availability.

❌ Bad: Service in single availability zone, tasks not distributed across AZs, no task placement strategy
✅ Good: Service across multiple availability zones, task placement strategy: `spread` across AZs, minimum desired count = 2, auto-scaling distributes tasks across AZs
⚠️ Why: Single AZ deployment has single point of failure; multi-AZ provides high availability and automatic failover
🔧 Fix: Deploy services across multiple AZs, configure task placement strategy, set minimum desired count to 2+, verify AZ distribution
📍 See: `aws-general-best-practices.mdc` section 2.1

**Detect:** Services in single availability zone, tasks not distributed across AZs, missing task placement strategy, desired count = 1, no AZ distribution verification

---

### 2.5 Missing Logging Configuration (CRIT)

**CRITICAL:** Fargate tasks must send logs to CloudWatch Logs for security monitoring and troubleshooting.

❌ Bad: Tasks without CloudWatch logging, missing log group configuration, logs not encrypted, no log retention policy
✅ Good: Configure CloudWatch log driver in task definition (`"logConfiguration": {"logDriver": "awslogs", "options": {"awslogs-group": "/ecs/service-name"}}`), create log groups with retention policies, enable log encryption (KMS), structured logging (JSON format)
⚠️ Why: Without centralized logging, security incidents go undetected; logs are essential for compliance and incident response; structured logging enables querying
🔧 Fix: Configure `logConfiguration` in task definition with CloudWatch log driver, create log groups, set retention policies, enable encryption, use structured logging
📍 See: `aws-cloudwatch-best-practices.mdc`

**Detect:** Task definitions without `logConfiguration`, missing CloudWatch log groups, logs not encrypted, no log retention policy, unstructured logs (not JSON format)

---

## Category 3: Container Image Security

### 3.1 Public Container Images (CRIT)

**CRITICAL:** Container images must be stored in private ECR repositories, not public registries or public ECR.

❌ Bad: Using public Docker Hub images in production, public ECR repositories, images accessible without authentication
✅ Good: Private ECR repositories, image pull authentication via IAM, VPC endpoints for ECR access, repository policies restrict access to specific roles
⚠️ Why: Public images can be tampered with, lack access control, and may contain vulnerabilities; privacy-preserving apps require private images
🔧 Fix: Use private ECR repositories, enable image pull authentication, use VPC endpoints for ECR access, restrict repository access via policies
📍 See: `aws-general-best-practices.mdc` section 1.2

**Detect:** Public ECR repositories, Docker Hub images in production task definitions, images without authentication requirements, missing VPC endpoints for ECR access

---

### 3.2 Image Versioning (CRIT)

**CRITICAL:** Container images must use specific version tags, not `latest`.

❌ Bad: Using `latest` tags in production, hardcoded image tags in task definitions, no image versioning strategy
✅ Good: Image tags use semantic versioning or commit SHAs, parameterized image tags in IaC, automated image tagging in CI/CD pipeline
⚠️ Why: `latest` tags are unpredictable and can cause deployment issues; specific tags enable rollback and reproducibility
🔧 Fix: Use semantic versioning or commit SHAs for image tags, parameterize tags in IaC, automate tagging in CI/CD, document versioning strategy
**Detect:** `latest` tags in production task definitions, hardcoded image tags in IaC, missing image versioning strategy, no automated image tagging

---

## References

- [ECS Best Practices](https://docs.aws.amazon.com/AmazonECS/latest/bestpracticesguide/intro.html)
- [Fargate Security Best Practices](https://docs.aws.amazon.com/AmazonECS/latest/bestpracticesguide/security.html)
- [ECS Task Definition Parameters](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definition_parameters.html)
- [ECS Auto Scaling](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/service-auto-scaling.html)
- [ECS Health Checks](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-definition-healthcheck.html)
- [ECS Deployment Circuit Breaker](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/deployment-circuit-breaker.html)

---

*This file consolidates Fargate-specific best practices. For general AWS patterns, see `aws-general-best-practices.mdc`. For project-specific Fargate requirements, see project-specific rules file or project-conventions.md.*
