# Aurora PostgreSQL for production services (two-region)

Stands up one Aurora PostgreSQL **global database** for a service: a writer
cluster in `primary_region` and a continuously replicated, fully sized standby
cluster in `secondary_region`, each inside the network team's
`apps-<environment>` VPC on the subnets tagged `tier = database`.

## Minimal use

```hcl
service          = "checkout"
environment      = "prod"
primary_region   = "us-east-1"
secondary_region = "us-west-2"
```

To let the service in, add its EKS security groups and pod IAM roles:

```hcl
client_security_group_ids = {
  "us-east-1" = ["sg-0123456789abcdef0"]
  "us-west-2" = ["sg-0fedcba9876543210"]
}
app_iam_role_names = ["checkout-prod-use1", "checkout-prod-usw2"]
```

Then, once, as the administrator (credentials are in the `master_secret_name`
secret): `CREATE USER app; GRANT rds_iam TO app;` plus the grants the service
needs.

## What the module decides

| Concern | Decision |
|---|---|
| Region failure | Aurora global database; the standby region runs the same number and size of instances as the primary, so promotion takes minutes. Promotion is a deliberate operator action - see the `regional_failover_command` output. |
| Data loss bound | Managed RPO (`rds.global_db_rpo`) of 20 s, the lowest Aurora allows; typical lag is under 1 s and an alarm fires above 5 s. **Trade-off:** if the standby is unreachable for longer than the bound, commits on the writer pause until it catches up or the bound is lifted (`managed_rpo_seconds = null`). |
| AZ failure | 2 instances per region in different availability zones; Aurora fails over automatically inside the region. |
| Bad deploys / deletes | 35 days of point-in-time recovery in each region, deletion protection, final snapshot on destroy. |
| Encryption | Customer-managed KMS key per region (rotation on) for storage, backups, logs, Performance Insights and the admin secret; TLS 1.2+ required on every connection. |
| Access | Private subnets only, no public access; inbound 5432 only from listed security groups; services log in with IAM authentication; the admin password is generated, stored in Secrets Manager and replicated to the standby region. |
| Audit | Connections, disconnections, DDL and role changes logged (pgaudit) to an encrypted CloudWatch log group kept 365 days. |
| Endpoints | `global_writer_endpoint` always follows the writer. Services in the standby region can instead use their local cluster with write forwarding (enabled on the secondary cluster). |

## Operating notes

* After a failover or switchover the regions' roles are swapped in AWS but not
  in this configuration. The module tolerates that (it ignores the replication
  source), but switch back - or swap `primary_region` / `secondary_region`
  deliberately - before making structural changes.
* Upgrade versions by changing `engine_version`; both regions are upgraded
  through the global cluster.
* The generated admin password is held in the OpenTofu state: keep the state
  in an encrypted, access-controlled backend.
* To destroy: set `deletion_protection = false`, apply, then destroy.
