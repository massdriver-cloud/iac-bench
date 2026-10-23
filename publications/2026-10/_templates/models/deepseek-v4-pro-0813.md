# DeepSeek V4 Pro

{{FACTS}}

## Summary

DeepSeek V4 Pro is close to the leading group on S3 (G001, median 82) and falls well behind
on Cloud SQL and App Service. All 9 of its modules planned. Five of the 9 had a security
finding, each caused by a security setting exposed as an input or left at an insecure
provider default.

Its most distinctive weakness is documentation that describes behavior the code does not
implement. The judge scored *Documentation* 0 in all six of its Cloud SQL and App Service
attempts.

{{SCORES}}

## Strengths

- **Every module planned** (9/9).
- **S3 baseline coverage.** Bucket-owner-enforced ownership, multipart cleanup and the
  regional domain output in 3/3 attempts, and a TLS-only policy in 2/3. The judge gave one
  S3 attempt *Scope* 2 "without unwarranted extras."
- **Dedicated resources.** *Inline vs separate resources* scored 2 in 8/9 attempts.
- **No password users on Cloud SQL.** Only IAM users are created.
- **One App Service attempt meets every core and mandatory item** (rubric 0.944). The model
  knows the settings, but applies them inconsistently.

## Weaknesses

- **Security findings (5/9):**
  - S3, one attempt: all four public-access-block settings are fed by
    `var.block_public_access` (`H1`).
  - Cloud SQL, two attempts: `ipv4_enabled` is an input. In one it defaults to `true`, so
    the defaults plan has a public IP, while the description says "Private-only
    regardless of this flag" (`H1`). In the other, `require_ssl = false` maps to
    unencrypted connections (`H1`, `H2`).
  - App Service, two attempts: the basic-auth publishing flags are never set (`H2`). One
    attempt also makes `https_only` an input (`H1`).
- **Documentation that contradicts the code.** Examples:
  - "least-requests load balancing" that is never configured;
  - a `staging_traffic` input documented to route traffic, which only feeds an output;
  - "0 disables autoresize", which it does not.
- **Lifecycle misuse.** `prevent_destroy = var.deletion_protection` in 3/3 Cloud SQL
  attempts, duplicating the native `deletion_protection` attribute. *Lifecycle
  meta-arguments* scored 0 in all three.
- **Inputs declared and never used,** in several attempts (`zone`, `allocated_ip_range`,
  `staging_traffic`, `service_tag`).

## Characteristic patterns

- **The stated posture and the actual interface disagree** (excerpt below).
- **It leans toward too many inputs.** One S3 attempt has 18 inputs, one Cloud SQL attempt
  34. *Interface design* scored 1 in 9/9.
- **Stray files on Azure,** such as `_tmp_prod.tf` and `_full_test.tfvars`, and a pinned
  `azurerm ~> 3.0` with deprecated arguments in one attempt.

{{EXCERPT}}
