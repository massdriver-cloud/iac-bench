# gke-standard

The platform team's standard module for production GKE **Standard** clusters.
Every new cluster comes from this module. Platform engineers fill in the four
cluster-specific inputs (`project_id`, `name`, `region`, `network`); the module
owns every other design decision.

## What you get

**Resilience**
- Regional cluster: three control-plane replicas across zones; node pools span
  every zone of the region by default.
- Autoscaling node pools with surge upgrades (`max_surge=1, max_unavailable=0`)
  so capacity is preserved during upgrades.
- Node auto-repair and auto-upgrade; `REGULAR` release channel; daily
  02:00–06:00 UTC maintenance window with support for exclusions.
- `deletion_protection` on by default.

**Security**
- VPC-native cluster on the network team's existing subnet
  (`<vpc>-gke-<region>` with secondary ranges `pods` and `services`).
- Private nodes (no public IPs on workers); control-plane endpoint is public
  but authenticated by default, and can be restricted with
  `master_authorized_networks` or made fully private (`enable_private_endpoint`).
- **Workload Identity** is always on — this is how workloads reach Pub/Sub,
  Cloud Storage, Cloud SQL, etc. without exported keys. Use
  `workload_service_accounts` to provision per-team Google service accounts and
  their Kubernetes service account bindings.
- Dedicated least-privilege node service account (telemetry + image pulls only)
  — never the default compute service account.
- Shielded nodes with secure boot and integrity monitoring; GKE metadata server
  on every pool; legacy metadata endpoints disabled.
- Dataplane V2 (Cilium): network policy enforcement built into the dataplane,
  no Calico addon.
- Optional application-layer secrets encryption (Cloud KMS), Binary
  Authorization, and Google Groups-based RBAC.

**Operations**
- Cloud Logging (system + workloads) and Cloud Monitoring (system) wired up;
  Managed Service for Prometheus enabled.
- Per-namespace cost metering for a shared, multi-team cluster.
- Optional Pub/Sub upgrade notifications.
- Node pools managed as separate resources — add/remove pools without
  recreating the cluster.

## Prerequisites

- The network team's VPC and subnet already exist in the project:
  subnet `<network>-gke-<region>` with secondary ranges named `pods` and
  `services` (names overridable).
- APIs enabled in the project: `container.googleapis.com`,
  `compute.googleapis.com`, `iam.googleapis.com`.
- Nodes are private: to pull images from outside Google Cloud, the subnet
  needs a Cloud NAT (or Private Google Access plus Artifact Registry).

## Usage

```hcl
# minimal.tfvars — the smallest valid cluster
project_id = "apps-prod-123456"
name       = "prod-us-central1"
region     = "us-central1"
network    = "apps-prod"
```

A cluster with team-dedicated capacity and a workload identity:

```hcl
project_id = "apps-prod-123456"
name       = "prod-us-central1"
region     = "us-central1"
network    = "apps-prod"

node_pools = {
  general = {} # all module defaults
  batch = {
    machine_type = "e2-standard-8"
    spot         = true
    max_count    = 20
    labels       = { workload = "batch" }
    taints       = [{ key = "workload", value = "batch", effect = "NO_SCHEDULE" }]
  }
}

workload_service_accounts = {
  orders-publisher = {
    namespace     = "orders"
    project_roles = ["roles/pubsub.publisher"]
  }
}
```

## Design decisions the module owns

Regional vs zonal, VPC-native IP allocation, private nodes, Workload Identity,
Dataplane V2, node service account and its roles, shielded nodes, node pool
management strategy, release channel, maintenance window, logging/monitoring
wiring, cost metering, deletion protection. Override variables exist for the
rest; prefer changing the module over overriding per cluster, so the fleet
stays uniform.
