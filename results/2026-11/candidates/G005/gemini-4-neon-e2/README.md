# GKE Standard Production Cluster Module

Reusable OpenTofu root module for creating and operating resilient, secure, multi-team **GKE Standard** clusters on Google Cloud.

Designed for platform engineers who know Kubernetes well without needing to manage GKE-specific networking, IAM, or hardening details for every cluster.

## Quick Start

Create a `.tfvars` file specifying only what is unique to the cluster:

```hcl
project_id   = "my-gcp-project"
cluster_name = "core-us-central1"
environment  = "prod"        # "staging" or "prod" -> selects apps-<env> VPC
region       = "us-central1" # US region -> selects apps-<env>-gke-<region> subnet
```

```bash
tofu init
tofu plan -var-file=cluster.tfvars
tofu apply -var-file=cluster.tfvars
```

## What the Module Configures Automatically

### Networking & Multi-Team Isolation
- **Network team integration**: Looks up VPC `apps-<environment>` and subnet `apps-<environment>-gke-<region>` with secondary ranges `pods` and `services`, and verifies subnet prerequisites (secondary ranges + Private Google Access) at plan time.
- **VPC-native + Dataplane V2 (`ADVANCED_DATAPATH`)**: eBPF-based networking with native Kubernetes `NetworkPolicy` and `CiliumClusterwideNetworkPolicy` enforcement, intra-node visibility for VPC Flow Logs, and L4 ILB subsetting.
- **Private nodes + Private Service Connect control plane**: Worker nodes have no public IP addresses. Control plane networking defaults to Private Service Connect (no `/28` peering CIDR allocation needed across clusters in the same VPC), with global private endpoint access enabled across US regions.
- **Fail-closed API access**: `master_authorized_networks_config` blocks public internet access by default (`authorized_networks = []`, `gcp_public_cidrs_access_enabled = false`). Add VPN/CI CIDRs to `authorized_networks`, enable `enable_dns_endpoint_external_traffic = true` for IAM-authenticated DNS access, or set `enable_private_endpoint = true` to remove the public IP endpoint entirely.
- **Pod IP efficiency**: Defaults to `64` pods per node (`/25` per node), doubling node capacity across clusters sharing the subnet's `/17` `pods` range compared to GKE's default of `110` (`/24`).

### Resilience & Lifecycle Operations
- **Regional HA control plane & multi-zone node pools**: Spans all zones in `var.region` with `BALANCED` autoscaling distribution (and `ANY` zone placement for optional Spot pools).
- **Separated system & workload node pools**:
  - `system` pool (`e2-standard-2`, 1–3/zone) tainted with `components.gke.io/gke-managed-components=true:NoSchedule` isolates `kube-dns` and GKE system agents from noisy product workloads.
  - `general` workload pool (`e2-standard-4`, 1–5/zone) runs product team workloads out of the box; add additional pools via `workload_node_pools`.
- **Zero-downtime upgrades & node pool replacement**: Surge upgrades (`max_surge = 1`, `max_unavailable = 0`), auto-repair, auto-upgrade, `create_before_destroy` on node pools, `REGULAR` release channel, and weekend off-peak maintenance windows (`SA,SU 02:00–10:00 UTC`).
- **Deletion protection**: Enabled by default for `prod`, disabled by default for `staging` (explicitly overridable via `deletion_protection`).

### Security & Governance
- **Dedicated least-privilege node service account**: Never uses the Compute Engine default SA. Grants only `roles/container.defaultNodeServiceAccount` and `roles/artifactregistry.reader` (intentionally omits `roles/storage.objectViewer` so nodes cannot read product data buckets).
- **Workload Identity Federation**: Enabled at the cluster (`<project_id>.svc.id.goog`) and enforced on every node via `GKE_METADATA` so pods cannot steal node credentials.
- **Hardened nodes & API**: `COS_CONTAINERD`, Shielded GKE Nodes with Secure Boot & Integrity Monitoring, legacy metadata endpoints disabled, legacy ABAC disabled, static client certs disabled, limited anonymous authentication, insecure `system:authenticated`/`system:unauthenticated` RBAC bindings blocked, `Service.spec.externalIPs` disabled (CVE-2020-8554 mitigation), and GKE Security Posture (`BASIC` + `VULNERABILITY_BASIC`).
- **Optional enterprise controls**: Google Groups RBAC (`security_group`), customer-managed KMS etcd encryption (`database_encryption_kms_key_id`), Binary Authorization (`binary_authorization_mode`), Secret Manager CSI add-on (`enable_secret_manager_addon`), and per-pool gVisor sandboxing (`enable_gvisor = true`).

### Observability, Add-ons & Cost Visibility
- Cloud Logging (`SYSTEM_COMPONENTS`, `WORKLOADS`), Cloud Monitoring, and Google Cloud Managed Service for Prometheus (GMP).
- GKE Cost Allocation (`cost_management_config`) for per-namespace/label cost attribution across product teams.
- NodeLocal DNSCache, Vertical Pod Autoscaler, Kubernetes Gateway API (`CHANNEL_STANDARD`), GCE Persistent Disk CSI, and Cloud Storage FUSE CSI driver.

## Connecting Workloads to Pub/Sub, Cloud Storage, and Cloud SQL

Workloads must authenticate via **Workload Identity Federation** rather than static service account keys:

- **Pub/Sub & Cloud Storage (direct Workload Identity Federation)**: Grant the target IAM role directly on the topic/subscription or bucket to:
  ```
  <workload_identity_principal_prefix>/subject/ns/<namespace>/sa/<ksa-name>
  ```
- **Cloud Storage as a volume**: Enabled via the Cloud Storage FUSE CSI driver (`enable_gcs_fuse_csi_driver = true`).
- **Cloud SQL**: Run the Cloud SQL Auth Proxy sidecar (connecting over private IP or IAM auth) with a dedicated per-service GCP Service Account bound via `roles/iam.workloadIdentityUser` to `serviceAccount:<project_id>.svc.id.goog[<namespace>/<ksa-name>]` and annotated with `iam.gke.io/gcp-service-account`.

## Example: Production Cluster Customization

```hcl
project_id   = "my-gcp-project"
cluster_name = "apps-prod-us-east1"
environment  = "prod"
region       = "us-east1"

authorized_networks = [
  { cidr_block = "203.0.113.0/24", display_name = "corporate-vpn" }
]

security_group                = "gke-security-groups@example.com"
artifact_registry_project_ids = ["shared-cicd-artifacts"]

workload_node_pools = {
  general = {
    machine_type       = "n2-standard-4"
    min_count_per_zone = 2
    max_count_per_zone = 10
  }
  highmem = {
    machine_type       = "n2-highmem-8"
    min_count_per_zone = 0
    max_count_per_zone = 6
    labels             = { "workload-class" = "highmem" }
    taints = [{
      key    = "workload-class"
      value  = "highmem"
      effect = "NO_SCHEDULE"
    }]
  }
  batch-spot = {
    machine_type       = "e2-standard-8"
    min_count_per_zone = 0
    max_count_per_zone = 10
    spot               = true
  }
}
```
