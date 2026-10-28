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

{{CRITERIA_TABLES}}

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
