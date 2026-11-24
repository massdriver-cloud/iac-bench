# aurora-global-postgres

Standard OpenTofu root module for a production Aurora PostgreSQL database that
survives the loss of an AWS region.

## What it builds

- An **Aurora Global Database** spanning `primary_region` (writer) and
  `secondary_region` (read-only, promotable). Cross-region replication is
  typically sub-second, which is what bounds the write loss on failover.
- Per region: a provisioned cluster with `instance_count` instances (default 2,
  spread across AZs), a DB subnet group built from the `tier = database`
  subnets of the `apps-<environment>` VPC, a security group limited to
  PostgreSQL from that VPC, and a cluster parameter group that forces TLS.
- A customer-managed KMS key in each region (keys are regional), with rotation.
- Master password generated and held in Secrets Manager (RDS rotates it).
- IAM database authentication. Services get `rds-db:connect` through their IAM
  role. No static application passwords.
- Enhanced monitoring, Performance Insights, PostgreSQL logs to CloudWatch.
- Deletion protection, 35-day backups, copied tags, final snapshots.

The module creates no networking. The network team owns the VPCs and subnets.

## Usage

```hcl
module "checkout_db" {
  source = "./"   # or your registry/Git source, pinned

  service_name     = "checkout"
  environment      = "prod"
  primary_region   = "us-east-1"
  secondary_region = "us-west-2"

  # Optional, service-specific:
  database_name          = "checkout"
  iam_database_users     = ["checkout_app"]
  application_role_names = ["checkout-prod-irsa"]
  instance_class         = "db.r6g.xlarge"
}
```

Run it as a root module with `tofu apply`. Credentials come from the
environment.

Inputs you must set: `service_name`, `environment`, `primary_region`,
`secondary_region`. Everything else has a production-appropriate default.

## After the first apply: database users

IAM authentication needs the PostgreSQL role to exist and be granted `rds_iam`.
Connect with the managed master credentials (from the secret in
`master_user_secret_arn`) and run:

```sql
CREATE USER checkout_app;
GRANT rds_iam TO checkout_app;
-- then grant the schema privileges the service needs
```

Do this in the primary cluster. The change replicates to the secondary.

Clients connect with a token from `aws rds generate-db-auth-token`, or the
equivalent in their SDK. The token is valid for 15 minutes, and the connection
must use `sslmode=require` (`rds.force_ssl` is enforced).

## Regional failover

Two procedures. Run both from a workstation or runbook with AWS credentials.

### Drill: planned switchover (no data loss)

Run this periodically to prove the secondary is healthy.

```
aws rds switchover-global-cluster \
  --global-cluster-identifier <global_cluster_id> \
  --target-db-cluster-identifier <secondary_cluster_arn> \
  --region <primary_region>
```

The roles swap. The old writer becomes a secondary. Then run `tofu plan`.

### Outage: unplanned failover (bounded data loss)

Use this when the primary region is down and cannot be reached.

```
aws rds failover-global-cluster \
  --global-cluster-identifier <global_cluster_id> \
  --target-db-cluster-identifier <secondary_cluster_arn> \
  --region <secondary_region>
```

Writes not yet replicated when the region failed are lost. With normal
replication lag, that is seconds of writes. The `failover_runbook` output has
the exact commands for this stack.

After the failover:

1. Point services at the surviving region's writer endpoint.
   `secondary_writer_endpoint` is the new writer. Services read their endpoint
   from config. Update that config (or your DNS record) for the affected
   service. The module does not automate this.
2. Do not run `tofu apply` against the failed region until it recovers. Its
   state will show drift until the old writer rejoins as a secondary.
3. Once the old primary region recovers, it rejoins as a read-only secondary
   (it will not take writes unless you switch back).

### Why this is not fully automatic

Region failure takes down the monitoring that would detect it, and
promoting a secondary can lose writes. An automatic promotion would make that
trade-off without a human, so the module leaves the decision with an operator.
A failover should take a few minutes end to end.

## Operational notes

- `deletion_protection` defaults to true. To tear down a disposable
  environment, set it to `false`, apply, then destroy. Final snapshots are
  taken automatically.
- `instance_class` must be a Global Database-capable class in both regions.
- `engine_version` must be supported for Global Database in both regions. The
  engine family is derived from the major version, which selects the parameter
  group.
- Minor version upgrades are applied during `preferred_maintenance_window`.
  Set `engine_version` to the new value to track them in state.
- `additional_ingress_cidrs` is for CIDRs outside the VPC only (for example,
  VPN). Services inside the VPC, including EKS pods using VPC CIDR networking,
  are already allowed.
