---
title: "iac-bench scoring criteria"
release: "2026-10"
published: 2026-10-23
---

# iac-bench scoring criteria

**Release 2026-10 · reference**

This page defines every criterion behind an iac-bench score: each mechanical rubric item,
each expertise item, and each section the judge grades. Other articles refer to criteria by
ID, such as G002 `H11` or the judge's *Sensitive values*, and this page is where those IDs
are defined. For how the criteria combine into a score, see
[Methodology](./methodology.md).

## How to read a criterion ID

Criterion IDs are scoped to their fixture. `H1` in G001 and `H1` in G003 are different
criteria. Always read an ID together with its fixture.

| Prefix | Layer | What it covers |
|---|---|---|
| `H` | Rubric (core) | Security, data protection and operability that follow from the brief or universal practice |
| `A` | Rubric (audience fit) | **Exposure:** controls the audience needs. **Restraint:** settings it should not be handed. **Budget:** interface size. |
| `B` | Rubric (baseline) | Applies to every fixture: provider version constraints (`B1`) and descriptions (`B2`) |
| `E` | Expertise | Service-specific practices an expert adds without being asked; weight 1 each |
| *Section name* | Judge | One of 14 doctrine sections, graded 0, 1 or 2 |

**Kind** describes what an item treats as correct:

| Kind | Passes when |
|---|---|
| Hardcoded | The secure value is a literal, set unconditionally, and stays secure in every plan the sweep produces. Exposing the setting as an input fails, even when its default is safe. |
| On by default | The protection is on at defaults, with a real way to turn it off. Always on with no opt-out earns 0.75; off by default but reachable earns 0.5. |
| Offered | The capability appears at defaults, or under at least one documented input. |
| Graded | Credit for the best of several working mechanisms. |
| Budget | Full credit at or under the soft input count, falling linearly to zero at the hard count. |
| Direct | A direct check described in the item text. |

**Mandatory** items are each fixture's most severe security failures. Failing one is
reported as a *security finding* (⚠). It does not cap the score, but it marks the attempt
unshippable.

The "Full credit" column counts attempts that earned the item's full credit, out of the
attempts that passed the gate (a module that does not plan earns nothing). Partial credit
counts as not full.

## Mechanical criteria by fixture

#### G001: S3 bucket (AWS)

Mandatory (security findings): H1, H3. Total rubric weight: 86.

| ID | Weight | Kind | What passes | Full credit (attempts that planned) |
|---|---|---|---|---|
| `H1` **(mandatory)** | 18 | hardcoded | Privacy is a property, not a knob: a public access block exists with all four settings hardcoded true, its existence unconditional, and every planned instance stays fully enabled across the entire sweep. | 25/30 |
| `H3` **(mandatory)** | 14 | hardcoded | Encryption at rest is a property, not a knob: configured unconditionally in the source (dedicated resource or inline), present in every reachable plan. Which algorithm is a design choice; whether to encrypt is not. | 30/30 |
| `H6` | 6 | offered | Lifecycle cost management volunteered: transition and/or expiration rules appear at defaults or under some documented input. | 22/30 |
| `H7` | 4 | offered | Noncurrent-version handling: expiration or transition for old object versions. (Multipart-upload cleanup is expertise item E2; the same evidence is never paid twice.) | 22/30 |
| `H8` | 5 | offered | Versioning offered: enabled at defaults or under some input. | 30/30 |
| `H9` | 4 | offered | Server access logging offered: the mechanism (direct toggle or inferred from a generalized setting) is a design choice and not scored. | 11/30 |
| `A1` | 2 | Direct | Exposure: consumers can influence the bucket's name (directly, as a prefix, or through a concept such as purpose). Naming is the one input every app team obviously has. | 30/30 |
| `A2` | 2 | Direct | Restraint: no encryption key is demanded. Default S3 encryption or an optional customer-managed key both pass; a required KMS key input fails here while still earning H3, so demanding a key costs partial credit. Disabling encryption is H3's failure, not… | 30/30 |
| `A3` | 1 | Direct | Restraint: no input controls object ownership or ACLs. | 27/30 |
| `A4` | 2 | Direct | Restraint: no CDN or static-website architecture: no distribution, origin access control, or website configuration at defaults or under any documented input, and no bucket policy granting the CloudFront service. Distribution was never part of the request. | 30/30 |
| `A5` | 8 | budget | Interface budget: full credit at 8 or fewer inputs, falling linearly to zero at 16. This audience fills in "a couple of obvious inputs". A race to expose every setting in order to satisfy exposure checks is the failure this guards against: pass-through… | 14/30 |
| `H12` | 2 | graded | Consumers can add their own tags through an optional input. Full credit when that input feeds the provider's default_tags, so every resource is tagged by one setting; half credit when it is applied resource by resource, which every new resource must… | 5/30 |
| `H15` | 4 | Direct | Explicit provider configuration with a configurable region: the module declares its aws provider block and an input feeds its region (a default is fine). A standalone module that relies on the implicit provider leaves the region to whatever environment… | 12/30 |
| `H13` | 4 | Direct | Access logging actually works: some bucket policy's document grants the logging service permission to deliver. Checked in the policy expression (resolved through locals), not plan JSON: ARN-interpolating policies are unknown at plan time. | 0/30 |
| `H14` | 3 | Direct | force_destroy is accessible (per Destructive defaults): some documented input influences it, directly or inferred from a concept such as environment. Hardcoded either way, or absent entirely, leaves the consumer no way out. Influence is detected… | 23/30 |
| `B1_provider_constraints` | 5 | Direct | required_providers declared with constraints that cannot admit a new major version (~>, an upper bound, or a pin): an unconstrained provider is broken, not a style choice. | 11/30 |
| `B2_descriptions` | 2 | Direct | Every variable and output carries a description. | 30/30 |

