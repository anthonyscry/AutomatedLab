# Phase 2: Security Hardening - Context

**Gathered:** 2026-02-16
**Status:** Ready for planning

<domain>
## Phase Boundary

Eliminate hardcoded passwords, validate download checksums, secure SSH operations, and scrub credentials from logs — making lab deployments use secure defaults. No new features; this is security hygiene on existing code.

</domain>

<decisions>
## Implementation Decisions

### Password removal behavior
- Keep default password ('SimpleLab123!') in Lab-Config.ps1 but warn loudly on every run — this is a lab tool, ease of use matters
- When no password is provided via env var or parameter, prompt interactively (Read-Host -AsSecureString)
- Use hardcoded environment variable names: LAB_ADMIN_PASSWORD, LAB_SQL_PASSWORD, etc. — simple and predictable
- Resolution order: parameter > environment variable > config default (with warning) > interactive prompt

### SSH host key policy
- Use `accept-new` for first-time connections — auto-accept on first connect, reject if key changes later
- Teardown auto-clears old host keys from known_hosts so redeploy works cleanly
- SSH key generation happens automatically during bootstrap if keys don't exist
- No StrictHostKeyChecking=no anywhere in the codebase

### Claude's Discretion
- Which passwords are security-critical vs internal-only (Claude audits and determines scope)
- Where to store known_hosts file (system default vs lab-specific)
- Where to store expected checksums (in GlobalLabConfig vs separate file)
- What to do on checksum mismatch (fail-and-delete vs warn — Claude picks appropriate strictness)
- Which download operations exist and need checksums (Claude audits all download paths)
- How to handle checksum updates for new software versions
- What to redact in logs (passwords only vs all credential-like values)
- Where scrubbing applies (console, log files, run artifacts — Claude determines scope)
- Redacted value format (***REDACTED*** vs partial mask vs other)
- Whether a debug escape hatch for credential visibility makes sense

</decisions>

<specifics>
## Specific Ideas

- User wants interactive prompts when credentials are missing — not just hard failure
- Lab convenience matters: default password stays but with loud warning, not silent
- SSH should "just work" for lab lifecycle (deploy → teardown → redeploy) without manual host key management
- User trusts Claude's judgment on download checksums and log scrubbing — wants it done right but doesn't have strong preferences on specifics

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 02-security-hardening*
*Context gathered: 2026-02-16*
