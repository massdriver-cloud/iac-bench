# GKE Standard production cluster module

One reusable OpenTofu root module for every new production GKE **Standard**
cluster. Product teams share these clusters; the module bakes in the
resilience and security decisions so operators only supply what is specific
to each cluster.

## What the module decides for you

| Concern | Decision |
|---|---|
| Topology | **Regional** cluster (`us-*` only): HA control plane, nodes spread across all zones (min 1 node/zone ⇒ ≥3 nodes). |
| Network | Attaches to the network team's existing VPC `apps-<environment>` and subnet `apps-<environment>-gke-<region>`, secondary ranges `pods` / `services`. VPC-native (alias IPs). Creates **no** network resources. Same project as the VPC. |
| API access | **Private nodes** always. Public control-plane endpoint only reachable from `master_authorized_networks` (required input); GCP-public-CIDR access disabled. Set `enable_private_endpoint = true` for no public endpoint at all. |
| Workload → GCP auth | **Workload Identity** enabled (`<project>.svc.id.goog`). Pods impersonate their own Google service accounts for Pub/Sub, Cloud Storage, Cloud SQL, etc. No SA keys. |
| Node identity | Dedicated node service account with only logging/monitoring/metadata-write/artifact-registry-read roles — never the Compute default SA. |
| Node hardening | Shielded nodes (secure boot + integrity monitoring), COS_CONTAINERD, legacy metadata endpoints disabled, GKE metadata server (`GKE_METADATA`). |
| Tenant isolation | **Dataplane V2** (`ADVANCED_DATAPATH`) — Kubernetes NetworkPolicy is enforced out of the box. |
| Upgrades | REGULAR release channel, auto-upgrade + auto-repair, daily maintenance window (04:00 UTC) plus optional freeze windows, surge upgrades with `max_surge=1, max_unavailable=0`. |
| Scaling | Cluster autoscaler per zone (default 1–3), BALANCED location policy; `max_pods_per_node = 64` to keep pod-IP usage predictable. |
| Observability | System + workload logging, system metrics and managed Prometheus. |
| Safety | `deletion_protection = true` by default; `environment`/`managed-by` labels always applied. |

## Required inputs (everything else has a safe default)

- `project_id` — project that owns the environment VPC.
- `cluster_name` — ≤24 chars, lowercase (`<name>-nodes` SA and `<name>-primary` pool are derived from it).
- `environment` — `staging` or `prod` (selects the VPC/subnet).
- `master_ipv4_cidr_block` — a **/28 unique per cluster** within the VPC, e.g. `172.16.0.0/28`, `172.16.0.16/28`, … Coordinate allocations with the network team.
- `master_authorized_networks` — office/VPN CIDRs allowed to reach the API server.

See `minimal.tfvars` for the smallest valid instantiation, and `variables.tf`
for the optional knobs (region, machine type, autoscaler bounds, disks,
release channel, maintenance window/exclusions, labels, private endpoint).

## Usage

```hcl
# terraform.tfvars for a new cluster
project_id             = "acme-apps-platform"
cluster_name           = "checkout-prod-east"
environment            = "prod"
region                 = "us-east1"
master_ipv4_cidr_block = "172.16.0.16/28"
master_authorized_networks = [
  { cidr_block = "203.0.113.0/24", display_name = "platform-office" },
]
```

```sh
tofu init
tofu plan  -var-file=terraform.tfvars
tofu apply -var-file=terraform.tfvars
```

Credentials come from the environment (Application Default Credentials).

## For product teams: accessing Google Cloud services

Bind your Kubernetes service account to a Google service account that has the
Pub/Sub / GCS / Cloud SQL roles you need:

```sh
gcloud iam service-accounts add-iam-policy-binding APP_SA@PROJECT.iam.gserviceaccount.com \
  --role=roles/iam.workloadIdentityUser \
  --member="principal://iam.googleapis.com/projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/PROJECT.svc.id.goog/subject/system:serviceaccount/NAMESPACE/KSA_NAME"
```

then annotate the Kubernetes service account with
`iam.gke.io/gcp-service-account: APP_SA@PROJECT.iam.gserviceaccount.com`.
Never grant application permissions to the node service account
(`node_service_account_email` output).

## Prerequisites owned by other teams

- VPC `apps-<env>` with subnet `apps-<env>-gke-<region>` and secondary ranges
  `pods` and `services` sized for the cluster (network team).
- Cloud NAT on that subnet for node/pod egress (nodes have no public IPs).
- GKE, Compute, IAM, Logging/Monitoring APIs enabled in the project.
