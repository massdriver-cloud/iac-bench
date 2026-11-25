# Platform GKE Standard module

The standard way to create a shared, production GKE **Standard** cluster.
Platform engineers supply only what is specific to their cluster; everything
else follows the module's production-safe defaults.

## What the module does for you

**Placement & networking**
- Regional cluster (multi-zonal control plane and nodes) in a US region, in the
  same project as the environment VPC.
- Wires into the network team's conventions automatically:
  VPC `apps-<environment>`, subnet `<vpc>-gke-<region>`, secondary ranges
  `pods` and `services`. VPC-native (alias IP) routing.
- Private nodes (no public IPs). The control-plane endpoint is only reachable
  from `master_authorized_networks` (required input — never open to the
  internet). Set `enable_private_endpoint = true` for a fully private endpoint.
- Dataplane V2 (eBPF) with built-in Kubernetes NetworkPolicy enforcement —
  teams can isolate their namespaces from each other.

**Security**
- Workload Identity enabled; GKE Metadata Server on every node; legacy
  metadata endpoints, legacy ABAC and client certificates all disabled.
- Dedicated least-privilege node service account (logging/monitoring/metadata
  writer + Artifact Registry reader only — never `roles/editor`).
- Shielded nodes: secure boot + integrity monitoring, COS_CONTAINERD images.
- Optional: Binary Authorization enforcement, CMEK application-layer secrets
  encryption (`database_encryption`).
- `deletion_protection = true` by default.

**Google Cloud service access for workloads (Pub/Sub, GCS, Cloud SQL, ...)**
- Declare entries in `workload_identities`. For each, the module creates a
  Google service account, grants it exactly the project roles you list
  (e.g. `roles/pubsub.subscriber`, `roles/storage.objectViewer`,
  `roles/cloudsql.client`), and binds it keylessly to one Kubernetes service
  account. Teams annotate their KSA with
  `iam.gke.io/gcp-service-account=<email from outputs>` — no exported keys.

**Resilience & operations**
- Node pools spread evenly across zones (`location_policy = BALANCED`),
  autoscaled (default 1–3 nodes per zone), auto-repair + auto-upgrade.
- Surge upgrades with `max_unavailable = 0` — capacity is added before it is
  removed.
- Release channel `REGULAR` (choose `STABLE` to be more conservative); version
  drift is ignored so GKE-managed upgrades don't fight OpenTofu.
- Daily maintenance window (default 03:00 UTC) plus optional named freeze
  windows (`maintenance_exclusions`, blocks minor upgrades only).
- Cloud Logging (system + workload logs), Cloud Monitoring and Managed
  Prometheus.
- Optional daily Backup for GKE plan (`enable_backup = true`).
- `extra_node_pools` for specialised capacity (bigger machines, taints for
  dedicated/isolated teams, spot batch pools) with the same hardened defaults.

## Minimal usage

```hcl
project_id   = "my-project"
environment  = "prod"            # or "staging"
region       = "us-central1"
cluster_name = "prod-shared-1"

master_authorized_networks = [
  { cidr_block = "198.51.100.0/24", display_name = "platform-vpn" },
]
```

Run: `tofu plan -var-file=minimal.tfvars` (see `minimal.tfvars`).
A fuller production example is in `example-prod.tfvars`.

After apply, engineers connect with the `get_credentials_command` output.

## Prerequisites

- The subnet `apps-<environment>-gke-<region>` (with `pods`/`services`
  secondary ranges) exists in `project_id` — owned by the network team.
- APIs enabled on the project: `container.googleapis.com`, `iam.googleapis.com`,
  `compute.googleapis.com` (plus `gkebackup.googleapis.com` if backups,
  `cloudkms.googleapis.com` if CMEK, `binaryauthorization.googleapis.com` if
  Binary Authorization are enabled).
- If nodes need internet egress (image pulls from outside Google, etc.), the
  network team provides Cloud NAT on the GKE subnet — nodes are private.
- `master_ipv4_cidr_block` (default `172.16.0.0/28`) must not overlap existing
  ranges; override per cluster if needed.

## Inputs the platform team usually touches

| Variable | Purpose | Default |
|---|---|---|
| `project_id`, `environment`, `region`, `cluster_name` | placement (required) | — |
| `master_authorized_networks` | who can reach the API server (required) | — |
| `primary_node_pool` | machine type / autoscale bounds / disks | e2-standard-4, 1–3 per zone, 100 GB pd-balanced |
| `extra_node_pools` | specialised pools | none |
| `workload_identities` | GSA + roles + KSA bindings for GCP access | none |
| `release_channel` | upgrade cadence | REGULAR |
| `enable_private_endpoint` | fully private control plane | false |
| `maintenance_start_time`, `maintenance_exclusions` | ops windows | 03:00 UTC, none |
| `enable_backup`, `database_encryption`, `binary_authorization_evaluation_mode` | optional DR / hardening | off |
| `deletion_protection` | destroy guard | true |
