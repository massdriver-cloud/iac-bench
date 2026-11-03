"""Hermetic tests for the static analysis that needs no cloud: the solver's
witnesses (solve.py) and closed_values proofs (checks.py). The generation
selftest exercises both end to end, but only with cloud credentials."""

import json
from pathlib import Path

import pytest

from iacbench import checks, solve
from iacbench.paths import REPO_ROOT

SOLUTIONS = REPO_ROOT / "testdata" / "solutions"


def module(tmp_path: Path, source: str) -> Path:
    (tmp_path / "main.tf").write_text(source)
    return tmp_path


def closed(module_dir: Path, rtype: str, attrs: dict) -> bool:
    return checks.evaluate(
        checks.CheckContext(module_dir, None), {"closed_values": {"type": rtype, "attrs": attrs}}
    )


SECURE = {"in": ["ENCRYPTED_ONLY", "TRUSTED_CLIENT_CERTIFICATE_REQUIRED"]}


# ------------------------------------------------------------ closed_values

@pytest.mark.parametrize(
    "variables, value, expected",
    [
        ("", '"ENCRYPTED_ONLY"', True),
        ('variable "certs" { type = bool }',
         'var.certs ? "TRUSTED_CLIENT_CERTIFICATE_REQUIRED" : "ENCRYPTED_ONLY"', True),
        ('variable "certs" { type = bool }',
         'var.certs ? "TRUSTED_CLIENT_CERTIFICATE_REQUIRED" : "ALLOW_UNENCRYPTED_AND_ENCRYPTED"', False),
        ('variable "mode" {\n type = string\n validation {\n'
         '  condition = contains(["ENCRYPTED_ONLY", "TRUSTED_CLIENT_CERTIFICATE_REQUIRED"], var.mode)\n'
         '  error_message = "x"\n }\n}', "var.mode", True),
        ('variable "mode" {\n type = string\n validation {\n'
         '  condition = contains(["ALLOW_UNENCRYPTED_AND_ENCRYPTED", "ENCRYPTED_ONLY"], var.mode)\n'
         '  error_message = "x"\n }\n}', "var.mode", False),
        ('variable "mode" { type = string }', "var.mode", False),
        ('variable "mode" { type = string }', "lower(var.mode)", False),
        ('variable "size" { type = string }\nlocals {\n modes = {\n'
         '  small = "ENCRYPTED_ONLY"\n  large = "TRUSTED_CLIENT_CERTIFICATE_REQUIRED"\n }\n}',
         "local.modes[var.size]", True),
    ],
)
def test_closed_values_proves_every_reachable_value(tmp_path, variables, value, expected):
    d = module(tmp_path, f'{variables}\nresource "x_db" "this" {{\n  settings {{\n    ssl_mode = {value}\n  }}\n}}\n')
    assert closed(d, "x_db", {"settings.ssl_mode": SECURE}) is expected


def test_closed_values_needs_an_unconditional_instance(tmp_path):
    d = module(tmp_path, 'variable "on" { type = bool }\n'
                         'resource "x_db" "this" {\n  count = var.on ? 1 : 0\n  enabled = true\n}\n')
    assert not closed(d, "x_db", {"enabled": True})


def test_closed_values_fails_dynamic_and_missing(tmp_path):
    d = module(tmp_path, 'resource "x_db" "this" {\n  dynamic "settings" {\n    for_each = [1]\n'
                         '    content { ssl_mode = "ENCRYPTED_ONLY" }\n  }\n}\n')
    assert not closed(d, "x_db", {"settings.ssl_mode": SECURE})
    (tmp_path / "missing").mkdir()
    missing = module(tmp_path / "missing", 'resource "x_db" "this" {}\n')
    assert not closed(missing, "x_db", {"enabled": True})


# ------------------------------------------------------------ evaluator

def test_object_optional_defaults_apply(tmp_path):
    d = module(tmp_path, 'variable "cap" {\n  type = object({ min = optional(number, 2), on = optional(bool, false) })\n'
                         '  default = {}\n}\nlocals { n = var.cap.min * 2 }\n')
    ev = solve.Evaluator(solve.Module.load(d), {})
    assert ev.eval({"t": "ref", "steps": [{"attr": "local"}, {"attr": "n"}]}) == 4


# ------------------------------------------------------------ solver

ZONES = '''
variable "zone_redundant" {
  type    = bool
  default = false
}
variable "instances" {
  type    = number
  default = 1
  validation {
    condition     = var.instances >= 1 && var.instances <= %d
    error_message = "x"
  }
}
resource "x_plan" "this" {
  workers = var.instances
  zones   = var.zone_redundant
  lifecycle {
    precondition {
      condition     = !var.zone_redundant || var.instances >= 3
      error_message = "x"
    }
  }
}
'''

GOAL = solve.Goal("x_plan", json.dumps({"zones": True}))


def test_solver_finds_inputs_the_sweep_cannot_set_alone(tmp_path):
    m = solve.Module.load(module(tmp_path, ZONES % 30))
    witnesses = solve.solve(m, GOAL, solve.base_inputs(m, {}))
    assert witnesses[0].changed == {"instances": 3, "zone_redundant": True}


def test_solver_finds_nothing_when_guards_contradict(tmp_path):
    m = solve.Module.load(module(tmp_path, ZONES % 2))
    assert solve.solve(m, GOAL, solve.base_inputs(m, {})) == []


def test_solver_uses_fixture_samples_for_provider_values(tmp_path):
    d = module(tmp_path, 'variable "workspace_id" {\n  type = string\n  default = null\n}\n'
                         'resource "x_diag" "this" {\n  count = var.workspace_id == null ? 0 : 1\n'
                         '  workspace_id = var.workspace_id\n}\n')
    m = solve.Module.load(d)
    goal = solve.Goal("x_diag", "null")
    assert solve.solve(m, goal, solve.base_inputs(m, {})) == []
    sample = {"x_diag.workspace_id": "/subscriptions/0/workspaces/w"}
    witnesses = solve.solve(m, goal, solve.base_inputs(m, {}), sample)
    assert witnesses[0].changed == {"workspace_id": "/subscriptions/0/workspaces/w"}


def test_solver_on_known_answer_solutions():
    goal = solve.Goal("azurerm_service_plan", json.dumps({"zone_balancing_enabled": True}))
    good = solve.Module.load(SOLUTIONS / "G003" / "ref_guarded")
    assert solve.solve(good, goal, solve.base_inputs(good, {}))
    bad = solve.Module.load(SOLUTIONS / "G003" / "bad_guard_contradiction")
    assert solve.solve(bad, goal, solve.base_inputs(bad, {})) == []


def test_closed_values_compares_types_like_hcl(tmp_path):
    d = module(tmp_path, 'variable "n" {\n  type = number\n  validation {\n'
                         '    condition = contains([1], var.n)\n    error_message = "x"\n  }\n}\n'
                         'resource "x_db" "this" {\n  enabled = var.n\n}\n')
    assert not closed(d, "x_db", {"enabled": True})
