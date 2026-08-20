# What we consider good OpenTofu

**Owner: Chris. Living document — amend as views sharpen.** This is the authoritative
definition of module quality for the judge layer: it is injected into the judge's system
prompt and its hash is recorded in every judgment, so a verdict is always attributable to a
specific edition of this document. It is NEVER shown to candidate models (same rule as the
rubric — we measure what they volunteer).

Guidance for entries: concrete over abstract, and discriminating — each principle should be
something two competent modules actually differ on. Name anti-patterns explicitly. If a
preference is conditional, say what it depends on.

> The entries below are seeds distilled from prior design discussion — edit, reorder,
> delete, and extend freely; this document is only useful as your actual opinions.

## Interface design

- Variablize *concepts*, not resource attributes. An `environment` input that drives
  versioning, logging, and retention beats three boolean toggles. The module should encode
  expertise: expose the handful of inputs consumers legitimately need to vary, and have
  opinions about everything else.
- There should ideally be ~5-10 variables, however this isn't a concrete requirement.
  Some modules will be extremely simple and only require 2-4 variables, and some cloud
  services are quite complex and may require more than 10 variables. If a module exposes
  more than 10 it should be considered whether a module is overly configurable and lacks
  expertise, and similarly if it is less than 5 the module may be overly prescriptive and
  lack necessary configurability.
- Anti-pattern: the pass-through module — one variable per resource attribute, defaults
  mirroring provider defaults, no judgment encoded anywhere.

## Variables and validation

- The variables that *should* be guarded are guarded, with error messages that teach.
  Validation coverage as a percentage is meaningless; validation on the input that can
  silently break prod is everything.

## Structure

- Use locals to compute inferred values from concept inputs rather than demanding more
  inputs. Deep chains of clever expressions are their own anti-pattern; locals should make
  the module *more* readable, not show off. Situations where two (or more) variables
  can be set which conflict with each other should be avoided unless necessary.

## Scope

- Include the resources a competent operator would consider part of the job (access
  posture, encryption, cost and data hygiene) — proportionate to the use case, without
  gold-plating the brief never implied.

## Versions

- OpenTofu and provider versions should be specified. Ideally they should be pinned to a
  major version, and not a specific semver. Best is using `~>` to pin to a major or minor
  version, or using the greater than/less than operators to specify a small window of
  compatible versions. Next is a hard pin to a specific semver. Worst is anything that
  allows a new major version with potentially a breaking change.

## Inline Resource Configuration vs Separate Resources

- In some situations, a provider will support *both* inline configuration of certain
  attributes, as well as separate resources to configure the attributes. An example is 
  the `aws_security_group` resource. The rules can be defined inline via the `ingress`
  and `egress` attributes, or they can be specified via the 
  `aws_security_group_ingress_rule` and `aws_security_group_egress_rule` resources. It is
  *always* better to use separate resources. The worst case is if a module uses both
  inline and separate resources, and this should be considered a broken module.

## Outputs

- Minimal outputs, mirroring the variables philosophy: output the values that are relevant
  to *using* the module's resources from outside (ids, ARNs, endpoints, computed names).
  Exporting everything because you can is the output-side version of the pass-through
  module.

## Tagging

- Best: informative, **calculated** tagging — `managed-by: opentofu`, deployed/modified
  timestamps, and a `Name` tag (or equivalent) on resources where the service takes the
  name from a tag (much of the EC2 family). Provider-level `default_tags` is the right
  mechanism when the provider offers it; per-resource tags are bad when provider-level is
  available, and should only be used where they *must* be (service-specific quirks).
- Next best: no tagging at all.
- Worst: inventing a tagging policy the prompt never asked for — especially **requiring**
  a new input (e.g. a mandatory `team` variable) purely to feed tags (fine if the prompt
  asked for it); or omitting a `Name`-style tag on resources that are effectively nameless
  without one.

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
- Simply calling a remote public module instead of generating the code.