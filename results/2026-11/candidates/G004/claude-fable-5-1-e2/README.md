# aurora-postgresql-global

Production Aurora PostgreSQL for customer-facing services: an **Aurora Global
Database** with a writer cluster in one US region and a warm standby cluster in
a second. Storage-level replication keeps the standby within about a second of
the primary; managed failover promotes it in roughly a minute.

## Minimal usage

```hcl
service_name = "checkout"
environment  = "prod"
```

That is enough. The module discovers the network team's `apps-<environment>`
VPC and the subnets tagged `tier = database` in both regions, and applies the
production defaults below. Everything else is optional and documented in
`variables.tf`.

## What you get

| Area | Decision |
|---|---|
| Topology | Global database, `us-east-1` primary / `us-west-2` secondary, 2 instances per region (Multi-AZ in region, full capacity in the standby). |
| Connectivity | Each regional EKS deployment uses its **local** cluster's writer/reader endpoints. Write forwarding lets the secondary accept writes, so nothing changes on promotion. |
| Auth | IAM database authentication for services (`iam_connect_policy_arn` output — attach to the IRSA role). Master password generated and stored in Secrets Manager; never supplied or seen. |
| Encryption | Customer-managed, auto-rotating KMS key per region for storage, the secret, Performance Insights and logs. TLS 1.2+ enforced (`rds.force_ssl`), SCRAM-SHA-256 passwords. |
| Audit | pgaudit (DDL / role / settings), connection logging, slow queries > 1 s, exported to encrypted CloudWatch log groups (90-day retention). |
| Durability | 35-day automated backups, final snapshot on destroy, deletion protection on. |
| Observability | Performance Insights and Enhanced Monitoring (60 s) on every instance. |
| Network | Private subnets only, security group allowing 5432 from the VPC (or only from the SGs/CIDRs you pass). |

## Day-2: regional failover

* **Planned (DR drill, region maintenance):**
  `aws rds switchover-global-cluster --global-cluster-identifier <global_cluster_id> --target-db-cluster-identifier <secondary cluster ARN>`
  — zero data loss.
* **Unplanned (region down):**
  `aws rds failover-global-cluster --global-cluster-identifier <global_cluster_id> --target-db-cluster-identifier <secondary cluster ARN> --allow-data-loss`
  — RPO is the replication lag (normally < 1 s).

After an unplanned failover, once the original region recovers, run a
`switchover-global-cluster` back so the cluster roles match this configuration
again before the next `tofu apply`.

## After first apply

Create the application role(s) in PostgreSQL once, using the master credentials
from Secrets Manager:

```sql
CREATE ROLE app LOGIN;
GRANT rds_iam TO app;
```

Services then connect with an IAM auth token and the DB role name listed in
`iam_database_usernames`.
