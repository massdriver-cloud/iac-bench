# Aurora PostgreSQL production database module

Reusable OpenTofu root module for the platform team's customer-facing service
databases. You supply **what is specific to your service** (`service_name`,
`environment`); the module owns every production design decision.

## What it builds

An **Aurora PostgreSQL Global Database** spanning two US regions
(default `us-east-1` primary, `us-west-2` secondary):

| Concern | Decision |
|---|---|
| Regional DR | Global Database storage replication: RPO ~1s, RTO ~minutes via failover/switchover. Secondary runs full-sized compute (2 × `db.r6g.large` by default) so no provisioning is needed during an incident. |
| In-region HA | 2 instances per region (writer + reader), automatic in-region failover. |
| Encryption at rest | Customer-managed KMS key per region, rotation enabled, 30-day deletion window. |
| Encryption in transit | `rds.force_ssl = 1` — plaintext connections are rejected. |
| Credentials | Master password generated & managed by RDS in Secrets Manager (CMK-encrypted). Never in code, variables, or plan output. |
| App authentication | IAM database authentication enabled; per-region `rds-connect` IAM policies to attach to your EKS (IRSA/Pod Identity) roles. |
| Network | Private `tier=database` subnets in the network team's `apps-<env>` VPC, discovered by tag. SG allows 5432 only from the VPC CIDR (+ optional extra CIDRs). `publicly_accessible = false`. |
| Backups | 35-day PITR, copy tags to snapshots, final snapshot on destroy, deletion protection on the global + both regional clusters. |
| Observability | PostgreSQL logs to CloudWatch, connection/disconnection logging, slow-query logging (>1s), enhanced OS monitoring (60s), Performance Insights (731 days, CMK). |
| Alerting | SNS topic per region; alarms for CPU in both regions and **global RPO lag > 10s** in the DR region. |

## Usage

```hcl
# terraform.tfvars
service_name = "checkout"
environment  = "prod"          # or "staging"
# optional:
# primary_region / secondary_region, instance_class, engine_version,
# alert_email = "oncall@example.com", tags = { Team = "payments" }
```

```
tofu init
tofu apply -var-file=your-service.tfvars
```

Prerequisites (owned by the network team, discovered by data sources):
a VPC tagged `Name = apps-<environment>` and ≥2 subnets tagged
`tier = database` in **both** regions.

### Connecting from EKS

1. Attach the output `primary.rds_connect_policy_arn` (and the secondary one)
   to the service's IAM role in each region.
2. Create the DB user once: `CREATE USER app_user; GRANT rds_iam TO app_user;`
3. Connect with an IAM auth token to `primary.writer_endpoint` (writes) or
   `primary.reader_endpoint` (reads), port 5432, TLS required
   (`sslmode=verify-full`, RDS CA bundle).

## DR runbook

**Planned move (no outage, zero data loss):**
```
aws rds switchover-global-cluster \
  --global-cluster-identifier <global_cluster_identifier output> \
  --target-db-cluster-identifier <secondary.cluster_arn output> \
  --region <secondary region>
```

**Regional outage (RPO seconds, RTO minutes):**
```
aws rds failover-global-cluster \
  --global-cluster-identifier <global_cluster_identifier output> \
  --target-db-cluster-identifier <secondary.cluster_arn output> \
  --region <secondary region>
```
Then point the service in the DR region at `secondary.writer_endpoint`
(the cluster endpoint becomes writable after promotion) and re-create the
old region as the new secondary when it recovers. Rehearse switchovers in
staging quarterly.

The `AuroraGlobalDBRPOLag` alarm warns *before* an incident if replication
falls behind the seconds-level RPO objective — treat it as urgent.

## Deliberate constraints

- US regions only (data residency); regions must differ.
- `environment` limited to `staging`/`prod` (VPC naming contract).
- ≥2 primary instances, ≥7-day backups: production HA/PITR floors.
- `deletion_protection` defaults true; turning it off should be a reviewed change.
