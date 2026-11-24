# Aurora PostgreSQL (global, production)

Reusable OpenTofu module for the platform team's production PostgreSQL
databases. It stands up an **Aurora global database** across two US regions
and owns every design decision except the handful of inputs that are specific
to each service.

## What it builds

```
                 Aurora global database (storage-level replication, typical lag < 1s)
        ┌───────────────────────────────────┴────────────────────────────────────┐
  primary region (writer)                                            secondary region (standby)
  ┌───────────────────────────────┐                                  ┌───────────────────────────────┐
  │ cluster "<name>-primary"      │ ─────── continuous replication ─▶│ cluster "<name>-secondary"    │
  │  writer + N-1 readers (multi- │                                  │  M warm readers, promotable   │
  │  AZ via tier=database subnets)│                                  │  to writer in ~1 minute       │
  │  CMK encryption (region key)  │                                  │  CMK encryption (region key)  │
  └───────────────────────────────┘                                  └───────────────────────────────┘
```

Per region, the module also creates: a DB subnet group and security group in
the environment VPC (both discovered by tag), a customer-managed KMS key, a
cluster parameter group (SSL enforced), and wires up IAM database
authentication, Performance Insights, Enhanced Monitoring, CloudWatch log
export, 35-day backups and deletion protection. The master password is
generated and managed by RDS in Secrets Manager — it never appears in
configuration or state.

## How it meets the availability bar

* **Data loss of at most a few seconds on regional failure** — Aurora global
  databases replicate at the storage layer with a typical cross-region lag
  well under one second; a managed switchover finishes any in-flight
  replication before promoting, so a planned switchover loses nothing.
* **Serving again within minutes** — the secondary cluster already runs warm
  instances (`secondary_instance_count >= 1`), so there is no provisioning
  wait. A managed switchover typically completes in about a minute; the
  ready-made command is in the `switchover_command` output.
* **Regional failure includes the writer** — if the primary region is
  degraded but reachable, use the switchover command. If it is truly gone,
  use a failover with data loss as the last resort:
  `aws rds failover-global-cluster --global-cluster-identifier <name> --target-db-cluster-identifier <secondary-cluster-arn> --allow-data-loss`
  (expected loss is still only the replication lag, usually < 1s).

After either operation, swap `primary_region`/`secondary_region` in the
caller's configuration (or rebuild in the old region) to restore the desired
topology.

## Usage

The module drives two regions, so the caller passes two aliased providers:

```hcl
provider "aws" {
  region = "us-east-1"
}

provider "aws" {
  alias  = "secondary"
  region = "us-west-2"
}

module "checkout_db" {
  source = "…/aurora-postgresql-global"

  providers = {
    aws           = aws
    aws.secondary = aws.secondary
  }

  name             = "checkout"
  primary_region   = "us-east-1"
  secondary_region = "us-west-2"
  # everything else has a production default; see variables.tf
}
```

A staging database in the same regions is one input away:
`vpc_tags = { Name = "apps-staging" }`.

## Contract with the network team

The module discovers, in each region independently:

* the VPC matching `vpc_tags` (default `{ Name = "apps-prod" }`), and
* the subnets inside it matching `subnet_tags` (default `{ tier = "database" }`).

The `discovered_network` output shows what was found in each region; empty
values mean the network is not there (or is tagged differently) and the apply
must wait for the network team.

## Contract with the service teams (EKS)

* **Network**: the cluster security group accepts the database port from the
  environment VPC CIDR by default, so EKS workloads in the VPC can reach it.
  Tighten with `allowed_cidr_blocks` / `allowed_security_group_ids`.
* **Authentication**: IAM database authentication is on. Create the service's
  database user once as a DBA — `CREATE USER "checkout_app"; GRANT rds_iam TO
  "checkout_app";` — then give the service's IAM role
  `rds-db:connect` on
  `arn:aws:rds-db:<region>:<account>:dbuser:<iam_auth_cluster_resource_id>/checkout_app`.
  Connections must use TLS (the parameter group enforces it) and an IAM auth
  token.

## Design decisions owned by this module

| Decision | Choice | Why |
| --- | --- | --- |
| Topology | Aurora global database, warm secondary | RPO of seconds / RTO of minutes on regional failure |
| Auth | IAM database authentication only | Services already have IAM roles; no static passwords in apps |
| Master password | RDS-managed in Secrets Manager | Never in code or state; automatic rotation |
| Encryption at rest | Customer-managed KMS key per region, rotation on | Payment/customer data; keys are region-scoped so one per region |
| Encryption in transit | `rds.force_ssl = 1` | Non-negotiable for payment data |
| Network | Private subnets only, `publicly_accessible = false`, SG limited to DB port | Never expose the database |
| Backups | 35 days, tags copied to snapshots, final snapshot on destroy | Maximum retention for regulated data |
| Observability | PostgreSQL logs to CloudWatch, Performance Insights (CMK-encrypted), Enhanced Monitoring | Non-specialists need AWS-native tooling |
| Safety | Deletion protection on, maintenance/backup windows fixed, minor upgrades automatic | Production posture by default |

## Notes

* Engine version and instance class apply to both regions identically —
  Aurora requires members of a global cluster to run the same engine version.
* The secondary cluster takes no final snapshot; backups belong to the
  primary. After a switchover, the promoted cluster keeps its own backup
  schedule (retention is configured on both).
* Aurora bills the secondary region's instances and replicated storage from
  day one; that is the cost of the availability bar.
