# GKE Standard production cluster module

One OpenTofu module that every new production GKE Standard cluster is built
from. The platform team fills in the handful of values that differ per
cluster; the module owns every other design decision.

## Usage

The module is consumed directly as a root module: clone it, then plan and
apply with a tfvars file per cluster.

```hcl
# apps-prod-us-central1.tfvars
project_id   = "my-gcp-project"
region       = "us-central1"
cluster_name = "orders-prod-us-central1"
network      = "apps-prod"

# Allocate one control-plane /28 per cluster in the VPC (the default
# 172.16.0.0/28 can only be used by ONE cluster per VPC).
master_ipv4_cidr = "172.16.4.16/28"

master_authorized_networks = [
  { cidr_block = "203.0.113.0/24", display_name = "office-egress" },
]

node_pools = {
  primary = {
    machine_type = "e2-standard-4"
    min_count    = 1   # per zone -> 3 nodes minimum across the region
    max_count    = 6   # per zone
  }
}
```

```sh
tofu plan  -var-file=apps-prod-us-central1.tfvars
tofu apply -var-file=apps-prod-us-central1.tfvars
```

`minimal.tfvars` shows the smallest valid instantiation (only the four
required variables).

## What the platform team provides

| Variable | Meaning |
|---|---|
| `project_id` | Project that owns the cluster (same project as the VPC). |
| `region` | US region for the regional cluster. |
| `cluster_name` | Unique cluster name. |
| `network` | Environment VPC, e.g. `apps-staging` / `apps-prod`. |

Everything else has a production-ready default and can be overridden per
cluster — see `variables.tf`; every variable is documented.

## Design decisions the module makes

**Resilience**

- *Regional cluster*: the control plane is replicated across zones of the
  region and node pools span those zones by default (`node_locations`).
- *Autoscaling node pools*: cluster autoscaler keeps each pool between
  `min_count`/`max_count` per zone, balanced across zones.
- *Surge upgrades*: nodes upgrade one surge node at a time with zero
  unavailable nodes, so capacity stays up during upgrades.
- *Auto-repair and auto-upgrade* on every pool.
- *Backup for GKE agent* installed, ready for backup plans.

**Networking** (integrates with the network team's setup)

- VPC-native cluster on the existing subnetwork `<vpc>-gke-<region>` with
  secondary ranges `pods` and `services` (names overridable).
- *Private nodes* by default (no public IPs on nodes). The control-plane
  endpoint stays public but can be restricted with
  `master_authorized_networks`, or made fully private with
  `enable_private_endpoint = true`.
- *Dataplane V2* (eBPF): network policies are enforced natively, with flow
  visibility — no Calico add-on to operate.
- *Gateway API* (standard channel) enabled as the multi-team-friendly
  successor to Ingress; HTTP(S) load balancing add-on stays on.

**Security**

- *Workload Identity Federation for GKE* — workloads reach Pub/Sub, Cloud
  Storage, Cloud SQL, etc. through Kubernetes service accounts, never via
  node credentials. The Cloud Storage FUSE CSI driver is enabled for
  bucket-backed volumes.
- Dedicated *least-privilege node service account* per cluster (log writer,
  metric writer, monitoring viewer, resource metadata writer, Artifact
  Registry reader — override with `node_service_account_roles`).
- Shielded nodes with secure boot and integrity monitoring; legacy metadata
  endpoints disabled; no legacy client certificates.
- Service `externalIPs` blocked (`service_external_ips_config`).
- GKE security posture dashboard and basic vulnerability scanning on.
- Optional: application-layer Secrets encryption with a caller-provided KMS
  key (`database_encryption_key` — the module wires the IAM grant), Binary
  Authorization enforcement (`enable_binary_authorization`), and Google
  Groups for RBAC (`rbac_security_group`).
- *Deletion protection* on by default — set `deletion_protection = false`
  before destroying a cluster.

**Operations**

- Release channel `REGULAR` with a daily maintenance window (03:00 UTC
  default) so upgrades are predictable.
- Cloud Logging for system components and workloads; Cloud Monitoring for
  system components plus *Managed Service for Prometheus*.
- *Cost allocation* enabled — usage/cost per namespace and label in Cloud
  Billing, which matters because each cluster is shared by several product
  teams.
- Optional Pub/Sub topic with cluster upgrade and security-bulletin events
  (`enable_upgrade_notifications`) for alerting and automation.

## Prerequisites (owned outside this module)

1. `container.googleapis.com` enabled in the project (plus
   `pubsub.googleapis.com` if `enable_upgrade_notifications = true`).
2. The network team's subnetwork `<vpc>-gke-<region>` exists with `pods` and
   `services` secondary ranges. With private nodes (the default) it needs
   Private Google Access or a NAT path so nodes can reach Google APIs and
   pull images.
3. A distinct `master_ipv4_cidr` /28 allocated per cluster in the VPC.

## For product teams: using Google Cloud services from workloads

The cluster has Workload Identity enabled. To let a workload use e.g.
Pub/Sub, a team creates an IAM service account, grants it the Pub/Sub role,
binds it to their Kubernetes service account, and annotates the KSA:

```sh
gcloud iam service-accounts add-iam-policy-binding APP_SA@PROJECT.iam.gserviceaccount.com \
  --role roles/iam.workloadIdentityUser \
  --member "serviceAccount:PROJECT.svc.id.goog[NAMESPACE/KSA_NAME]"
kubectl annotate serviceaccount KSA_NAME -n NAMESPACE \
  iam.gke.io/gcp-service-account=APP_SA@PROJECT.iam.gserviceaccount.com
```

Pods using that KSA then call Google Cloud APIs with the app identity. The
exact pool is in the `workload_identity_pool` output.

## Outputs

Cluster name/id/location, control-plane endpoint, CA certificate (sensitive),
master version, workload identity pool, node service account, network and
subnetwork used, node pool IDs, upgrade-notifications topic, and a ready-made
`gcloud ... get-credentials` command.
