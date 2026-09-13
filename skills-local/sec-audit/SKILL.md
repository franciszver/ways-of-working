---
name: sec-audit
description: Security audit of a diff or codebase — trace untrusted data flows, report only exploitable findings with concrete exploit scenarios. Use when asked for a security review or audit, or before shipping code that handles auth, payments, or untrusted input.
---

# Security Audit Protocol

You are a local model auditing code for security. Token usage is not a concern — read every file on the data path. Rule zero: a finding without a concrete exploit scenario is noise and must be deleted. False positives destroy the report's value.

## Step 1 — MAP

List, in your notes: every entry point where untrusted data enters (HTTP handlers, CLI args, file uploads, webhooks, queue consumers) · the sensitive sinks (DB queries, shell/exec, file paths, eval/deserialize, auth decisions, logs) · where the secrets and PII live. Data coming OUT of the database that users wrote is still untrusted.

## Step 2 — TRACE

For each entry point, follow the data to its sinks. A grep hit ("uses eval", "string-built SQL") is a CANDIDATE, not a finding — trace where the value comes from and what sanitization it passes on EVERY path. You must examine at least these categories:

1. Injection: SQL/NoSQL, shell/command, path traversal, template — untrusted data concatenated into any interpreter
2. AuthN/AuthZ: authorization checked on EVERY path, not just the UI route; object IDs authorized against the caller (IDOR); JWT signature/expiry actually validated
3. Code execution: unsafe deserialization (pickle, yaml.load), eval of tainted strings
4. Secrets: hardcoded credentials, secrets in logs/errors/URLs, disabled TLS verification, non-CSPRNG tokens
5. Data exposure: PII in logs, verbose errors to clients, API responses returning extra fields
6. Web (if applicable): XSS, CSRF on state-changing endpoints, SSRF on user URLs, open redirects

## Step 3 — DO NOT REPORT

Skip these unless the user explicitly asked: DoS/resource exhaustion · rate limiting · missing hardening (headers, audit logs) · theoretical races/timing attacks · CVEs in outdated dependencies (one summary line: "update X", not per-CVE findings) · memory safety in memory-safe languages · test-only files · log spoofing · ReDoS.

## Step 4 — VERIFY EACH CANDIDATE

Write the exploit scenario: "attacker sends X → flows through Y unsanitized (file:line) → attacker achieves Z". 
- Traced end-to-end with the malicious input stated → CONFIRMED.
- Sink is real but one link untraceable → PLAUSIBLE + state exactly what would confirm it.
- No scenario → DELETE the finding.

## Step 5 — REPORT

```
SEVERITY [CONFIRMED|PLAUSIBLE] path:line — vulnerability — exploit scenario — remediation
```
- BLOCKER = directly exploitable: RCE, auth bypass, injection reaching real data, exposed secrets
- MAJOR = exploitable with realistic preconditions (needs an account, common misconfig)
- MINOR = real weakness, contained blast radius

Remediation names the STANDARD fix (parameterized queries, allowlist validation, framework escaping) — never invent a custom sanitizer. A clean report must list which entry points you traced and which categories you checked.

## Hard rules

- Allowlist validation at trust boundaries; blocklists lose.
- Do not fix during the audit — report first; fixes are a separate reviewed change.
- Secrets already in git history are exposed: remediation is rotation, not deletion.
- Do not audit code you were not asked to audit.