| Expertise item | What it detects | Present |
|---|---|---|
| `E1` ownership controls | BucketOwnerEnforced ownership controls (ACLs disabled). | 30/30 |
| `E2` multipart cleanup | Aborts incomplete multipart uploads (storage garbage collection). | 26/30 |
| `E4` tls enforcement | Bucket policy denies non-TLS (aws:SecureTransport) access. | 26/30 |
| `E5` regional domain output | Outputs bucket_regional_domain_name for downstream wiring. | 30/30 |
| `E6` intelligent tiering | Uses or offers Intelligent-Tiering storage class awareness. | 6/30 |
| `E7` name uniqueness | Bucket names include a uniqueness mechanism (random suffix, account id) seen through locals, or delegate to bucket_prefix: S3's namespace is global. Kept out of the core rubric: forced suffixes have drawbacks and consumers may legitimately want exact names. | 12/30 |
| `E9` consumer access policies | Ships ready-to-attach access policies for the bucket's consumers (read-only and/or read-write), as managed IAM policies or as policy documents exposed through outputs. | 7/30 |

#### G002: Cloud SQL for PostgreSQL (GCP)

Mandatory (security findings): H1, H2. Total rubric weight: 92.

| ID | Weight | Kind | What passes | Full credit (attempts that planned) |
|---|---|---|---|---|
| `H1` **(mandatory)** | 14 | hardcoded | No public IP: the instance is reachable only on the private network. ipv4_enabled is hardcoded false, and every planned instance keeps it false across the sweep. Network reachability is never a knob, whoever the audience is. | 23/28 |
| `H2` **(mandatory)** | 10 | hardcoded | Encrypted connections are required on every planned instance. ssl_mode is either hardcoded to a mode that rejects unencrypted clients, or fed by an input whose every value the sweep plans (a bool, or a validation listing the allowed modes) with no plan… | 19/28 |
| `H3` | 6 | on by default | Deletion protection ships on with a real opt-out: either the native API-level flag or the provider-level guard. Hardcoded on in either form leaves no way to retire an instance. | 27/28 |
| `H4` | 6 | on by default | Automated backups ship on with a real opt-out (full credit); always-on with no opt-out earns partial credit: DBAs running throwaway instances lose the choice, but nothing is blocked. Hardcoded off or absent fails. | 10/28 |
| `H5` | 4 | on by default | Point-in-time recovery ships on with a real opt-out (full credit); always-on earns partial credit: retained transaction logs bill as backup storage, so test instances legitimately turn it off. Hardcoded off or absent fails. | 9/28 |
| `H6` | 4 | offered | High availability is offered: a regional (failover) instance appears at defaults or under some documented input. | 27/28 |
| `H7` | 4 | Direct | No raw credential input: no variable feeds an instance root password or a database user password. Generated secrets, write-only values from a secret store, or IAM authentication all pass; demanding the secret as a plain input fails (Sensitive values). | 25/28 |
| `H8` | 2 | Direct | Consumers can add their own labels through an optional input that reaches the instance's user_labels. Cloud SQL instances keep labels inside settings and do not inherit the provider's default_labels, and nothing else this module creates carries labels, so… | 27/28 |
| `H9` | 4 | graded | Explicit provider configuration with a configurable region. Full credit when an input feeds the google provider's region (a default is fine); half credit when an input feeds the instance's region while the provider configuration stays implicit. Neither… | 18/28 |
| `H10` | 4 | Direct | No database password stored in state: no database user's password and no instance root password is set through an attribute OpenTofu records. IAM database authentication, or write-only passwords (password_wo, root_password_wo), pass; generated or supplied… | 24/28 |
| `H11` | 4 | graded | Removing a database from the module's input does not drop its data by default. google_sql_database deletes the database when it leaves the configuration unless deletion_policy is ABANDON or the resource is protected with prevent_destroy. Full credit for a… | 4/28 |
| `A1` | 2 | Direct | Exposure: machine tier (sizing) is a DBA decision. | 28/28 |
| `A2` | 2 | Direct | Exposure: the PostgreSQL major version is a DBA decision. | 27/28 |
| `A3` | 2 | Direct | Exposure: engine flags (database_flags) can be set per instance. | 26/28 |
| `A4` | 2 | Direct | Exposure: the maintenance window (day and/or hour) is controllable. | 27/28 |
| `A5` | 2 | Direct | Exposure: the backup schedule or retention (start time, retained backups, or transaction-log retention) is controllable. | 27/28 |
| `A6` | 1 | Direct | Exposure: storage sizing (disk size or autoresize limit) is controllable. | 28/28 |
| `A7` | 2 | Direct | Exposure: the VPC network the instance attaches to is an input (required or defaulted), directly or through a data-source lookup. The brief names one network per environment; hardcoding one bakes an environment into a reusable module. | 28/28 |
| `A8` | 8 | budget | Interface budget: full credit at 25 or fewer inputs, falling linearly to zero at 35. A DBA team legitimately owns many controls (edition, zones, disks, databases, IAM users, backup placement); past 35 the interface reads as pass-through. A race to expose… | 16/28 |
| `A9` | 2 | Direct | Restraint: no networking setup. The brief says the network team owns the VPCs and has already configured private services access, so the module creates no peering range or service networking connection, at defaults or under any input. Building networking… | 28/28 |
| `B1_provider_constraints` | 5 | Direct | required_providers declared with constraints that cannot admit a new major version (~>, an upper bound, or a pin): an unconstrained provider is broken, not a style choice. | 6/28 |
| `B2_descriptions` | 2 | Direct | Every variable and output carries a description. | 28/28 |

