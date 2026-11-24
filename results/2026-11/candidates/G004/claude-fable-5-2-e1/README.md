# Aurora PostgreSQL for production services (two-region)

Stands up one service's PostgreSQL database as an **Aurora global database**:
a writer cluster in the primary region and a continuously replicated, fully
sized cluster in a second US region. If a region fails, the other region is
promoted with one command, in minutes, losing at most the replication lag
(normally under a second).

```hcl
# checkout.tfvars
service     = "checkout"
environment = "prod"
```

```sh
tofu init
tofu apply -var-file=checkout.tfvars
```

Those two values are all a service has to provide. See `variables.tf` for the
optional knobs and `examples/full.tfvars` for a fuller example.

## What the module decides for you

| Area | Decision |
|------|----------|
| Topology | Aurora global database across `primary_region` (default `us-east-1`) and `secondary_region` (default `us-west-2`). Each region runs `instances_per_region` instances (default 2) across availability zones; the DR region is the same size as the primary so it can take full load on promotion. |
| Network | Discovers the network team's `apps-<environment>` VPC and its `tier = database` subnets in each region. Never publicly accessible. The database only accepts PostgreSQL traffic from a per-region *client* security group the module creates (plus anything you explicitly list). |
| Encryption | Storage, backups, snapshots, logs, Performance Insights and the admin secret are encrypted with a customer-managed KMS key per region (rotation on). TLS is mandatory for every connection. |
| Service login | IAM database authentication: pods use their IAM role to obtain 15-minute tokens. No application passwords exist. |
| Admin login | A random break-glass password is generated at apply time and stored only in Secrets Manager (replicated to the DR region). It is never written to state or shown in a plan. |
| Backups | 35 days of point-in-time recovery in each region, final snapshot on deletion, deletion protection on. |
| Audit | Connections, disconnections, DDL and role/permission changes (pgaudit) are logged to encrypted CloudWatch log groups kept for 1 year. |
| Upgrades | Engine version is pinned; nothing upgrades on its own. Change `engine_version` to upgrade. |
| Monitoring | Enhanced monitoring, Performance Insights, and alarms on cross-region replication lag (> 5 s) and CPU in both regions. Pass `alarm_topic_arns` to be notified. |

## After the first apply (once per database)

1. Read the admin credentials from the `master_secret_arns` output and create
   the service user(s) listed in the `iam_database_users` output:

   ```sql
   CREATE USER checkout;
   GRANT rds_iam TO checkout;
   GRANT ALL ON DATABASE checkout TO checkout;
   ```

2. Give the service's pod role permission to log in: list it in
   `iam_auth_role_names`, or attach `iam_connect_policy_arn` yourself.
3. Attach the region's security group from `client_security_group_ids` to the
   service's pods (EKS `SecurityGroupPolicy`).
4. Point the service at the endpoints of its own region from the `endpoints`
   output (`cluster` for writes, `reader` for reads), authenticating with an
   IAM token and `sslmode=verify-full`.

## When a region fails

Run the `disaster` command from the `regional_failover_commands` output. It
promotes the surviving region to writer. Regional endpoints keep their names,
so services in the surviving region carry on once promotion completes. The
failed region rejoins as the replica automatically when it comes back.

Rehearse with the `drill` command (a zero-data-loss switchover) on a schedule;
staging uses the same topology precisely so this can be practised there.

Promotion is a deliberate human (or runbook automation) action rather than
automatic: an automatic cross-region failover on a false alarm would be its own
outage.

## Things to know

* **Requires** OpenTofu >= 1.11 and AWS provider >= 6.0 (write-only arguments
  keep the admin password out of state).
* **Write forwarding** (on by default) lets pods in the DR region write through
  their local cluster endpoint. Sessions that write there must set
  `apg_write_forward.consistency_mode` (for example `session`).
* **Rotate the admin password** by increasing `master_password_version`.
* **`enforced_rpo_seconds`** turns the replication-lag target into a hard
  guarantee (Aurora blocks commits when the DR region is too far behind, 20 s
  minimum). It is off by default because it trades write availability in the
  healthy region for that guarantee.
* **Major version upgrades** of a global database are a planned procedure
  (new parameter group family, coordinated across regions); do not just bump
  the major number in `engine_version` on a live database.
* **Decommissioning**: set `deletion_protection = false`, apply, then destroy.
  A final snapshot of each cluster is kept.
