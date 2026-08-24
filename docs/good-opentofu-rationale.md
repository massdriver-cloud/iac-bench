# Why we grade OpenTofu this way

Companion to `good-opentofu.md`. That document is the judge's grading anchor
and is written for a model to apply, not for humans to be persuaded by — every
word in it costs tokens on every judgment, so the defense of its preferences
lives here instead. This file is never loaded into any prompt.

Operational facts about the doctrine: it is injected into the judge's system
prompt and its sha256 is recorded in every judgment, so a verdict is always
attributable to a specific edition. It is never shown to candidate models —
like the rubric, it measures what they volunteer. Most of its preferences are
defensible as objectively better engineering; the rest are our documented
opinions, published deliberately so you can argue with the document instead of
the scores. The per-section grade table in every report exists for exactly
that: reject a preference, discount its row.

## Encoded expertise over extensive configuration

The most contestable position first. We prefer modules that variablize
*concepts* and hold opinions about everything else, and we penalize the
pass-through module — one variable per resource attribute, provider defaults
mirrored, no judgment anywhere. The strongest counterargument is that the
community's most battle-tested modules are exactly that shape, with hundreds
of inputs, and they got battle-tested for a reason: experts need escape
hatches.

Our answer: those modules are built *for experts*, and most consumers of a
platform module are not experts. A mega-module's hundreds of knobs encode only
the *relationships* between resources — which arguments wire to which — not
any opinion about how the service should be configured. Handing one to a
novice is how publicly readable data stores happen. Companies should not hand
their application teams modules that will happily create public, unencrypted
resources when the wrong two booleans meet. The expertise a module encodes is
precisely its refusal to expose those combinations.

One could argue the ideal is the opposite: a maximal pass-through module plus
an LLM that selects variables safely. We disagree, and this benchmark
deliberately measures authoring — but evaluating LLM *variable selection*
against a fixed knob-heavy module is a legitimate, different benchmark, and we
encourage anyone who holds that position to build it.

## Why remote module calls fail outright

In the evaluation, calling a registry module is answer-key evasion — the task
is generating the module, so delegating generation measures nothing. That is
enough on its own, and the scaffold prompt says so to the models. The doctrine
also holds the position on the merits, per the section above: "just use the
community module" is often the responsible choice for an expert team, and
still the wrong thing to hand a layman.

## Terraliths and module independence

Industry-default guidance says reusable modules should declare
`required_providers` but carry no provider configuration, so they can be
composed into a shared root. We knowingly invert that default. The composed
root — the terralith — is the anti-pattern we are grading against: one state
file, one blast radius, one lifecycle shared by everything in it. A module
built as an independently deployable unit has its own state, its own blast
radius, and its own lifecycle. The doctrine keeps the mechanical caveat (a
provider block inside a child module breaks `count`/`for_each` on the module
call and strands resources at destroy) because judgment must follow the
module's intended shape — the point is that "intended to stand alone" is the
better ambition, not that provider blocks are free.

## Version constraints, not lockfiles

A module's `required_providers` constraints must exclude the next major
version on their own. The lockfile argument ("hard pins plus `.terraform.lock.hcl`
is more reproducible") is true for a *root being operated* and irrelevant to a
*module being authored*: the lockfile is a runtime artifact of whichever root
executes the module, consumers regenerate or gitignore it, and a module that
is only safe under a particular lockfile is unsafe. Range constraints within a
major (`~>`) also let consumers converge provider versions across a root
without conflicts, which hard pins routinely break.

## Tagging as table stakes

Tags are the only universal metadata channel consumers have — cost
allocation, ownership, cleanup automation all hang off them — so a module that
gives consumers no way to attach any is defective, and an optional map input
is the portable mechanism (a child module cannot set provider `default_tags`).
At the same time, a module that *demands* tag inputs the prompt never asked
for taxes every consumer for someone else's tagging policy; that is scope
invention, not tagging. And run-varying tag values (timestamps) make every
plan dirty, which trains operators to ignore diffs — the worst possible
outcome of a metadata feature.

## Separate resources over inline blocks

Where a provider offers both, separate resources give each entry its own
address and lifecycle: adds and removes are surgical, whereas inline lists
diff as a whole and invite churn. We stop short of "always" — a specific
resource may have atomicity or ordering semantics that justify inline — but
the justification must be objective and written down, because the default is
load-bearing: mixing both styles on the same attributes is documented broken
behavior, and the mixed state is usually reached by deviating casually.

## Why the grading weights are tiered

Security and safety sections weigh 3, core design judgment 2, style 1. A flat
mean would price "file layout" equal to "insecure configurations", which no
reviewer believes. Weights are declared inside the doctrine itself — not in
harness config — so they are hashed into every judgment and versioned with
the opinions they express.