| Expertise item | What it detects | Present |
|---|---|---|
| `E1` backups survive deletion | Automated backups outlive the instance: retain_backups_on_delete or a final backup on deletion. Cloud SQL otherwise deletes them with it. | 0/28 |
| `E2` customer managed key | A customer-managed encryption key can be supplied (encryption_key_name). Settable only at creation; needed where policy requires the company to hold and be able to revoke its keys. | 12/28 |
| `E3` iam database login | IAM database authentication is enabled (the cloudsql.iam_authentication flag), so people and workloads log in with their Google identity and a short-lived token instead of a password. | 27/28 |
| `E4` manages databases | The DBAs can declare the instance's databases through an input. Managing databases is a core DBA responsibility. | 25/28 |
| `E5` manages users | The DBAs can declare the instance's database users (IAM or built-in) through an input. Managing users is a core DBA responsibility. | 26/28 |
| `E6` iam login granted | The IAM principals given database users are also granted roles/cloudsql.instanceUser. Without it the database user exists but IAM authentication refuses the login. | 13/28 |
| `E7` workload identities | Workload service accounts can be given database logins (CLOUD_IAM_SERVICE_ACCOUNT users), not only people. The applications on GKE and Compute Engine connect with their own Google identities. | 25/28 |
| `E8` connection audit trail | Connections and disconnections are logged (log_connections and log_disconnections), so every session is recorded under the identity that opened it for the security team's audit. | 12/28 |
| `E9` query insights | Query Insights is enabled, giving the DBAs per-query load, latency and plan history in the console without running their own tooling. | 21/28 |

