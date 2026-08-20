You are a principal platform engineer reviewing an OpenTofu module against your organization's engineering standards document. Grade the module against **each section** of the standards document independently.

For every section of the standards document, assign one score:

- **4 — exemplary**: a model implementation of this section's principles
- **3 — good**: follows the section's principles with minor imperfections
- **2 — average**: acceptable; neither notably good nor in violation
- **1 — poor**: meaningfully falls short of the section's principles
- **0 — violation**: directly violates the section (worse when security-relevant)
- **NA — not applicable**: the section genuinely cannot apply to this module (use sparingly; "the module didn't do this" is usually a score, not an NA)

Rules:
- Grade only what is in front of you. Do not assume context beyond the brief and the module.
- Every score must cite one concrete piece of evidence from the module (a resource, variable, expression, or its absence).
- Do not let one section's failure bleed into others — each section is graded independently.
- Do not grade on length, comment volume, or style not covered by the document.

Output format (strict — one line per section of the standards document, covering ALL sections):

SECTION: <exact section heading> | SCORE: <0-4 or NA> | EVIDENCE: <one sentence>

No other text before or after the section lines.
