# Aurora PostgreSQL — platform standard production database module

Reusable OpenTofu module that stands up the production PostgreSQL databases
behind our customer-facing services, on **Amazon Aurora PostgreSQL**, the way
the platform team agreed to run them.

**The business bar:** if an AWS region fails, a service's database must be
serving again from another region within minutes, having lost no more than a
few seconds of writes.

**How this module meets it:** every database is an **Aurora Global Database** —
a primary cluster in one region plus an always-on warm-standby cluster in the
second region, continuously replicated at the storage layer.

| Requirement | Aurora Global Database capability | Typical |
| --- | --- | --- |
| Serving again within minutes | Managed failover (planned or unplanned) | well under 1 minute |
| No more than a few seconds of lost writes | Asynchronous storage replication | under 1 second of lag |

The standby is not a cold copy. It serves **local reads in the second region**
at millisecond latency, and failover is a metadata operation — no snapshot
restore, no instance rebuild, no re-seeding of data.

## What the module creates

- `aws_rds_global_cluster` — ties the two regional clusters together.
- `aws_rds_cluster` + `aws_rds_cluster_instance` — a primary cluster (writer +
  readers) in `primary_region`, and a warm-standby cluster in
  `secondary_region` that serves local reads and takes over on failover.
- `aws_db_subnet_group` per region — built from the network team's **private
  database subnets**, auto-discovered by the `tier = database` tag inside the
  environment VPC (`apps-staging` / `apps-prod`, looked up by name tag).
