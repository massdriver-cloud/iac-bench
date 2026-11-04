"""iacbench: benchmark scoring LLM-written OpenTofu modules against real plans and a calibrated judge."""

__version__ = "0.1.0"

SUITE_VERSION = "v0.1.0"
# Pinned at "1" until the benchmark is published; pre-launch contract changes
# invalidate old runs instead of bumping (docs/generation-check-engine.md).
SCAFFOLD_CONTRACT_VERSION = "1"
CHECK_DSL_VERSION = "1"
