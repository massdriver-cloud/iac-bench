# GKE Standard platform module

One module for every production GKE **Standard** cluster. Product teams share
each cluster; the platform team supplies only what is cluster-specific and
trusts the module for everything else.

## What the caller must provide

| Variable       | Meaning                                                        |
| -------------- | -------------------------------------------------------------- |
| `project_id`   | Project that also owns the environment VPC                      |
| `environment`  | `staging` or `prod` — selects the `apps-<env>` VPC              |
| `region`       | A US region with an existing `apps-<env>-gke-<region>` subnet   |
| `cluster_name` | Unique cluster name                                            |

The subnet's secondary ranges must be named `pods` and `services` (the network
team's standard). See `minimal.tfvars` for the smallest valid instantiation.

## What the module decides (and why)

**Resilience**
- Regional cluster: zonal control plane replicas and nodes spread across three
  zones (override with `node_locations`).
- Node pools autoscale with `location_policy = BALANCED`; minimum 1 node per
  zone so a zone failure never empties a pool.
- Auto-repair + auto-upgrade everywhere; surge upgrades with
  `max_unavailable = 0` so capacity is added before it is drained.
- `REGULAR` release channel (automatic, proven-version upgrades) and an
  overnight-US maintenance window.
- Upgrade notifications published to a per-cluster Pub/Sub topic.

**Security**
- Private nodes and (by default) a private control plane endpoint. To administer
  from outside the VPC set `enable_private_endpoint = false` **and** supply
  `master_authorized_networks` — a public endpoint without an allow-list is
  rejected by a precondition.
- Workload Identity enabled; node metadata server enforced (`GKE_METADATA`),
  legacy metadata endpoints disabled. Apps reach Pub/Sub, GCS, Cloud SQL, etc.
  via their own Google service accounts bound to Kubernetes service accounts —
  never via node credentials or key files.
- Dedicated node service account with only logging/monitoring/metadata/
  Artifact Registry reader roles (no Compute default SA, no Editor).
- Shielded nodes with secure boot + integrity monitoring; no client
  certificates; Dataplane V2 so Kubernetes NetworkPolicy is enforced.
- Optional application-layer Secret encryption (`database_encryption_key_name`,
  Cloud KMS CMEK) and Binary Authorization (`binary_authorization_mode`).

**Operability**
- System + workload logging, system monitoring, managed Prometheus, NodeLocal
  DNSCache, VPA recommendations, GCE PD CSI driver, cost allocation enabled.
- Extra capacity via `additional_node_pools` (e.g. bigger machines or spot
  batch pools with taints) — same hardening as the primary pool.
- `deletion_protection = true` is recommended for long-lived prod clusters.

## Example

```hcl
project_id   = "acme-apps-prod"
environment  = "prod"
region       = "us-east1"
cluster_name = "shared-prod-east"

machine_type      = "n2-standard-8"
min_node_count    = 2
max_node_count    = 6
deletion_protection          = true
database_encryption_key_name = "projects/acme-apps-prod/locations/us-east1/keyRings/gke/cryptoKeys/secrets"

additional_node_pools = {
  batch = {
    machine_type   = "e2-standard-8"
    spot           = true
    max_node_count = 10
    taints = [{ key = "workload", value = "batch", effect = "NO_SCHEDULE" }]
  }
}
```

## After apply

```
gcloud container clusters get-credentials <cluster_name> --region <region> --project <project_id>
```

Bind app identities for Google Cloud access:

```
gcloud iam service-accounts add-iam-policy-binding APP_SA@PROJECT.iam.gserviceaccount.com \
  --role roles/iam.workloadIdentityUser \
  --member "serviceAccount:PROJECT.svc.id.goog[NAMESPACE/KSA_NAME]"
```

Note: `master_ipv4_cidr_block` defaults to `172.16.0.0/28`; each cluster in a
VPC needs its own free /28 — coordinate with the network team.
