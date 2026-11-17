"""Hermetic tests for the plan lens: numeric, list and regex predicates,
instance and region counts, and region resolution (checks.region_of)."""

from iacbench import checks


def plan(resources, provider_config=None, config_resources=None, variables=None):
    return {
        "planned_values": {"root_module": {"resources": resources}},
        "configuration": {
            "provider_config": provider_config or {},
            "root_module": {"resources": config_resources or []},
        },
        "variables": variables or {},
    }


def res(address, values):
    rtype = address.split(".")[0]
    return {"address": address, "type": rtype, "mode": "managed", "values": values}


def check(p, spec, tmp_path):
    return checks.evaluate(checks.CheckContext(tmp_path, p), {"resource": spec})


def test_gte_and_lte_compare_numbers_and_numeric_strings(tmp_path):
    p = plan([res("aws_rds_cluster.a", {"backup_retention_period": 14, "port": "5432"})])
    assert check(p, {"type": "aws_rds_cluster", "where": {"backup_retention_period": {"gte": 7}}}, tmp_path)
    assert not check(p, {"type": "aws_rds_cluster", "where": {"backup_retention_period": {"gte": 15}}}, tmp_path)
    assert check(p, {"type": "aws_rds_cluster", "where": {"port": {"gte": 1024, "lte": 65535}}}, tmp_path)


def test_gte_rejects_non_numbers(tmp_path):
    p = plan([res("aws_rds_cluster.a", {"backup_retention_period": True})])
    assert not check(p, {"type": "aws_rds_cluster", "where": {"backup_retention_period": {"gte": 0}}}, tmp_path)


def test_contains_and_matches(tmp_path):
    p = plan([res("aws_rds_cluster.a", {
        "enabled_cloudwatch_logs_exports": ["postgresql"],
        "parameter": [{"name": "shared_preload_libraries", "value": "pg_stat_statements,pgaudit"}],
    })])
    assert check(p, {"type": "aws_rds_cluster", "where": {"enabled_cloudwatch_logs_exports": {"contains": "postgresql"}}}, tmp_path)
    assert not check(p, {"type": "aws_rds_cluster", "where": {"enabled_cloudwatch_logs_exports": {"contains": "upgrade"}}}, tmp_path)
    assert check(p, {"type": "aws_rds_cluster", "where": {
        "parameter": {"name": "shared_preload_libraries", "value": {"matches": r"\bpgaudit\b"}}}}, tmp_path)


def test_min_instances_counts_matching_instances(tmp_path):
    p = plan([
        res("aws_rds_cluster_instance.a[0]", {"publicly_accessible": False}),
        res("aws_rds_cluster_instance.a[1]", {"publicly_accessible": False}),
        res("aws_rds_cluster_instance.a[2]", {"publicly_accessible": True}),
    ])
    spec = {"type": "aws_rds_cluster_instance", "where": {"publicly_accessible": False}}
    assert check(p, {**spec, "min_instances": 2}, tmp_path)
    assert not check(p, {**spec, "min_instances": 3}, tmp_path)
    assert not check(p, {**spec, "match": "every"}, tmp_path)


def test_min_regions_reads_the_planned_region(tmp_path):
    two = plan([res("aws_rds_cluster.p", {"region": "us-east-1"}), res("aws_rds_cluster.s", {"region": "us-west-2"})])
    one = plan([res("aws_rds_cluster.p", {"region": "us-east-1"}), res("aws_rds_cluster.s", {"region": "us-east-1"})])
    assert check(two, {"type": "aws_rds_cluster", "min_regions": 2}, tmp_path)
    assert not check(one, {"type": "aws_rds_cluster", "min_regions": 2}, tmp_path)


def test_region_resolves_through_the_provider_configuration(tmp_path, monkeypatch):
    monkeypatch.setenv("AWS_REGION", "us-east-1")
    p = plan(
        [res("aws_rds_cluster.p", {}), res("aws_rds_cluster.s", {}), res("aws_rds_cluster.t", {})],
        provider_config={
            "aws": {"name": "aws"},
            "aws.secondary": {"name": "aws", "expressions": {"region": {"references": ["var.secondary_region"]}}},
            "aws.third": {"name": "aws", "expressions": {"region": {"constant_value": "us-east-2"}}},
        },
        config_resources=[
            {"address": "aws_rds_cluster.p", "provider_config_key": "aws"},
            {"address": "aws_rds_cluster.s", "provider_config_key": "aws.secondary"},
            {"address": "aws_rds_cluster.t", "provider_config_key": "aws.third"},
        ],
        variables={"secondary_region": {"value": "us-west-2"}},
    )
    found = [checks.region_of(p, r) for r in checks.planned(p)]
    assert found == ["us-east-1", "us-west-2", "us-east-2"]
    assert check(p, {"type": "aws_rds_cluster", "min_regions": 3}, tmp_path)


def test_an_unresolvable_region_does_not_count(tmp_path):
    p = plan(
        [res("aws_rds_cluster.p", {"region": "us-east-1"}), res("aws_rds_cluster.s", {})],
        provider_config={"aws.secondary": {"name": "aws", "expressions": {"region": {"references": ["local.r"]}}}},
        config_resources=[{"address": "aws_rds_cluster.s", "provider_config_key": "aws.secondary"}],
    )
    assert not check(p, {"type": "aws_rds_cluster", "min_regions": 2}, tmp_path)


def test_region_follows_an_object_variable_attribute(tmp_path):
    p = plan(
        [res("aws_rds_cluster.s", {})],
        provider_config={"aws.secondary": {"name": "aws", "expressions": {
            "region": {"references": ["var.regions.secondary", "var.regions"]}}}},
        config_resources=[{"address": "aws_rds_cluster.s", "provider_config_key": "aws.secondary"}],
        variables={"regions": {"value": {"primary": "us-east-1", "secondary": "us-west-2"}}},
    )
    assert [checks.region_of(p, r) for r in checks.planned(p)] == ["us-west-2"]


def test_g004_apply_failure_needs_secrets_manager_on_a_global_member(tmp_path):
    from pathlib import Path

    from iacbench.generation import GenerationFixture

    fixture = GenerationFixture.load(Path(__file__).parent.parent / "fixtures/generation/G004")
    (entry,) = [f for f in fixture.apply_failures if f["id"] == "F1_secrets_manager_on_global_member"]

    def hits(resources):
        return checks.evaluate(checks.CheckContext(tmp_path, plan(resources)), entry["check"])

    glob = res("aws_rds_global_cluster.g", {})
    sm = res("aws_rds_cluster.p", {"manage_master_user_password": True})
    pw = res("aws_rds_cluster.p", {"manage_master_user_password": None})
    assert hits([glob, sm])
    assert not hits([sm])  # a single-region cluster may use Secrets Manager
    assert not hits([glob, pw])
