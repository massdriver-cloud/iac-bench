"""Static checks see resources declared in the local modules a module calls."""
from pathlib import Path

from iacbench import checks, hclast, hclq, solve

ROOT = """
variable "encrypted" {
  type    = bool
  default = true
}

variable "name" {
  type = string
}

locals {
  key = "root"
}

resource "aws_kms_key" "this" {}

module "east" {
  source    = "./modules/region"
  name      = "${var.name}-east"
  encrypted = true
  key_arn   = aws_kms_key.this.arn
}

module "west" {
  source    = "./modules/region"
  name      = "${var.name}-west"
  encrypted = var.encrypted
}

output "id" {
  value = module.east.id
}
"""

CHILD = """
variable "name" {
  type = string
}

variable "encrypted" {
  type = bool
}

variable "key_arn" {
  type    = string
  default = null
}

locals {
  key = var.key_arn
}

resource "aws_kms_key" "this" {}

resource "aws_rds_cluster" "this" {
  cluster_identifier = var.name
  storage_encrypted  = var.encrypted
  kms_key_id         = coalesce(local.key, aws_kms_key.this.arn)
}

output "id" {
  value = aws_rds_cluster.this.id
}
"""

EXAMPLE = """
resource "aws_rds_cluster" "example" {
  storage_encrypted = false
}
"""


def _module(tmp_path: Path) -> Path:
    (tmp_path / "main.tf").write_text(ROOT)
    (tmp_path / "modules/region").mkdir(parents=True)
    (tmp_path / "modules/region/main.tf").write_text(CHILD)
    (tmp_path / "examples").mkdir()
    (tmp_path / "examples/main.tf").write_text(EXAMPLE)  # never called
    return tmp_path


def test_called_child_resources_are_visible(tmp_path):
    d = _module(tmp_path)
    clusters = hclq.resource_attrs(d, "aws_rds_cluster")
    # One per call, named by the call's argument; the uncalled example stays out.
    assert sorted(c["cluster_identifier"] for c in clusters) == ["${var.name}-east", "${var.name}-west"]


def test_child_inputs_resolve_to_the_call_arguments(tmp_path):
    d = _module(tmp_path)
    by_name = {c["kms_key_id"]: c for c in hclq.resource_attrs(d, "aws_rds_cluster")}
    texts = " ".join(by_name)
    assert "aws_kms_key.__east__this.arn" in texts and "aws_kms_key.__west__this.arn" in texts
    assert "local.__east__key" in texts  # child locals renamed, not the root's local.key
    module = solve.Module.load(d)
    assert "key" in module.locals and "__east__key" in module.locals


def test_closed_values_follow_the_call(tmp_path):
    d = _module(tmp_path)
    ctx = checks.CheckContext(module_dir=d, defaults_plan=None)
    spec = {"type": "aws_rds_cluster", "attrs": {"storage_encrypted": True}}
    # west passes var.encrypted: an input can turn encryption off.
    assert checks._verb_closed_values(ctx, spec) is False
    (d / "main.tf").write_text(ROOT.replace("encrypted = var.encrypted", "encrypted = true"))
    assert checks._verb_closed_values(checks.CheckContext(module_dir=d, defaults_plan=None), spec) is True


def test_root_interface_unchanged(tmp_path):
    d = _module(tmp_path)
    assert set(hclq.variables(d)) == {"encrypted", "name"}
    assert set(hclq.outputs(d)) == {"id"}
    assert hclq.unparsed_files(d) == []
    assert sorted(hclast.files(d)) == ["east/main.tf", "main.tf", "west/main.tf"]
