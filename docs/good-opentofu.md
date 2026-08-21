# What we consider good OpenTofu

**Owner: Chris.** The authoritative definition of module quality for the judge:
each section below is graded 0–4. Grade what the module does, not what it says.
The human-facing rationale for these preferences lives in
`good-opentofu-rationale.md` and is not part of this definition.

## Interface design

- Variablize *concepts*, not resource attributes. An `environment` input that drives
  versioning, logging, and retention beats three boolean toggles. The module should encode
  expertise: expose the handful of inputs consumers legitimately need to vary, and have
  opinions about everything else.
- ~5–10 variables is the healthy range, not a hard rule: very simple modules may need
  2–4, and complex services may justify more than 10. Above 10, suspect
  overconfigurability and missing expertise; below 5, suspect overprescription.
- Anti-pattern: the pass-through module — one variable per resource attribute, defaults
  mirroring provider defaults, no judgment encoded anywhere.

## Variables and validation

- The variables that *should* be guarded are guarded, with error messages that teach.
  Validation coverage as a percentage is meaningless; validation on the input that can
  silently break prod is everything.

## Structure

- Use locals to compute inferred values from concept inputs rather than demanding more
  inputs. Deep chains of clever expressions are their own anti-pattern; locals should make
  the module *more* readable, not show off. Avoid pairs of variables that can be set to
  conflict with each other unless necessary.

## Scope

- Include the resources a competent operator would consider part of the job (access
  posture, encryption, cost and data hygiene) — proportionate to the use case, without
  gold-plating the brief never implied.

## Versions

- OpenTofu and provider version constraints are required, and the bar is: **the
  constraint must not admit a new major version.** `~>` bounds, bounded windows
  (`>= 6.0, < 7.0`), and hard semver pins all pass; unconstrained requirements or a bare
  `>=` fail.
- A lockfile never substitutes for constraints — it is a runtime artifact the consumer
  may regenerate or ignore.

## Inline Resource Configuration vs Separate Resources

- Where a provider supports *both* inline configuration and separate resources for the
  same attributes (e.g. `aws_security_group` rules inline vs
  `aws_security_group_ingress_rule`/`aws_security_group_egress_rule`), separate resources
  are the strong default: independent lifecycle per entry, no whole-list diff churn.
  Inline is acceptable only with a clear, objective, resource-specific justification
  stated in a comment. Using both styles for the same attributes is a broken module.

## Outputs

- Minimal outputs, mirroring the variables philosophy: output the values that are relevant
  to *using* the module's resources from outside (ids, ARNs, endpoints, computed names).
  Exporting everything because you can is the output-side version of the pass-through
  module.

## Tagging

- Consumers must have a way to add their own tags — an **optional** map input merged onto
  every taggable resource. A module with no way to add tags is bad.
- Calculated tags applied by the module (e.g. `managed-by`) are a plus. Never tag with
  values that change on every run (timestamps): they turn every plan into a diff.
- Provider-level `default_tags` is the right mechanism when the module is designed to run
  standalone and the provider offers it; the optional tags variable is the portable
  mechanism when the module may be consumed as a child.
- A `Name` tag (or equivalent) matters on resources that are effectively nameless
  without one.
- **Requiring** a new input purely to feed tags is scope invention — judge it under
  Unstated assumptions (fine if the prompt asked for it).

## Iteration: for_each vs count

- `for_each` whenever possible. `count` is acceptable only as an on/off switch
  (`count = condition ? 1 : 0`). Using `count` for multiplicity keys resources by index
  and invites address churn on reorder.

## Data sources vs inputs

- Bias toward data sources for facts about dependencies. Take the dependency's *identity*
  as a variable (a VPC ID), then look the rest up with a data source rather than asking
  for it. A module that requires both a VPC ID and a VPC CIDR lets the user enter a CIDR
  that doesn't actually match the VPC; a data lookup is authoritative.

## File layout

- `variables.tf` and `outputs.tf` when they're needed; a `main.tf` is good, especially
  when the resources fit comfortably in one file. Beyond roughly 150–200 lines of
  resources, or more than one clear concern, split conceptually (`bucket.tf`,
  `logging.tf`) for readability. (Cutoff is a suggested default, not a hard line.)

## Destructive defaults

- A module must never make irreversible destructive decisions on the consumer's behalf.
  Any behavior that deletes or destroys data or resources — retention policies, expiry
  rules, cleanup automation, forced replacement — must be avoidable: opt-in, or at
  minimum fully disableable, never merely postponable unless required by the resource.
