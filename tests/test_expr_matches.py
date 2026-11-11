"""Hermetic tests for expr_matches: attribute expressions resolved through
locals, data sources and variable defaults (hclq.value_text_closure)."""

from pathlib import Path

from iacbench import checks, hclq

ABANDON = {"expr_matches": {"type": "google_sql_database", "attr": "deletion_policy", "pattern": "ABANDON"}}


def module(tmp_path: Path, source: str) -> Path:
    tmp_path.mkdir(parents=True, exist_ok=True)
    (tmp_path / "main.tf").write_text(source)
    return tmp_path


def matches(module_dir: Path, spec: dict = ABANDON) -> bool:
    return checks.evaluate(checks.CheckContext(module_dir, None), spec)


def database(deletion_policy: str, for_each: str = "") -> str:
    return (
        'resource "google_sql_database" "this" {\n'
        + (f"  for_each        = {for_each}\n" if for_each else "")
        + '  name            = "app"\n'
        + '  instance        = "main"\n'
        + f"  deletion_policy = {deletion_policy}\n"
        + "}\n"
    )


def test_optional_defaults_reads_the_default_of_the_named_attribute():
    type_text = """map(object({
      charset         = optional(string, "UTF8")
      deletion_policy = optional(string, "ABANDON")
      tags            = optional(list(string), ["a", "b,c"])
      collation       = optional(string)
    }))"""
    assert hclq.optional_defaults(type_text, "deletion_policy") == ['"ABANDON"']
    assert hclq.optional_defaults(type_text, "tags") == ['["a", "b,c"]']
    assert hclq.optional_defaults(type_text, "collation") == []
    assert hclq.optional_defaults(type_text, "missing") == []


def test_each_value_attribute_reaches_an_optional_default(tmp_path):
    d = module(tmp_path, """
variable "databases" {
  type = map(object({
    charset         = optional(string, "UTF8")
    deletion_policy = optional(string, "ABANDON")
  }))
  default = {}
}
""" + database("each.value.deletion_policy", "var.databases"))
    assert matches(d)


def test_each_value_attribute_reaches_an_optional_default_through_a_local(tmp_path):
    d = module(tmp_path, """
variable "databases" {
  type    = map(object({ deletion_policy = optional(string, "ABANDON") }))
  default = {}
}
locals {
  dbs = var.databases
}
""" + database("each.value.deletion_policy", "local.dbs"))
    assert matches(d)


def test_an_optional_default_of_another_attribute_does_not_match(tmp_path):
    d = module(tmp_path, """
variable "databases" {
  type = map(object({
    deletion_policy = optional(string, "DELETE")
    note            = optional(string, "ABANDON")
  }))
  default = {}
}
""" + database("each.value.deletion_policy", "var.databases"))
    assert not matches(d)


def test_a_plain_variable_reaches_its_default(tmp_path):
    keep = module(tmp_path / "keep", 'variable "p" {\n  default = "ABANDON"\n}\n' + database("var.p"))
    drop = module(tmp_path / "drop", 'variable "p" {\n  default = "DELETE"\n}\n' + database("var.p"))
    assert matches(keep)
    assert not matches(drop)


def test_an_object_variable_attribute_reaches_its_default(tmp_path):
    d = module(tmp_path, """
variable "settings" {
  type    = object({ deletion_policy = optional(string, "ABANDON") })
  default = {}
}
""" + database("var.settings.deletion_policy"))
    assert matches(d)


def test_a_required_variable_matches_nothing(tmp_path):
    d = module(tmp_path, 'variable "p" {\n  type = string\n}\n' + database("var.p"))
    assert not matches(d)