#### G003: App Service (Azure)

Mandatory (security findings): H1, H2. Total rubric weight: 72.

| ID | Weight | Kind | What passes | Full credit (attempts that planned) |
|---|---|---|---|---|
| `H1` **(mandatory)** | 10 | hardcoded | HTTPS only: plain-HTTP requests are redirected, hardcoded on every web app and deployment slot and present across the sweep. The provider default is off. | 22/28 |
| `H2` **(mandatory)** | 8 | hardcoded | Basic-auth publishing is disabled on every web app and deployment slot: neither FTP nor Web Deploy accepts the shared publishing credentials. Both default to ON in the provider. | 18/28 |
| `H3` | 6 | Direct | Transport stays strong: TLS for the site and the deployment (SCM) endpoint is 1.2 or newer, FTP is disabled or FTPS-only, and remote debugging is off, on every planned app and deployment slot, and none of these is fed by an input. | 25/28 |
| `H4` | 4 | hardcoded | A managed identity is attached unconditionally, so the app can reach other Azure services without stored credentials. | 26/28 |
| `H5` | 4 | offered | Health checks are offered: a health-check path is configured at defaults or under some documented input, so unhealthy instances are taken out of rotation. | 28/28 |
| `H6` | 4 | offered | Observability is offered: diagnostic settings or Application Insights appear at defaults or under some documented input. | 26/28 |
| `H7` | 3 | offered | Redundancy is offered: zone balancing on the service plan appears at defaults or under some documented input. An input that feeds it counts even when turning it on alone fails the module's own guard (zone balancing needs several instances), which a… | 24/28 |
| `H9` | 4 | offered | Rollouts are offered: a deployment slot (azurerm_linux_web_app_slot) is declared, at defaults or behind an input, so a release can be staged, warmed and swapped into production instead of replacing the running app in place. | 27/28 |
| `H8` | 2 | Direct | Tagging support is table stakes: consumers can add their own tags to the web app through an optional input. | 25/28 |
| `A1` | 2 | Direct | Exposure: the plan size (SKU) is an SRE capacity decision. | 28/28 |
| `A2` | 2 | Direct | Exposure: instance count or autoscale bounds are controllable. | 28/28 |
| `A3` | 2 | Direct | Exposure: the health-check path is set per service. | 28/28 |
| `A4` | 2 | Direct | Exposure: which container image runs is set per service. | 27/28 |
| `A5` | 2 | Direct | Exposure: application settings (environment) can be supplied. | 28/28 |
| `A6` | 2 | Direct | Restraint: no input for App Service worker internals (32-bit worker, HTTP/2, load-balancing mode, in-app MySQL). The brief's audience explicitly doesn't want to hand-tune these. | 25/28 |
| `A7` | 8 | budget | Interface budget: full credit at 20 or fewer inputs, falling linearly to zero at 30. An SRE team owns capacity, availability, health, rollout, and observability controls. A race to expose every setting in order to satisfy exposure checks is the failure… | 9/28 |
| `B1_provider_constraints` | 5 | Direct | required_providers declared with constraints that cannot admit a new major version (~>, an upper bound, or a pin): an unconstrained provider is broken, not a style choice. | 26/28 |
| `B2_descriptions` | 2 | Direct | Every variable and output carries a description. | 28/28 |

