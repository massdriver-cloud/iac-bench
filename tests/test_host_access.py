"""Hermetic tests for baseline item B4_no_host_access and the environment
tofu runs with."""

from pathlib import Path

import yaml

from iacbench import checks
from iacbench.generation import GenerationFixture
from iacbench.paths import REPO_ROOT
from iacbench.tofu import tofu_environment

BASELINE = yaml.safe_load((REPO_ROOT / "fixtures" / "generation" / "baseline.yaml").read_text())
B4 = next(i for i in BASELINE["items"] if i["id"] == "B4_no_host_access")


def passes(tmp_path: Path, source: str) -> bool:
    tmp_path.mkdir(parents=True, exist_ok=True)
    (tmp_path / "main.tf").write_text(source)
    return checks.evaluate(checks.CheckContext(tmp_path, None), B4["check"])


def test_plain_module_passes(tmp_path):
    assert passes(tmp_path, 'variable "name" {\n  type = string\n}\n')


def test_reading_proc_fails(tmp_path):
    assert not passes(tmp_path, 'locals {\n  env = file("/proc/self/environ")\n}\n')


def test_external_data_source_fails(tmp_path):
    assert not passes(tmp_path, 'data "external" "env" {\n  program = ["sh", "-c", "env"]\n}\n')


def test_local_exec_fails(tmp_path):
    src = 'resource "terraform_data" "x" {\n  provisioner "local-exec" {\n    command = "true"\n  }\n}\n'
    assert not passes(tmp_path, src)


def test_comment_mentioning_proc_passes(tmp_path):
    assert passes(tmp_path, '# never read /proc/ from a module\nvariable "name" {\n  type = string\n}\n')


def test_b4_is_mandatory_in_every_fixture():
    for rubric in sorted((REPO_ROOT / "fixtures" / "generation").glob("G*/rubric.yaml")):
        fx = GenerationFixture.load(rubric.parent)
        assert "B4_no_host_access" in fx.mandatory, fx.id


def test_tofu_environment_keeps_provider_configuration_only():
    source = {
        "PATH": "/usr/bin", "HOME": "/home/u", "TF_PLUGIN_CACHE_DIR": "/c",
        "AWS_ACCESS_KEY_ID": "a", "AWS_REGION": "us-east-1", "GOOGLE_OAUTH_ACCESS_TOKEN": "g",
        "GOOGLE_PROJECT": "p", "ARM_CLIENT_ID": "c", "ARM_SUBSCRIPTION_ID": "s",
        "ANTHROPIC_API_KEY": "x", "OPENAI_API_KEY": "x", "OPENROUTER_API_KEY": "x",
        "GEMINI_API_KEY": "x", "GOOGLE_API_KEY": "x", "AZURE_RESOURCE_GROUP": "rg", "MODELS": "m",
    }
    env = tofu_environment(source)
    assert set(env) == {
        "PATH", "HOME", "TF_PLUGIN_CACHE_DIR", "AWS_ACCESS_KEY_ID", "AWS_REGION",
        "GOOGLE_OAUTH_ACCESS_TOKEN", "GOOGLE_PROJECT", "ARM_CLIENT_ID", "ARM_SUBSCRIPTION_ID",
    }
