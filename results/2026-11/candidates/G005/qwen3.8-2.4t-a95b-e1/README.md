# GKE Standard platform module

The one module every new production GKE cluster comes from. It encodes the
platform team's design decisions so product teams' clusters are consistent,
resilient, and secure without anyone on the platform team needing to be a GKE
specialist.

## What you fill in, what the module decides

Required inputs — the cluster-specific bits:

| Variable       | Example                   | Meaning                                        |
| -------------- | ------------------------- | ---------------------------------------------- |
| `project_id`   | `prj-platform-example`    | Project owning the cluster *and* the env VPC   |
| `cluster_name` | `apps-prod-us-central1`   | Cluster name                                   |
| `region`       | `us-central1`             | One of our US regions with a GKE subnet        |
| `network`      | `apps-prod`               | Environment VPC owned by the network team      |

Everything else has a platform default. The subnet is derived from the network
team's convention as `<network>-gke-<region>`, using the `pods` and
`services` secondary ranges.

Minimal instantiation (see `minimal.tfvars`):

```hcl
module "cluster" {
  source       = "./" # this module
  project_id   = "prj-platform-example"
  cluster_name = "apps-prod-us-central1"
  region       = "us-central1"
  network      = "apps-prod"
}
```

## Design decisions the module owns

### Resilience
- **Regional cluster, regional node pools.** The control plane and every node
  pool span all zones in the region; `location_policy = "BALANCED"` keeps
  nodes evenly spread so the cluster survives a zone failure.
- **Auto-repair and auto-upgrade** on all node pools; versions track the
  `REGULAR` release channel (override with `kubernetes_version` /
  `release_channel` if you must pin).
- **Surge upgrades** (`max_surge = 1`, `max_unavailable = 0`): upgrades add
  nodes first, they never remove capacity first.
- **Cluster autoscaler** per pool with sane defaults (1–10 nodes per zone),
  tunable per pool.
- **Weekend maintenance window** (Sat/Sun 04:00–08:00 UTC) so upgrades land
  outside business hours.
- **`deletion_protection = true`** by default; flip only to decommission.

### Security
- **Private cluster**: nodes have no public IPs and the control plane endpoint
  is private-only by default (`enable_private_endpoint = true`). Operate it
  with GKE Connect Gateway / a bastion inside the VPC. If you must expose the
  endpoint publicly, the module enforces (via a precondition) that you also
  supply `master_authorized_networks`.
- **Dataplane V2** (`datapath_provider = "ADVANCED_DATAPATH"`): eBPF datapath
  with built-in NetworkPolicy enforcement.
- **Shielded nodes** plus secure boot and integrity monitoring on every node.
- **Workload Identity** enabled. Workloads reach Pub/Sub, Cloud Storage,
  Cloud SQL, etc. through their own Google service accounts — never through
  node credentials. See the `workload_identity_pool` output and the example
  below.
- **Module-managed node service account** with only the roles GKE needs to
  operate (logging, monitoring, image pull). Never the Compute default SA.
  Legacy metadata endpoints are disabled.
- Optional **CMEK envelope encryption** for Kubernetes secrets via
  `secrets_kms_key`.
- The control plane master `/28` is **auto-selected by GKE by default**, so
  multiple clusters in one VPC never collide.

### Operability
- Cloud Logging (system + workload components) and Cloud Monitoring with
  **Managed Service for Prometheus**.
- **GKE cost management** enabled for chargeback across product teams.
- **L4 ILB subsetting** so teams can create internal load balancers without
  extra wiring; HTTP load balancing and HPA addons on.
- **NodeLocal DNSCache**, Persistent Disk CSI, and **GCS FUSE CSI** (mount
  Cloud Storage buckets from pods).
- **Cloud Router + Cloud NAT** managed by the module so private nodes can
  pull images; set `enable_cloud_nat = false` if the network team already
  provides egress for the subnet.

### Node pools
One `default` pool by default (on-demand `e2-standard-4`, 100 GB pd-balanced,
1–10 nodes per zone). Add pools for team/workload isolation:

```hcl
node_pools = {
  system = {
    machine_type   = "e2-standard-4"
    min_node_count = 1
    max_node_count = 5
  }
  batch = {
    machine_type   = "c2d-standard-8"
    spot           = true
    min_node_count = 0
    max_node_count = 20
    taints = [{ key = "workload", value = "batch", effect = "NO_SCHEDULE" }]
  }
}
```

## Prerequisites

- The environment VPC and its `<vpc>-gke-<region>` subnet (with `pods` and
  `services` secondary ranges) already exist — owned by the network team.
- APIs enabled in the project: `container.googleapis.com`,
  `compute.googleapis.com`, `iam.googleapis.com`,
  `containerregistry.googleapis.com` / `artifactregistry.googleapis.com`.
- The identity running OpenTofu needs roughly: `roles/container.admin`,
  `roles/compute.networkAdmin` (for the router/NAT),
  `roles/iam.serviceAccountAdmin`, `roles/resourcemanager.projectIamAdmin`.

## Wiring workload access to Pub/Sub / GCS / Cloud SQL

```bash
gcloud iam service-accounts add-iam-policy-binding APP_GSA@PROJECT.iam.gserviceaccount.com \
  --role roles/iam.workloadIdentityUser \
  --member "serviceAccount:PROJECT.svc.id.goog[NAMESPACE/K8S_SERVICE_ACCOUNT]"
```

…then annotate the Kubernetes service account with
`iam.gserviceaccount.com/APP_GSA@PROJECT.iam.gserviceaccount.com`. Use the
module's `workload_identity_pool` output for the pool name.
