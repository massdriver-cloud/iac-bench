# Gemini 3.6 Flash

{{FACTS}}

## Summary

Gemini 3.6 Flash places last, with security findings in 8 of 9 attempts and one failed
gate. Its defining habit is to ship secure values as *defaults on consumer-facing inputs*
rather than as fixed properties. The S3 public access block, Cloud SQL public IP and
`ssl_mode`, and App Service HTTPS are all inputs, each with a safe default and no
validation.

That one habit drives most of its losses:

- `H1` lost in every attempt that planned (8/8);
- the interface budget lost in every attempt that planned (8/8);
- *Anti-patterns* 0 in 8/9.

Its resource mechanics, by contrast, are consistently sound.

{{SCORES}}

## Strengths

- **Resource mechanics.** *Inline vs separate resources*, *Iteration*, *Lifecycle
  meta-arguments* and *Deprecated patterns* all scored 2 in 9/9 attempts.
- **S3 hygiene,** in 3/3 attempts:
  - bucket-owner-enforced ownership;
  - a 7-day multipart abort;
  - a TLS-deny policy;
  - the regional domain output;
  - unconditional encryption.
- **Identity on Cloud SQL.** IAM authentication, workload service-account logins, managed
  databases and users, and Query Insights in 3/3 attempts.
- **Operational scope on App Service.** The planned attempts include autoscale, a staging
  slot, Application Insights and diagnostics. One adds four metric alerts.

## Weaknesses

- **S3 `H1`, 3/3.** The public access block is fed by inputs: one boolean, or all four
  flags separately.
- **Cloud SQL `H1` and `H2`, 3/3.**
  - `ipv4_enabled` is an input.
  - `ssl_mode` is an unvalidated string, and its own description lists the unencrypted mode
    (excerpt below).
  - Two attempts also let `database_flags` turn IAM authentication off.
- **App Service `H1`/`H2`, in both attempts that planned.** `https_only` is missing on the
  slot or exposed as an input, and the basic-auth publishing flags are never set.
- **Raw passwords as plain, non-sensitive inputs on Cloud SQL** (`H7`, `H10`, 3/3).
- **Failed gate (App Service, 1/3).** The outputs reference a slot resource that the module
  never declares. Five alert variables drive nothing. The judge described this as the
  signature of resources deleted to make an error go away.
- **Almost no validation.** Three `validation` blocks across all nine modules.

## Characteristic patterns

- **The largest interfaces in the field:** 22, 33 and 40 median inputs. The judge never
  gave *Interface design* a 2.
- **"Create or pass an ID" switches** on App Service for the resource group, plan,
  workspace and Application Insights.
- **Scratch files left behind** in 4/9 attempts. One Cloud SQL attempt left 13 empty
  `test*.tf` files.

{{EXCERPT}}
