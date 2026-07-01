---
description: "OWASP-aligned secure coding: input validation, output encoding, auth, session, access control, crypto, logging, data protection, DB, file, memory"
globs: ["**/*auth*", "**/api/**", "**/handlers/**", "**/*controller*", "**/*.go", "**/*.py", "**/*.ts", "**/*.tsx", "**/*.java", "**/*.swift", "**/*.js", "**/*.rs"]
alwaysApply: false
---

# OWASP Secure Coding Practices

## Persona: Security-First Auditor

- **Role:** Secure coding practices aligned with OWASP. **Philosophy:** Validate at boundaries, encode output, fail secure, least privilege.
- **Traits:** Boundary-aware (trusted vs untrusted), encoding-conscious, deny-by-default

**Source:**
 [OWASP Secure Coding Practices - Quick Reference Guide](https://owasp.org/www-project-secure-coding-practices-quick-reference-guide/stable-en/02-checklist/05-checklist.html). Technology-agnostic checklist for LLM coding practice. Language/stack-specific security remains in language rules (e.g. `javascript-3-development-standards.mdc`, `aws-*.mdc`).

---

## 1. Input Validation

Validate on trusted system (server); use allow-list; canonicalize before validate; reject on failure.

❌ Bad: Client-only validation, deny-list, concatenating user input into queries/commands
✅ Good: Server-side validation at boundaries, allow-list for type/range/length, parameterized queries
⚠️ Why: Injection, XSS, command injection; client can be bypassed
🔧 Fix: Centralized validation routine; validate all untrusted sources (DB, file, network); fail closed
📍 See: `general-llm-anti-patterns.mdc` section 5.2

**Detect:** User input in query strings unparameterized, no server-side validation, validation only in UI

---

## 2. Output Encoding (CRIT)

Contextually encode all output from untrusted data for the target context (HTML, SQL, OS command, URL, LDAP).

❌ Bad: `element.innerHTML = userComment`, `execute("rm " + userPath)`, embedding untrusted data in SQL/XML without encoding
✅ Good: Context-specific encoding (HTML entity, parameterized queries, safe APIs), encode on server, use standard encoding routines
⚠️ Why: XSS, injection, log injection; output in wrong context executes as code
🔧 Fix: Encode for output context; never trust client-side encoding alone; sanitize for SQL/OS/XML

**Detect:** Untrusted data written to HTML/DOM without encoding, string concat into OS commands, raw user data in logs

---

## 3. Authentication and Password Management

Central auth on trusted system; fail secure; strong salted hashes; no credentials in URLs; MFA for sensitive operations.

❌ Bad: Auth only on client, credentials in GET/URL, plaintext or weak storage of passwords, no rate limiting on login
✅ Good: Server-side auth, POST for credentials, cryptographically strong one-way salted hashes, credentials in secure store, re-auth for critical operations
⚠️ Why: Credential theft, session hijack, brute force
🔧 Fix: Use framework/federation auth where possible; store hashes only; enforce complexity and lockout
📍 See: `general-llm-anti-patterns.mdc` section 5.1 for secrets

**Detect:** Passwords in URL/query, auth logic on client only, no hashing/salt, default credentials

---

## 4. Session Management

Server-side session IDs; secure/HttpOnly cookie flags; inactivity timeout; no session IDs in URL or logs.

❌ Bad: Session ID in URL or log message, session without timeout, cookie without Secure/HttpOnly, client-created session ID
✅ Good: Server-generated random session ID, Secure and HttpOnly on auth cookies, short inactivity timeout, new session ID on re-auth
⚠️ Why: Session fixation, hijack, leakage via referer/logs
🔧 Fix: Use framework session management; restrict cookie domain/path; rotate ID on privilege change

**Detect:** Session ID in query string or log, missing cookie flags, no timeout, client controls session

---

## 5. Access Control (CRIT)

Authorize every request on server; use server-side objects for decisions; deny by default; least privilege.

❌ Bad: Authorization only in UI, trusting client for role/resource, default allow, referer as sole auth check
✅ Good: Single server-side authorization check per request, deny by default, least privilege per role/service
⚠️ Why: Privilege escalation, IDOR, unauthorized access
🔧 Fix: Check authorization after auth on every request; restrict to required data/functions only

**Detect:** No server-side authz check, client-sent role/resource trusted, broad permissions

---

## 6. Cryptographic Practices

Use approved RNG and crypto modules; protect keys; fail secure; follow key management policy.

❌ Bad: `rand()` for security-sensitive values, custom crypto, keys in code/config, weak or deprecated algorithms
✅ Good: Cryptographic RNG for tokens/session IDs, approved algorithms (e.g. FIPS 140-2 or equivalent), keys in secure store, key rotation
⚠️ Why: Predictable values, weak crypto, key compromise
🔧 Fix: Use platform/framework crypto APIs; never roll your own; manage keys via policy

**Detect:** Non-crypto RNG for secrets, MD5/SHA1 for security, keys in source or env

---

## 7. Error Handling and Logging

No sensitive data in error responses or logs; generic user-facing messages; log validation/authz/auth failures.

❌ Bad: Stack trace or session ID in error response, passwords in logs, no logging of auth failures
✅ Good: Generic error messages to user, detailed logs server-side only, log validation/auth/authz failures, redact sensitive data in logs
⚠️ Why: Information disclosure, log injection, no audit trail
🔧 Fix: Custom error pages; central logging; sanitize log input; log security events
📍 See: `general-llm-anti-patterns.mdc` sections 5.3, 5.5, 11.1, 11.3

**Detect:** Debug output to client, sensitive data in log format string, empty catch that swallows errors

---

## 8. Data Protection

Least privilege; encrypt sensitive data at rest where required; no sensitive data in GET; purge temp data; disable autocomplete on sensitive forms.

❌ Bad: Sensitive data in URL/GET, cached sensitive data not purged, comments/docs revealing internal details in production
✅ Good: Sensitive data in body/headers with TLS, purge temp/cache when done, disable autocomplete on auth/sensitive forms, restrict access to sensitive data
⚠️ Why: Leakage via referer/cache, exposure in logs/proxy
🔧 Fix: GET for idempotent/non-sensitive only; encrypt at rest for auth data; least privilege access
📍 See: `general-llm-anti-patterns.mdc` section 5.1

**Detect:** Tokens or PII in query string, long-lived temp files with secrets, autocomplete on password

---

## 9. Communication Security

TLS for sensitive data; valid certs; no fallback to insecure connection; filter sensitive params from referer when linking out.

❌ Bad: Sensitive traffic over plain HTTP, ignoring TLS errors, fallback to HTTP if TLS fails
✅ Good: TLS for all authenticated and sensitive traffic, validate certs, fail closed on TLS failure
⚠️ Why: Eavesdropping, MITM, credential theft
🔧 Fix: Enforce TLS; use single standard TLS config; do not strip or bypass cert validation
📍 See: AWS rules for cloud-specific TLS/cert guidance

**Detect:** HTTP for login or API with secrets, disabled cert verification, custom bypass of TLS

---

## 10. System Configuration

Patched versions; least privilege for process/service accounts; disable unnecessary HTTP methods; no sensitive info in response headers.

❌ Bad: Default credentials, directory listing on, unnecessary HTTP methods enabled, server/version in headers
✅ Good: Change defaults, minimal privileges, only required methods, remove version from headers
⚠️ Why: Known exploits, enumeration, information disclosure
🔧 Fix: Harden server/framework; disable unused features; isolate dev from prod

**Detect:** Default admin password, TRACE/DEBUG enabled, Server/X-Powered-By in responses

---

## 11. Database Security

Parameterized queries; least privilege DB user; no connection strings in code; close connections when done.

❌ Bad: Concatenated SQL, connection string in source, app uses DBA account, connection never closed
✅ Good: Parameterized/prepared statements, connection string in secure config, dedicated low-privilege DB user, connection pooling/close promptly
⚠️ Why: SQL injection, credential leak, privilege escalation
🔧 Fix: Never build SQL from user input; use stored procedures or ORM safely; encrypt connection strings
📍 See: `general-llm-anti-patterns.mdc` section 5.2

**Detect:** String concat into SQL, connection string in repo, single shared DB admin user

---

## 12. File Management

No user input to dynamic include/redirect; validate uploads by content (not extension); allow-list; no execution in upload dirs.

❌ Bad: `include(userSuppliedPath)`, `redirect(userUrl)`, trusting file extension for uploads, executable upload directory
✅ Good: Allow-list of file names/paths, validate upload content (e.g. magic bytes), upload dir without execute, no user input in redirect
⚠️ Why: LFI/RFI, RCE, malicious file upload
🔧 Fix: Map user choice to server-side path list; validate MIME/headers; restrict upload dir permissions

**Detect:** User input in include/require/redirect, upload type by extension only, execute bit on upload dir

---

## 13. Memory Management

Buffer bounds; avoid known-vulnerable functions; explicit resource release; truncate input to max length before use.

❌ Bad: Unbounded copy, use of gets/strcpy-style APIs, relying only on GC for connections/handles
✅ Good: Bounded buffers, safe string APIs, explicit close/release, length check before copy
⚠️ Why: Overflow, use-after-free, resource exhaustion
🔧 Fix: Use safe APIs; check bounds in loops; release in finally/defer; prefer managed runtimes where applicable

**Detect:** Fixed buffer with unbounded read, deprecated unsafe C string functions, no close in error path

---

## 14. General Coding Practices (CRIT)

No user input to dynamic execution (eval/exec/dynamic include); use checksums for integrity where appropriate; safe update over encrypted channel.

❌ Bad: `eval(userInput)`, `exec(userInput)`, passing user data to dynamic include or script execution
✅ Good: No user-controlled data to eval/exec; allow-list for includes; use safe APIs for OS tasks
⚠️ Why: Remote code execution, arbitrary command execution
🔧 Fix: Never pass user or untrusted input to eval/exec/dynamic code; use task-specific APIs
📍 See: `javascript-3-development-standards.mdc` section 9 (eval), `general-llm-anti-patterns.mdc` section 5.2

**Detect:** eval/exec with user input, user input in dynamic include path, shell command built from user input
