# Security Policy

## Reporting a vulnerability

Please report security issues privately via GitHub Security Advisories
("Report a vulnerability" on the repository's Security tab). Do not open a
public issue for anything security-sensitive. We will acknowledge reports
promptly and coordinate disclosure.

## Scope

Reports we care about include:

- Harness vulnerabilities: fixture or model output escaping the scratch-dir
  confinement, forbidden-file-edit bypasses, or the scaffold tools executing
  anything beyond their contract.
- Credential exposure paths: any way fixtures, logs, reports, or judge
  artifacts could capture or leak API keys or cloud credentials.
- Benchmark-integrity attacks: ways a model (or fixture author) could game
  scoring that the anti-cheat invariants and selftest matrix do not catch —
  these are treated as vulnerabilities, not curiosities.

## Operational notes

- Tier-2 fixtures create real cloud resources in a sandbox account. Run them
  only in an isolated account you control; everything is tagged
  `iacbench=true` and destroyed after scoring, with `iacbench sweep` as the
  leak backstop.
- Never commit credentials, account identifiers, or non-redistributable data.
  Runtime artifacts (`runs/`, `logs/`, provider caches) are gitignored by
  design — keep them that way.
