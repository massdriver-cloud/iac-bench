# Aurora PostgreSQL for production services

Stands up one service's PostgreSQL database as an **Aurora Global Database**
across two US regions: a writer cluster in the primary region and a warm,
identically sized standby cluster in the secondary region.

```hcl
service          = "checkout"
environment      = "prod"        # or "staging"
primary_region   = "us-east-1"
secondary_region = "us-west-2"

# Usually also:
client_security_group_ids = {
  primary   = ["sg-..."]         # the service's pods/nodes in us-east-1
  secondary = ["sg-..."]         # ... and in us-west-2
}
app_role_names = ["checkout-prod"] # the IAM role(s) the pods run as
```

Requires OpenTofu 1.11 or newer.

## What the module decides for you

| Concern | Decision |
| --- | --- |
| Surviving a region failure | Aurora Global Database. The standby region runs the same number and size of instances as the primary, so it is ready for full load when promoted. Replication lag is normally under a second. |
| Surviving an AZ failure | At least two instances per region, so an AZ loss is an automatic in-region failover, not a regional one. |
| Network | Looks up the `apps-<environment>` VPC and its `tier = database` subnets in each region. Never publicly accessible. Only the security groups you list can reach port 5432. |
| Service logins | IAM database authentication. Pods get short-lived tokens from their IAM role; there are no application passwords. The connect policy covers both regions. |
| Encryption | A customer-managed KMS key per region for storage, backups, Performance Insights, logs and the master secret. TLS is mandatory for clients. |
| Master password | Break-glass only. Generated at apply time, kept out of plan and state, stored in Secrets Manager and replicated to the standby region. |
| Audit trail | Connections, disconnections and DDL go to encrypted CloudWatch Logs, kept 400 days. Query text is deliberately not logged, because it would contain customer and payment values. |
| Backups | 14 days of point-in-time recovery in each region; final snapshot on delete; deletion protection on. |
| Where data lives | Both regions must be commercial US regions. |

## Connecting

Use the `writer_endpoint` output. It is the global writer endpoint and always
points at the writer in whichever region is currently primary.

One-time bootstrap per database, as the master user (credentials are in the
`master_secret_arn` secret):

```sql
CREATE USER app;            -- one per name in app_database_users
GRANT rds_iam TO app;
GRANT ... ;                 -- the privileges the service needs
```

Services then connect as that user with an IAM auth token over TLS. Tokens are
signed for a specific region and endpoint: generate them for the regional
cluster endpoint (`cluster_endpoints` output) of the region that currently
holds the writer.

## When a region fails

Cross-region failover is **not automatic**; Aurora leaves that decision to an
operator (or to your own automation). To promote the surviving region, run the
command from the `regional_failover_commands` output for that region:

```
aws rds failover-global-cluster --region <surviving region> \
  --global-cluster-identifier <service>-<environment> \
  --target-db-cluster-identifier <ARN of the surviving region's cluster> \
  --allow-data-loss
```

Promotion typically completes in a minute or two. The global writer endpoint
moves with it. When the failed region returns, Aurora rebuilds it as the new
standby. To move the writer back (or to rehearse in staging) use
`aws rds switchover-global-cluster`, which loses no data.

No OpenTofu change is needed after a failover: clusters are named after their
region, not their role, and the module ignores the attributes that flip.

## Things to know

* **Data-loss bound.** Replication is asynchronous. The module alarms when lag
  exceeds `replication_lag_alarm_seconds` (default 5) but, by default, does not
  block writes to enforce it. `enforced_rpo_seconds` turns on Aurora's managed
  RPO, which does; its floor is 20 seconds and, with only two regions, it
  pauses commits on the writer whenever the standby region is unreachable.
* **Alarm delivery.** The lag alarms notify nobody until you pass SNS topics in
  `alarm_topic_arns`.
* **Nothing can connect by default.** Pass `client_security_group_ids`.
* **Decommissioning** is two steps: apply with `deletion_protection = false`,
  then destroy.
* **Rotating the master password:** increment `master_password_version`.
