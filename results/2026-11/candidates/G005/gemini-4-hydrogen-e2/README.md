# Production GKE Standard Root Module

Reusable OpenTofu root module for provisioning resilient, secure, multi-team **GKE Standard** regional clusters in Google Cloud.

## Design Decisions

- **Regional High Availability**: Control plane and node pools span zones in a US region (`us-*`) with `REGULAR` release channel, weekend off-peak maintenance windows, and `SURGE` node upgrades (`max_surge = 1`, `max_unavailable = 0`).
- **Pre-provisioned Network Integration**: Attaches to the network team's environment VPC (`apps-staging` or `apps-prod`) and pre-created regional subnet (`<vpc>-gke-<region>`) using the `pods` and `services` secondary ranges.
- **Private & Hardened Nodes**: Nodes have no public IPs (`enable_private_nodes = true`), run `COS_CONTAINERD` with `gVNIC`, Shielded GKE Nodes (Secure Boot + Integrity Monitoring), legacy metadata endpoints disabled, and `deletion_protection = true`.
- **Workload Identity & Least-Privilege IAM**:
  - Dedicated per-cluster node service account with only logging, monitoring, and Artifact Registry reader permissions.
  - Workload Identity Federation (`<project_id>.svc.id.goog`) + `GKE_METADATA` enabled so product-team pods authenticate to **Pub/Sub**, **Cloud Storage**, and **Cloud SQL** using per-namespace/per-service-account IAM bindings rather than node credentials.
- **Multi-Team Shared Cluster Tooling**:
  - **Dataplane V2** (`ADVANCED_DATAPATH`) for eBPF networking and native Kubernetes `NetworkPolicy` enforcement.
  - **Cloud DNS for GKE** (`CLUSTER_SCOPE`) to avoid `kube-dns` scaling bottlenecks.
  - **GKE Cost Allocation** enabled for namespace/label cost attribution.
  - **Gateway API** (`CHANNEL_STANDARD`), **Vertical Pod Autoscaling**, **Managed Service for Prometheus**, **GCS FUSE CSI driver**, **Secret Manager add-on**, and **Backup for GKE** agent enabled out of the box.
  - Scoped ingress firewall rule from `master_ipv4_cidr_block` to cluster nodes for Kubernetes admission webhooks (`6443`, `8443`, `9443`).
- **Separated Node Pools**: Default node pool is removed; by default the module manages a tainted `system` pool (`CriticalAddonsOnly=true:NoSchedule`) for cluster add-ons and an autoscaling `general` pool for product workloads.

## Usage

Supply cluster-specific values in a `.tfvars` file (see `minimal.tfvars` for the smallest valid example):

```hcl
project_id             = "my-apps-prod-project"
cluster_name           = "apps-us-central1-01"
environment            = "prod"
region                 = "us-central1"
master_ipv4_cidr_block = "172.16.0.0/28" # Must be unique per cluster in the VPC
```

### Connecting Product Workloads to Pub/Sub, Cloud Storage, and Cloud SQL

With Workload Identity enabled (`output.workload_identity_pool`), grant IAM roles directly to a Kubernetes ServiceAccount (`<namespace>/<ksa>`) without exporting keys:

```hcl
resource "google_pubsub_topic_iam_member" "team_publisher" {
  topic  = google_pubsub_topic.events.name
  role   = "roles/pubsub.publisher"
  member = "principal://iam.googleapis.com/projects/${var.project_number}/locations/global/workloadIdentityPools/${module_or_output.workload_identity_pool}/subject/ns/team-a/sa/orders-api"
}
```