- `aws_security_group` per region — ingress on port 5432 only, from the CIDR
  blocks / security groups you allow (defaults to the VPC's own CIDR). No
  public access.
- `aws_rds_cluster_parameter_group` per region — forces TLS (`rds.force_ssl = 1`).
- Master credentials — a generated 32-character password stored in **Secrets
  Manager in both regions** (same content, so either region can operate the
  database after a failover).
- IAM role for RDS enhanced monitoring (created only if `monitoring_interval > 0`).
- Optional IAM policy granting `rds-db:connect` for your service's database
  users, to attach to your EKS IRSA roles (set `iam_db_users`).

Platform engineers only have to answer: **which service** (`service_name`)
and **which environment** (`environment`). Everything else has a
production-grade default that can still be overridden per database.

## Prerequisites

- The network team's VPC named `apps-<environment>` in both regions, with
  private subnets tagged `tier = database` spanning at least two Availability
  Zones. (Both are discovered by tag; overrides exist if you ever need them:
  `vpc_name`, `subnet_tags`, `primary_subnet_ids`, `secondary_subnet_ids`.)
- AWS credentials that may create RDS, EC2 (VPC lookups), IAM and Secrets
  Manager resources in both regions.
- A state backend configured by the platform team (this module is applied as
  a root module).

## Quick start

```hcl
# minimal.tfvars
service_name = "checkout"
environment  = "prod"
```

```sh
tofu init
tofu apply -var-file=minimal.tfvars
```

That gives you: an Aurora PostgreSQL 17 global database `checkout-prod-global`,
writer/reader endpoints in `us-east-1`, a warm standby with read endpoints in
`us-west-2`, encryption at rest, forced TLS, IAM authentication, backups,
enhanced monitoring and Performance Insights.

### Staging vs prod defaults

| | staging | prod |
| --- | --- | --- |
| `instance_class` | db.t4g.medium | db.r6g.large |
| `primary_instance_count` | 1 | 2 (writer + reader) |
| `secondary_instance_count` | 1 | 1 |
| `backup_retention_period` | 1 day | 14 days |
| `deletion_protection` | false | true |
| final snapshot on destroy | skipped | kept (`<name>-final`) |
| secret recovery window | 0 (immediate) | 7 days |

All of these (plus `engine_version`, ports, windows, tags, parameters,
KMS key, storage type, extra instances) can be overridden per database.

## How services connect (IAM database authentication)

Services on EKS reach AWS through IAM roles, so they authenticate to the
database with IAM tokens — no database passwords in workloads.

1. Tell the module which DB users the service will use:

   ```hcl
   iam_db_users = ["checkout_app"]
   ```

2. Attach the resulting policy (output `rds_db_connect_policy_arn`) to the
   service's EKS service account IAM role. The policy already covers **both**
   regional clusters, so it keeps working after a regional failover.
3. One-time bootstrap, as master (password from the Secrets Manager secret in
   your region), e.g.:

   ```sql
   CREATE USER checkout_app;
   GRANT rds_iam TO checkout_app;
   GRANT CONNECT ON DATABASE checkout TO checkout_app;
   -- plus schema/table grants as appropriate
   ```

4. Connect with `sslmode=require` (the cluster forces TLS anyway) using an
   RDS authentication token generated for the endpoint you are dialling:
   writers → `primary_cluster.writer_endpoint`; local reads in the other
   region → `secondary_cluster.reader_endpoint`.

## Failover runbook (the minutes/RPO story)

The standby cluster is always running and kept in sync; failover is a
promotion, not a rebuild. Monitor replication lag in CloudWatch (the Aurora
global database lag metric) — it is typically under a second, which is what
bounds write loss (RPO) at failover time.

**Planned switch (e.g. region maintenance, or switchback after a recovered
outage) — typically < 1 minute, no data loss:**

```sh
aws rds failover-global-cluster \
  --global-cluster-identifier <global_cluster_identifier output> \
  --target-db-cluster-identifier <secondary_cluster.cluster_arn output>
```

**Unplanned failover (primary region is down) — typically < 1 minute, loses
at most the not-yet-replicated seconds:**

```sh
aws rds failover-global-cluster \
  --global-cluster-identifier <global_cluster_identifier output> \
  --target-db-cluster-identifier <secondary_cluster.cluster_arn output> \
  --allow-data-loss
```

After failover, point the service's writes at `secondary_cluster.cluster_endpoint`
(the standby's cluster endpoint becomes the writer endpoint). Services using
IAM tokens simply generate tokens for the new endpoint.

**Terraform after a failover:** both physical clusters still exist and are
tracked by address, so `tofu plan` stays clean. Do **not** swap
`primary_region`/`secondary_region` in your tfvars — provider region changes
force resource replacement. The variable names describe the *regions*; after a
failover the writer happens to live in the other one until you switch back
with the planned (lossless) failover command above.

If managed failover is unavailable (e.g. very old CLI), the manual equivalent
is `aws rds remove-from-global-cluster --db-cluster-identifier <secondary arn>
--global-cluster-identifier <global id>`, which detaches and promotes the
standby — but that breaks the global topology and requires rebuilding it, so
prefer managed failover.

## Design decisions worth knowing

- **Engine version:** resolved from the AWS default for the region (via
  `aws_rds_engine_version`) so every cluster in the global database agrees and
  the version is always one that accepts new clusters. Pin `engine_version` to
  control upgrades deliberately; `auto_minor_version_upgrade` is off on the
  instances because global-database upgrades are coordinated, two-region
  operations.
- **Security posture (customer/payment data):** storage is always encrypted
  (AWS managed key by default, or set `storage_kms_key_id`), TLS is forced by
  the cluster parameter group, instances are private (`publicly_accessible =
  false`), IAM database authentication is on, and the writer credentials are
  generated — never typed in, never printed in outputs.
- **Backups are regional** (automated backups + snapshots stay in their own
  region); the cross-region resilience of these databases comes from the
  global database itself, not from snapshot copies.
- **Master credentials in both regions:** the module writes the same secret
  to both regions rather than relying on the RDS-managed master password
  (which is single-region) — a region outage must not lock you out of the
  promoted cluster. Rotate with `tofu apply -replace=random_password.master`,
  which rolls the password, both secrets, and the cluster in one coordinated
  change.
- **Aurora PostgreSQL allows exactly one writer at a time**; services in the
  standby region read locally and write cross-region until a failover.

## Inputs

Only `service_name` and `environment` are required.

| Name | Default | Notes |
| --- | --- | --- |
| `service_name` | — | required; e.g. `checkout` |
| `environment` | — | required; `staging` or `prod` (selects the VPC) |
| `primary_region` | `us-east-1` | writer cluster region |
| `secondary_region` | `us-west-2` | warm standby region |
| `vpc_name` | `apps-<environment>` | Name tag of the network team's VPC |
| `subnet_tags` | `{ tier = "database" }` | tags identifying the private DB subnets |
| `primary_subnet_ids` / `secondary_subnet_ids` | discovered | explicit subnet overrides |
| `allowed_cidr_blocks` | VPC CIDR | PostgreSQL ingress sources (both regions) |
| `primary_allowed_security_group_ids` / `secondary_allowed_security_group_ids` | `[]` | EKS SGs allowed in, per region |
| `engine_version` | region default | pin to control upgrades |
| `database_name` | service name | initial database |
| `master_username` | `postgres` | master user (services use IAM auth) |
| `port` | `5432` | |
| `instance_class` | r6g.large (prod) / t4g.medium (staging) | all instances |
| `primary_instance_count` | 2 (prod) / 1 (staging) | writer + readers |
| `secondary_instance_count` | `1` | warm standby instances |
| `storage_type` | `aurora` | or `aurora-iopt1` |
| `storage_kms_key_id` | AWS managed key | CMK for the primary region |
| `iam_database_authentication_enabled` | `true` | IAM token logins |
| `iam_db_users` | `[]` | DB users to publish an `rds-db:connect` policy for |
| `cluster_parameters` | `{}` | extra cluster params (TLS is always forced) |
| `backup_retention_period` | 14 (prod) / 1 (staging) | days |
| `preferred_backup_window` | `03:00-04:00` | UTC |
| `preferred_maintenance_window` | `sun:04:00-sun:05:00` | UTC |
| `deletion_protection` | true (prod) | guards against accidental deletion |
| `skip_final_snapshot` | true (staging) / false (prod) | final snapshot on destroy |
| `apply_immediately` | `false` | |
| `auto_minor_version_upgrade` | `false` | upgrades stay deliberate |
| `enabled_cloudwatch_logs_exports` | `["postgresql", "upgrade"]` | |
| `performance_insights_enabled` | `true` | per instance |
| `performance_insights_retention_period` | `7` | days |
| `monitoring_interval` | `60` | enhanced monitoring; `0` disables |
| `tags` | `{}` | extra tags on everything |

## Outputs

| Name | Notes |
| --- | --- |
| `global_cluster_identifier` / `global_cluster_arn` | the global database |
| `engine_version` | resolved version in use |
| `database_name`, `port`, `master_username` | connection basics |
| `primary_cluster` | region, identifiers, ARN, `writer_endpoint`, `reader_endpoint` |
| `secondary_cluster` | region, identifiers, ARN, `cluster_endpoint` (writes after failover), `reader_endpoint` |
| `master_secret_arns` | Secrets Manager ARNs for master credentials, per region |
| `rds_db_connect_policy_arn` | IAM policy to attach to EKS roles (null unless `iam_db_users` set) |
| `security_group_ids` | ingress-controlling SG, per region |
