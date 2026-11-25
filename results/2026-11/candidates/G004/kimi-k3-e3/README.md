# Aurora PostgreSQL for production services

Standard module for the PostgreSQL databases behind our customer-facing
services. Every instantiation is an **Aurora global database** spanning the
platform's two US regions, so a database keeps serving even when an entire
region is lost.

## What the business required, and how the design answers it

| Business requirement | Design answer |
| --- | --- |
| Database serving from another region **within minutes** of a regional failure | Aurora global database with a **running** secondary cluster. A managed switchover/failover promotes it to read/write in minutes — no restore, no rebuild. |
| **No more than a few seconds of writes** lost | Aurora storage-level cross-region replication; typical lag is well under a second. A CloudWatch alarm on `AuroraGlobalDBReplicationLag` guards the SLO continuously. |
| Data is **customer and payment data** | Encryption at rest (dedicated per-region KMS keys with rotation), SSL enforced (`rds.force_ssl=1`), private subnets only, never public, connection audit logging, PostgreSQL logs exported to CloudWatch, 35 days of backups + final snapshot + deletion protection. |
| Services on EKS **reach AWS through IAM roles** | IAM database authentication is enabled — applications connect with IAM-signed tokens, no stored passwords. |
| Platform engineers **aren't database specialists** | Only `name` and `environment` are required. Everything else is an opinionated default documented below. |

## Architecture

```
                 Aurora global database  (<name>-<environment>)
        ┌───────────────────────────────────────────────────────┐
        │                                                       │
  primary region (us-east-1)                secondary region (us-west-2)
  ┌───────────────────────────┐             ┌───────────────────────────┐
  │ cluster: <n>-<e>-primary  │  <1s typ.   │ cluster: <n>-<e>-secondary│
  │  writer + reader(s)       │ ──────────► │  read-only standby        │
  │  (Multi-AZ)               │ replication │  ≥1 instance, warm        │
  │  KMS key (module-managed) │             │  KMS key (module-managed) │
  └───────────────────────────┘             └───────────────────────────┘
   VPC apps-<env>, subnets tier=database     VPC apps-<env>, subnets tier=database
```

The network team's VPCs and subnets are **discovered by tag, never created**:
the VPC tagged `Name = apps-<environment>`, and its subnets tagged
`tier = database`, in each region.

## Usage

```hcl
# tfvars for one service's database
name             = "checkout"
environment      = "prod"
primary_region   = "us-east-1"
secondary_region = "us-west-2"

# Who may talk to PostgreSQL, per region (typically EKS node/pod SGs):
allowed_security_group_ids = {
  primary   = ["sg-0123abc"]   # EKS security group in us-east-1
  secondary = ["sg-0456def"]   # EKS security group in us-west-2
}
```

See `minimal.tfvars` for the smallest valid instantiation. After `tofu apply`,
read `primary.writer_endpoint` / `secondary.reader_endpoint` and the
`iam_db_auth` output.

## Connecting from EKS (IAM database authentication)

1. Create the application DB user once (as the master user, via the secret in
   `primary.master_user_secret_arn`) and grant IAM login:

   ```sql
   CREATE USER checkout_app;
   GRANT rds_iam TO checkout_app;
   -- plus the service's schema grants
   ```

2. Allow the service's IAM role to connect (use the `iam_db_auth` output):

   ```json
   {
     "Effect": "Allow",
     "Action": "rds-db:connect",
     "Resource": "arn:aws:rds-db:us-east-1:<acct>:dbuser:<cluster-resource-id>/checkout_app"
   }
   ```

3. The application generates an auth token (`aws rds generate-db-auth-token`,
   or the AWS SDK) and uses it as the password over SSL (`sslmode=require` —
   SSL is enforced server-side).

## Disaster recovery runbook

Switchover/failover is an **operational action**, deliberately not expressed
in OpenTofu (state should not flip on a failover).

**Planned switchover** (zero data loss, e.g. before maintenance in the
primary region):

```sh
aws rds switchover-global-cluster \
  --global-cluster-identifier <name>-<env> \
  --target-db-cluster-identifier arn:aws:rds:<secondary-region>:<acct>:cluster:<name>-<env>-secondary
```

**Unplanned failover** (primary region down; may lose the last few seconds of
writes — exactly what the replication-lag alarm exists to bound):

```sh
aws rds failover-global-cluster \
  --global-cluster-identifier <name>-<env> \
  --target-db-cluster-identifier arn:aws:rds:<secondary-region>:<acct>:cluster:<name>-<env>-secondary
```

After promotion:

1. Point the service at the new writer endpoint (the old secondary's cluster
   endpoint becomes read/write).
2. Rebuild the lost region later by re-running `tofu apply` once the region is
   healthy — it rejoins as the new secondary.

Caveat: the RDS-managed master user secret lives in the original primary
region's Secrets Manager. It remains retrievable cross-region, but applications
should never need it — they use IAM auth.

## Design decisions this module owns

- **Aurora global database** (not snapshots, not cross-region read replicas)
  because it is the only option meeting minutes-RTO / seconds-RPO.
- **Two providers, two regions** configured by the module itself; a `check`
  block refuses identical regions.
- **Secondary is always warm** (`secondary_instance_count >= 1`) — a headless
  secondary cannot accept traffic within minutes.
- **KMS**: one dedicated key per region with rotation (KMS keys are regional);
  bring-your-own via `primary_kms_key_arn` / `secondary_kms_key_arn`.
- **Master password** is RDS-managed in Secrets Manager; it never appears in
  configuration or state.
- **Networking**: subnets discovered via the network team's tags; security
  group allows ingress on the PostgreSQL port only from explicitly listed
  security groups/CIDRs, no egress, no public access.
- **Backups**: 35-day retention (Aurora maximum, point-in-time recovery),
  final snapshot on destroy, deletion protection on.
- **Upgrades are deliberate**: engine version pinned, auto minor upgrades off,
  `apply_immediately` off, defined backup/maintenance windows.
- **Observability**: Performance Insights (KMS-encrypted), enhanced monitoring
  (dedicated IAM role), PostgreSQL logs to CloudWatch, per-instance CPU alarms
  and a global replication-lag alarm to per-region SNS topics (subscribe
  on-call there).

## Inputs and outputs

Run `tofu plan -var-file=minimal.tfvars` to see everything. Key inputs:
`name`, `environment` (required); `primary_region`/`secondary_region`,
`engine_version`, `instance_class`, `primary_instance_count`,
`secondary_instance_count`, `allowed_security_group_ids`,
`allowed_cidr_blocks` (common overrides). Key outputs: `primary`,
`secondary`, `iam_db_auth`, `global_cluster_identifier`.

## Requirements

- OpenTofu >= 1.6, AWS provider >= 5.0.
- AWS credentials with RDS/KMS/IAM/SNS/CloudWatch permissions in both regions.
- The network team's `apps-<environment>` VPC with `tier = database` subnets
  in both regions.