- Periodic cleanup (expiry, retention, pruning) is fine — even good — but the consumer
  must be able to opt out entirely. Exposing the timeline is not enough: a deletion window
  that can only be moved, never disabled, is still a forced destructive decision. A
  sentinel that disables the rule entirely (e.g. `0` turns it off) is good design.
- Destroy-time conveniences like `force_destroy` are good when configurable — via an
  input, or inferred from a concept (e.g. enabled outside production) — and bad when
  hardcoded with no way out.

## Unstated assumptions

- Don't assume architecture the prompt never mentioned, unless the additional service
  is required in order to complete the task. Presuming an additional service,
  integration, or consumer (a CDN, a peered network, a downstream system) is scope
  invention. Encoding expertise means having opinions about *how* to build what was asked
  for, not adding architecture that wasn't.
- The line between good and bad gold-plating: **parameterizing a core capability of the
  requested service is expertise; inventing an uncommunicated use-case is scope creep.**
  Configuring a native feature of the service that was asked for — including requiring
  user input to do so — is good practice, not scope creep. Adding a capability, consumer,
  or integration the prompt never implied invents a new use-case, and is worse when the
  invention opens access paths or weakens the security posture. Judge added resources and
  inputs by which side of that line they fall on.

## Insecure Configurations

- Unless required by the prompt, the module should not encode or allow insecure 
  configurations by the user. For example, a user shouldn't be able to make a resource 
  publicly accessible, disable encryption, or turn off security measures that should 
  otherwise be on.
- The line between security and safety: **exposure** — anything touching access,
  confidentiality, or network reachability — is never a knob. **Durability and
  operational protections** (deletion protection, retention, backups) ship safe by
  default with a real opt-out; see Destructive defaults.

## Sensitive values

- Variables and outputs that carry secrets or other confidential values must be marked
  `sensitive = true`.
- Prefer accepting a *reference* to a secret (an identifier the provider can resolve)
  over the secret value itself; demanding raw credentials as plain inputs is a negative.
- Never hardcode a secret, and never give one as a variable default. `sensitive`
  controls display, not state.

## Lifecycle meta-arguments

- `prevent_destroy`: positive for stateful services (databases and the like) where the
  resource has no native deletion-protection feature. Most other uses are a negative —
  and using `lifecycle` protection when the resource offers a native protection attribute
  is itself a negative (use the resource's feature).
- `ignore_changes`: only legitimate where the value is expected to change dynamically
  outside IaC (e.g. the count field on an autoscaled resource). Anything else is almost
  surely a negative.

## Documentation

- Every variable and output has a `description`. A README is positive. Some documentation
  is good; excessive documentation is not good; no documentation is bad; incorrect or
  out-of-date documentation is really bad.

## Deprecated and escape-hatch patterns

- Deprecated resource forms are bad (e.g. legacy inline configuration that the provider
  has since split into dedicated resources).
- `null_resource` and `local-exec` are HIGHLY suspect. Without significant justification —
  a comment explaining why it is *absolutely* necessary with no workaround — treat their
  presence as a big negative.

## Provider declarations and module independence

- A module MUST declare `required_providers` with proper version constraints (see
  Versions). A module with no provider requirements is at the mercy of whatever the root
  module happens to use, with no guarantee it was written for compatibility with that
  version — treat this as broken, not as a style choice.
- Modules designed to be executed as independent deployable units are preferred over
  modules built purely to be composed into a terralith. Terraliths are an anti-pattern;
  a module that can stand alone (and carries its own provider configuration in that
  design) reflects better judgment than one that only functions as a fragment of a
  monolithic root.
- Caveat the judge should apply: a `provider "..." { }` configuration block inside a
  module has two mechanical consequences for anyone consuming it as a child module —
  tofu refuses `count`/`for_each`/`depends_on` on that module call, and deleting the
  module call from a root strands its resources at destroy time ("provider configuration
  not present"). So provider config inside a module is good judgment when the module is
  genuinely built to run standalone, and a defect when the module is clearly meant to be
  composed by callers.

## Anti-patterns (immediate credibility loss)

- Making an error disappear by deleting/commenting the resource that errored.
- Exposing an input that lets a consumer silently violate a security posture the module
  otherwise establishes.
- Calling a remote module instead of authoring the resources — the task is authoring
  the module.

## Grading weights

The judge grades each section above 0–4; the overall grade is the weighted mean of
applicable sections. Sections not listed here weigh 1.

- Insecure Configurations: 3
- Sensitive values: 3
- Destructive defaults: 3
- Interface design: 2
- Variables and validation: 2
- Scope: 2
- Unstated assumptions: 2
- Provider declarations and module independence: 2
