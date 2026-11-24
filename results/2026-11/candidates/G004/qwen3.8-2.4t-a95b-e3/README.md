# Aurora PostgreSQL — Production Database Module

Reusable OpenTofu module the platform team uses to stand up the production
PostgreSQL databases behind our customer-facing services. Every database this
module creates is a **multi-region Aurora Global Database** sized for our
business requirement:

> If an AWS region fails, the service's database must be serving again from
> another region **within minutes**, having lost **no more than a few seconds
> of writes**.

## What the module builds

```
                primary region                     secondary region
             (default us-east-1)                (default us-west-2)
        ┌─────────────────────────────┐    ┌─────────────────────────────┐
        │  apps-<env> VPC             │    │  apps-<env> VPC             │
        │  ┌───────────────────────┐  │    │  ┌───────────────────────┐  │
 EKS ──►│  │ <svc>-<env>-primary   │  │    │  │ <svc>-<env>-secondary │◄─┼── EKS
 (5432) │  │  writer + N readers   │──┼────┼─►│  N standby instances  │  │ (5432)
        │  │  tier=database subnets│  │ <1s │  │  tier=database subnets│  │
        │  └───────────────────────┘  │ repl│  └───────────────────────┘  │
        └─────────────────────────────┘    └─────────────────────────────┘
                       ▲   one Aurora global cluster ties both together   ▲
```

Per service (`name`) and `environment`:

| Resource | Primary region | Secondary region |
|---|---|---|
| Aurora PostgreSQL cluster (member of one global cluster) | writable | read-only replica |
| Cluster instances (`instances_per_cluster`, default 2) | yes | yes |
| Customer-managed KMS key + alias, annual rotation | yes | yes |
| Cluster parameter group (TLS enforced) | yes | yes |
| Security group on port 5432 | yes | yes |
| DB subnet group over the `tier = database` subnets | yes | yes |

Plus, globally: the `aws_rds_global_cluster`, an Enhanced Monitoring IAM
role, and (by default) an RDS-managed master password in Secrets Manager.

## Design decisions

- **Aurora Global Database, not cross-region read replicas or backups.**
  Global Database replicates at the storage layer with typically < 1s lag
  (RPO: a few seconds at worst), and the secondary cluster already has
  running instances, so promotion serves traffic within minutes (RTO).
  Restoring backups alone could not meet either number.
- **Multi-AZ in both regions.** Default 2 instances per cluster, spread over
  AZs with explicit failover priority, so a single-AZ failure fails over
  inside the region without touching the DR path.
- **Network is discovered, not created.** The network team owns one VPC per
  environment (`apps-staging`, `apps-prod`) with private subnets tagged
  `tier = database`; the module looks them up by tag. Override `vpc_name` if
  an environment deviates. RDS itself rejects a subnet group that does not
  span at least two AZs.
- **Customer/payment-data hardening by default:**
  - storage encrypted with customer-managed, rotating KMS keys (per region);
  - `rds.force_ssl = 1` — TLS-only client connections;
  - IAM database authentication enabled, so EKS pods authenticate with
    short-lived tokens from their IAM roles (`rds-db:connect`) instead of
    static passwords;
  - no public accessibility; reachable only from inside the environment VPC
    CIDR plus security groups/CIDRs passed in `allowed_security_group_ids` /
    `allowed_cidr_blocks`;
  - master password generated and managed by RDS in Secrets Manager
    (`manage_master_user_password`); bring-your-own only for migrations;
  - point-in-time backups retained `backup_retention_days` (default 14,
    max 35), copies tagged, final snapshots taken on deletion, and
    `deletion_protection` on.
- **Observability built in:** Performance Insights, Enhanced Monitoring
  (60s), and PostgreSQL logs exported to CloudWatch.
- **Regions are inputs** (`primary_region` / `secondary_region`, default
  `us-east-1` / `us-west-2`) so the same module serves any US region pair.

## Usage

```hcl
module "checkout_db" {
  source = "./modules/aurora-postgresql"  # this module

  name        = "checkout"
  environment = "prod"

  allowed_security_group_ids = {
    primary   = [data.aws_security_group.eks_nodes_us_east_1.id]
    secondary = [data.aws_security_group.eks_nodes_us_west_2.id]
  }
}
```

`minimal.tfvars` shows the smallest valid instantiation (only `name` and
`environment` are required). Plan with:

```sh
tofu plan -var-file=minimal.tfvars
```

### Wiring EKS workloads

With IAM database auth enabled, grant the service's pod role:

```json
{
  "Effect": "Allow",
  "Action": "rds-db:connect",
  "Resource": "arn:aws:rds-db:<region>:<account-id>:dbuser:<cluster_resource_id>/postgres"
}
```

Pods then mint an auth token (valid 15 minutes) instead of using a password.
The secret in `master_credentials_secret_arn` is for admin/migration use.

## Failover runbook

**Planned (region maintenance, zero data loss):**

```sh
aws rds global-cluster failover \
  --global-cluster-identifier <svc>-<env> \
  --target-db-cluster-identifier <secondary_cluster_arn>
```

Both clusters swap roles; completes in a few minutes. Repoint the service at
the new writer endpoint (`secondary_writer_endpoint` output).

**Unplanned (primary region is down):**

1. Detach and promote the secondary cluster:

   ```sh
   aws rds global-cluster remove-from-global-database \
     --global-cluster-identifier <svc>-<env> \
     --db-cluster-identifier <secondary_cluster_arn>
   ```

2. Route the service to `secondary_writer_endpoint` (its EKS in that region
   was already allowed through the secondary security group).
3. Writes resume within minutes; at most a few seconds of the very latest
   writes may be lost. Rebuild the former primary as the new secondary once
   the region recovers (`tofu apply` against a revised configuration).

## Requirements

| Name | Version |
|---|---|
| OpenTofu | >= 1.6.0 |
| AWS provider | >= 5.100, < 6.0 |

Credentials come from the environment (IRSA/profile/env vars). The plan-time
provider needs permission to describe VPCs and subnets in both regions.
