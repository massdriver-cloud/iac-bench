"""The composite: a known apply failure multiplies the whole composite,
judge share included."""

from iacbench.report import Attempt, _composite

W = {"mechanical": 0.7, "grade": 0.3}


def attempt(**kw):
    return Attempt(model="m", fixture="G", passed=True, terminal_state="complete", **kw)


def test_working_module_composite():
    assert abs(_composite(attempt(mechanical_score=0.9), 80, W) - 87.0) < 1e-9


def test_apply_failure_halves_the_whole_composite():
    a = attempt(mechanical_score=0.45, raw_mechanical_score=0.9, apply_failures=["F1"])
    assert abs(_composite(a, 80, W) - 43.5) < 1e-9
