# Security Policy

## Reporting a vulnerability

Please report security issues privately via GitHub Security Advisories
("Report a vulnerability" on the repository's Security tab). Do not open a
public issue for anything security-sensitive. We will acknowledge reports
promptly and coordinate disclosure.

## Scope

Reports we care about include:

- Harness vulnerabilities: fixture or model output escaping the working-directory
  confinement, or the scaffold tools executing anything beyond their contract.
- Credential exposure paths: any way fixtures, logs, reports, or judge
  artifacts could capture or leak API keys or cloud credentials.
- Benchmark-integrity attacks: ways a model (or fixture author) could game
  scoring that the rubric checks and reference matrices do not catch —
  these are treated as vulnerabilities, not curiosities.

## Operational notes

- Scoring plans against real clouds but never applies. Use read-only
  credentials for an isolated account you control.
- Never commit credentials, account identifiers, or non-redistributable data.
  Runtime artifacts (`runs/`, `logs/`, provider caches) are gitignored by
  design — keep them that way.
