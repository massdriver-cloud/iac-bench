# Aurora PostgreSQL for production services (region-failure resilient)

The platform team's standard OpenTofu module for standing up production
PostgreSQL databases on Amazon Aurora. It is built to meet the bar the business
set after the last regional outage:

> If an AWS region fails, a service's database must be serving again from
> another region within minutes, having lost no more than a few seconds of
> writes.

## Architecture

```
            Aurora Global Database (storage-level replication, typically <1s lag)

  primary region (e.g. us-east-1)                 secondary region (e.g. us-west-2)
 ┌──────────────────────────────────┐            ┌──────────────────────────────────┐
 │ <svc>-<env>    read-write cluster│ ─────────► │ <svc>-<env>-dr   standby cluster │
 │ writer + reader(s), spread over  │            │ serves local reads; promoted to  │
 │ AZs; CMK-encrypted storage;      │            │ read-write on regional failover; │
 │ secret in Secrets Manager; SG:   │            │ own CMK + secret; identical      │
 │ 5432 from the VPC only; TLS on   │            │ hardened posture                 │
 └──────────────────────────────────┘            └──────────────────────────────────┘
```

For each service + environment the module creates:

- An **Aurora global cluster** spanning the two regions — the replication fabric.
- A **primary (read-write) cluster** in `primary_region` with
  `primary_instance_count` instances (default 2: one writer plus one reader,
  placed in distinct AZs so an AZ failure fails over within the region).
- A **secondary cluster** in `secondary_region` (default 1 instance). It serves
  local reads during normal operation and is promoted when the primary region
  is lost.
- **Network discovery, not creation**: it looks up the environment's VPC
  (Name tag `apps-<environment>`, i.e. `apps-staging` / `apps-prod`) and the
  network team's private subnets tagged `tier = database`, then builds a subnet
  group and a security group per region. Ingress is 5432 from the VPC CIDR
  only; nothing is publicly accessible.
- **Encryption everywhere**: a customer-managed KMS key per region (rotation
  on) protecting cluster storage and the credentials secret; TLS enforced at
  the database via `rds.force_ssl`; IAM database authentication enabled for
  EKS workloads that prefer short-lived tokens.
- **Credentials**: a generated master password stored as a Secrets Manager
  secret **in both regions**, so services authenticate immediately after a
  failover with no out-of-band copying. The password is never exposed in
  outputs.
- **Operability**: Enhanced Monitoring + Performance Insights, PostgreSQL logs
  exported to CloudWatch with bounded retention, connection/disconnection
  auditing, deletion protection and final snapshots.

## How the bar is met

- **RTO (minutes)** — the secondary cluster is warm; nothing is restored from
  backup. Promotion is a single managed API call and typically completes in a
  couple of minutes.
- **RPO (seconds)** — global-database storage replication typically lags by
  less than a second. A *planned* failover (primary still healthy) loses no
  writes at all; an unplanned one loses at most the in-flight, unreplicated
  writes.

## Usage

```bash
tofu init
tofu plan -var-file minimal.tfvars
tofu apply -var-file minimal.tfvars
```

Copy `minimal.tfvars` per service/environment and supply the four required
inputs: `service_name`, `environment`, `primary_region`, `secondary_region`.
Everything else has a production default; see `variables.tf` for the tunables
(instance class/counts, engine version, backup retention, windows, …).

Credentials come from the environment (IAM roles — pipelines and EKS workloads
never hold long-lived keys), so no provider credentials are declared.

### Giving a service access to the secret

The service's IRSA role needs read access to the secret (outputs
`primary_credentials_secret_arn` / `secondary_credentials_secret_arn`), e.g.:

```json
{
  "Effect": "Allow",
  "Action": ["secretsmanager:GetSecretValue"],
  "Resource": "<secret arn>"
}
```

## Failover runbook (regional outage)

1. **Confirm** the primary region is genuinely down — do not fail over on a blip.
2. **Promote** the secondary cluster (also available as the `failover_command` output):

   ```bash
   aws rds failover-global-cluster \
     --global-cluster-identifier <output global_cluster_identifier> \
     --target-db-cluster-identifier <output secondary_cluster_arn>
   ```

   Promotion typically completes in a couple of minutes; the secondary cluster
   becomes read-write.
3. **Point the service at the secondary region.** Services read the same-named
   credentials secret in their own region and connect to the secondary writer
   endpoint (`secondary_writer_endpoint`), or flip their DNS indirection to it.
4. **Freeze `tofu apply` on this module** while the incident is open — the
   configuration still describes the pre-failover topology.
5. **Re-align after recovery.** The old primary region's cluster is detached
   from the global database after a failover. Either swap `primary_region` /
   `secondary_region` and use `tofu state mv` to swap the primary/secondary
   resource addresses (take a manual snapshot first; rehearse in staging), or
   tear the old-primary resources out of state and re-apply to rebuild it as
   the new standby.

## Design decisions (why, briefly)

| Decision | Why |
| --- | --- |
| Aurora Global Database instead of cross-region snapshot restores | Snapshot restores take tens of minutes and lose up to the last backup; storage replication fails over in minutes with ~seconds of loss. |
| Module discovers the VPC/subnets instead of creating them | Networking is owned by the network team; one VPC per environment per region already exists with `tier = database` subnets. |
| Customer-managed KMS key per region | Customer + payment data: rotation, CloudTrail visibility, revocable access. |
| Credentials secret in both regions | After a failover, services must authenticate immediately. |
| TLS forced, VPC-only access, deletion protection, final snapshots | Baseline for customer/payment data. |
| Enhanced Monitoring + Performance Insights on by default | The platform team isn't DBA-staffed; ship the observability a DBA would demand. |
| Providers configured inside the module (primary + `secondary` alias) | Regions are per-service inputs; the module is run directly as a root module. |

## Outputs

Run `tofu output` after apply. Key ones: `primary_writer_endpoint`,
`secondary_writer_endpoint` / `secondary_reader_endpoint`,
`*_credentials_secret_arn`, `global_cluster_identifier`, `failover_command`.