| Expertise item | What it detects | Present |
|---|---|---|
| `E1` autoscale rules | Capacity follows load: an autoscale setting scales the plan between bounds instead of a fixed instance count. | 24/28 |
| `E2` container port | The container's listening port reaches App Service (WEBSITES_PORT), so images that don't listen on port 80 receive traffic and pass health checks. | 23/28 |
| `E3` metric alerts | Metric alerts are defined (for example 5xx rate, response time or health-check status), so the SREs are paged on symptoms rather than discovering them in dashboards. | 16/28 |
| `E4` registry pull identity | Images are pulled from the container registry with the app's managed identity (container_registry_use_managed_identity), so no registry password is stored in app settings. | 18/28 |
| `E5` key vault references | Secrets reach the app as Key Vault references in app settings (@Microsoft.KeyVault(...)), resolved by the managed identity, so secret values never sit in app settings or state. | 6/28 |


## Judged criteria

The judge, Claude Opus 5.5, grades 14 sections of the quality doctrine
(`docs/good-opentofu.md`). Each grade is 0, 1 or 2, and each is the median of three
independent readings. A section with nothing to apply to earns 2. The overall judge grade
is the weighted mean, scaled to 0–100.

| Section | Weight | Earns 2 | Typical reasons for less |
|---|---|---|---|
| Sensitive values | 3 | Secrets marked `sensitive`; references to secrets accepted instead of raw values; no secret hardcoded or given as a default | Raw passwords or tokens as plain inputs; secret-bearing outputs not marked sensitive |
| Interface design | 2 | Inputs are the decisions that genuinely vary for this use case and audience, expressed as concepts; the module makes every decision the use case settles | Pass-through variables (one per attribute); knobs the audience should not own; decisions the brief leaves open, hardcoded |
| Variables and validation | 2 | Realistic mistakes are caught with teaching messages; no condition rejects a valid value; no avoidable pair of inputs that can conflict | **1:** guards are deliberate but one is missing, too strict, or the module adds a conflicting pair. **0:** essentially no validation. |
| Scope | 2 | The resources a competent operator considers part of the job (access posture, encryption, cost and data hygiene), in proportion | Missing hygiene or access pieces; architecture the brief never implied |
| Internal logic | 1 | Locals derive values from concept inputs and make the module easier to read | Duplicated blocks; clever expression chains; dead locals |
| Inline vs separate resources | 1 | Separate resources where the provider supports both forms | Inline blocks without justification; both styles for the same attributes |
| Outputs | 1 | The IDs, endpoints and names a consumer needs | Missing essentials; every attribute dumped |
| Iteration (`for_each` vs `count`) | 1 | `for_each` for multiplicity; `count` only as an on/off switch | `count` used for lists of things |
| Data sources vs inputs | 1 | A dependency's identity is taken as an input; facts about it are looked up | Asking for facts that can disagree with the dependency (an ID *and* its CIDR) |
| File layout | 1 | Variables, outputs and resources each in their place; split by concern as the module grows | One file holding everything; a large `main.tf` mixing concerns |
| Lifecycle meta-arguments | 1 | `prevent_destroy` only where no native protection exists; `ignore_changes` only for values changed outside IaC | Lifecycle used instead of a native protection attribute; unconditional `ignore_changes` |
| Documentation | 1 | **2:** accurate, and sized to the module. **1:** accurate but too thin or so heavy it becomes noise. | **0:** missing, or **any** statement wrong or out of date |
| Deprecated and escape-hatch patterns | 1 | No deprecated resource forms; no unexplained `null_resource`/`local-exec` | Legacy forms; shell escape hatches |
| Anti-patterns | 1 | None present | An input that lets a consumer silently violate the module's own security posture; an error hidden by deleting a resource; calling a remote module |

### Doctrine sections scored by the rubric, not the judge

The judge reads these sections for context but does not grade them, so a defect never costs
a module twice:

| Doctrine section | Rubric criteria |
|---|---|
| Insecure configurations | G001 `H1`, `H3`; G002 `H1`, `H2`, `H7`, `H10`; G003 `H1`–`H4` |
| Destructive defaults | G001 `H14`; G002 `H3`–`H5`, `H11` |
| Unstated assumptions | G001 `A4`; G002 `A9` (G003 has no item) |
| Tagging | G001 `H12`; G002 `H8`; G003 `H8` |
| Versions | `B1` (all fixtures) |
| Provider declarations | `B1`; G001 `H15`; G002 `H9` |
