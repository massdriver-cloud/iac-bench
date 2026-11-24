# Aurora PostgreSQL global database — platform module

Standard module for the production PostgreSQL databases behind our
customer-facing services. One instantiation per service: it provisions an
**Aurora PostgreSQL global database** with a writable cluster in the primary
region and a continuously-replicated standby cluster in a second region, plus
everything around it (KMS, IAM auth, audit logging, monitoring, backups,
networking) with safe defaults. Platform engineers fill in what is specific to
each service and trust the module for the rest.

## How it meets the bar

The business requirement — a regional outage may cost at most a few seconds of
writes and the database must serve from another region within minutes — is met
by Aurora Global Database, provisioned by this module:

| Concern | Design decision |
|---|---|
| Region fails | `aws_rds_global_cluster` with a standby cluster in the second region. Replication lag is typically well under a second (**RPO ≈ seconds**); detaching the failed primary promotes the standby to writer in about a minute (**RTO ≈ minutes**). See the failover runbook. |
| AZ fails | Prod defaults run 2 instances per region across the discovered database subnets. |
| Access from EKS | IAM database authentication: pods mint short-lived tokens with their IRSA role. No DB passwords exist in application config or OpenTofu state. The module creates the `rds-db:connect` policy service teams attach to their roles. |
| Customer & payment data | Customer-managed KMS keys per region (automatic rotation), storage encrypted, TLS enforced (`rds.force_ssl = 1`), private database subnets only, no public accessibility, `pgaudit` SQL audit trail + connection logging, deletion protection and final snapshots in prod, backups (30 days in prod) with point-in-time recovery. |
| Non-experts | Tag-based subnet discovery (no subnet IDs to paste), environment-aware defaults, plan-time validation of the network layout, engine version resolved automatically, runbooks below. |

## Environment contract

This module assumes the standard platform environment:

- The network team owns **one VPC per environment per region**, named
  `apps-staging` / `apps-prod` (`Name` tag), each with **private database
  subnets tagged `tier = database`** spanning at least two AZs. The module
  discovers them automatically; provide `subnet_ids` if you ever need to place
  a database by hand.
- Services run on EKS in both regions and reach AWS through IAM roles.
- Regions default to `us-east-1` (primary) and `us-west-2` (failover).

## Usage

The module is applied directly as a root module. Smallest instantiation
(`minimal.tfvars`):

```hcl
name          = "checkout"
database_name = "checkout"
environment   = "staging"
```

```sh
tofu init
tofu plan -var-file=minimal.tfvars
tofu apply -var-file=minimal.tfvars
```

Production instantiation for a service, e.g. `checkout-prod.tfvars`:

```hcl
name          = "checkout"
database_name = "checkout"
environment   = "prod"

# EKS security groups allowed to reach the database (one list per region -
# security group IDs are region-scoped)
allowed_security_group_ids          = ["sg-0eksusprimaryregion"]
secondary_allowed_security_group_ids = ["sg-0ekssecondaryregion"]

# Service-specific capacity (defaults: 2 instances per region in prod)
instance_class           = "db.r7g.large"
instance_count           = 3
secondary_instance_count = 2

# Pin the engine version so upgrades are a deliberate, reviewed change
engine_version = "17.9"

# Stricter audit for PCI-scoped data
pgaudit_log = ["ddl", "role", "misc", "write", "read"]

tags = {
  team        = "commerce"
  "pci-scope" = "true"
}
```

Notes:

- Every resource is named `<name>-<environment>-…`, so staging and prod
  deployments coexist in the same account without collisions.
- If neither `allowed_security_group_ids` nor `allowed_cidr_blocks` is set, the
  database security group allows the environment VPC's CIDR so services in the
  same VPC can connect out of the box. Pin it to your EKS security groups for
  a tighter posture.
- `instance_class = "db.serverless"` switches both clusters to Aurora
  Serverless v2 with the given min/max ACU bounds.

## Connecting from EKS with IAM auth

1. Attach the generated policy (output `rds_db_connect_policy_arn`) to the
   service's IRSA role. It grants `rds-db:connect` on **both** regional
   clusters, so tokens keep working after a failover.
2. One-time bootstrap, from a break-glass session using the master secret
   (output `master_user_secret_arn`, RDS-managed, never in state), create a
   least-privilege role for the service:

   ```sql
   CREATE ROLE checkout_app LOGIN;
   GRANT CONNECT ON DATABASE checkout TO checkout_app;
   -- grant the service's schema/table privileges as appropriate
   ```

3. Pods connect with a token minted as their role; TLS is mandatory:

   ```sh
   PGPASSWORD="$(aws rds generate-db-auth-token \
     --hostname <primary_cluster.writer_endpoint> \
     --port 5432 --username checkout_app --region us-east-1)" \
   psql "host=<primary_cluster.writer_endpoint> port=5432 dbname=checkout \
     user=checkout_app sslmode=verify-full \
     sslrootcert=/var/tmp/global-bundle.pem"
   ```

   Writes always go to the writer endpoint; reads can use the reader endpoint
   in either region.

## Failover runbook

Identifiers come from the module outputs (`global_cluster_identifier`,
`primary_cluster`, `secondary_cluster`).

### Unplanned failover (a region is down)

1. Detach the failed primary from the global database. Aurora then promotes
   the remaining member — the standby cluster — to writer, typically in under
   a minute:

   ```sh
   aws rds remove-from-global-cluster \
     --global-cluster-identifier <global_cluster_identifier> \
     --db-cluster-identifier <primary_cluster.arn>
   ```

2. Point the service at the secondary region's cluster (output
   `secondary_cluster`; its `endpoint` is the writer endpoint once promoted) —
   via the service's connection config or service discovery. Writes resume.
   Data loss is bounded by replication lag: typically well under a second.

3. When the failed region recovers, rebuild a standby there (apply the module
   with the regions swapped, or re-add a member cluster) and run a planned
   failover to move the writer home.

### Planned failover (DR drills, region exit)

Use Aurora's managed planned failover — a lossless, engine-coordinated
switchover of the writer to the other region (supported on Aurora PostgreSQL):

```sh
aws rds failover-global-cluster \
  --global-cluster-identifier <global_cluster_identifier>
```

### Reconciling OpenTofu state afterwards

Failovers deliberately change live topology outside of OpenTofu. Afterwards,
either import the re-homed clusters into their resources
(`tofu import aws_rds_cluster.primary <cluster-identifier>`) or re-provision
the failed region's resources with the region variables. Treat that
reconciliation as part of the incident close-out, per service.

## Operations

- **Backups**: automated backups + PITR run in the region that owns the writer
  (30 days in prod). After failover, backups resume in the promoted region.
  Aurora global secondaries do not take their own automated backups;
  `secondary_backup_retention_period` exists but defaults to 0.
- **Engine version**: the module resolves AWS's default Aurora PostgreSQL
  version at plan time. Pin `engine_version` when you want upgrades reviewed.
- **Cluster parameters** (`rds.force_ssl`, pgaudit, connection logging) are
  managed in the primary region and replicated to the standby by Aurora global
  database semantics — hardening is defined exactly once.
- **Monitoring**: Performance Insights and enhanced monitoring are on by
  default; PostgreSQL and upgrade logs are exported to CloudWatch.
- **Teardown**: prod clusters have deletion protection and take a final
  snapshot. To destroy, temporarily set `deletion_protection = false`.
- Escape hatches: `subnet_ids` (explicit placement), `vpc_name` (non-standard
  VPC naming), `engine_version`, `instance_class`, both instance counts,
  backup retention, monitoring interval, audit classes, and extra `tags`.
