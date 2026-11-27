"""A generation run refuses to start without its cloud's credentials."""
from iacbench.task import missing_cloud_env


def test_gcp_needs_project_and_a_credential():
    assert missing_cloud_env("gcp", {}) == [
        "GOOGLE_PROJECT", "GOOGLE_OAUTH_ACCESS_TOKEN|GOOGLE_CREDENTIALS|GOOGLE_APPLICATION_CREDENTIALS"]
    assert missing_cloud_env("gcp", {"GOOGLE_PROJECT": "p"}) == [
        "GOOGLE_OAUTH_ACCESS_TOKEN|GOOGLE_CREDENTIALS|GOOGLE_APPLICATION_CREDENTIALS"]
    assert missing_cloud_env("gcp", {"GOOGLE_PROJECT": "p", "GOOGLE_OAUTH_ACCESS_TOKEN": "t"}) == []


def test_empty_values_count_as_missing():
    assert missing_cloud_env("aws", {"AWS_ACCESS_KEY_ID": ""}) == ["AWS_ACCESS_KEY_ID|AWS_PROFILE"]
    assert missing_cloud_env("aws", {"AWS_PROFILE": "sandbox"}) == []


def test_azure():
    assert missing_cloud_env("azure", {"ARM_SUBSCRIPTION_ID": "s", "ARM_CLIENT_SECRET": "x"}) == []
    assert missing_cloud_env("azure", {"ARM_CLIENT_SECRET": "x"}) == ["ARM_SUBSCRIPTION_ID"]
