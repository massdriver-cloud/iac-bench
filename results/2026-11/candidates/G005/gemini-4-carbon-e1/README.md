# Production GKE Standard OpenTofu Module

Reusable OpenTofu root module for provisioning and operating shared, multi-team **GKE Standard** production and staging clusters on Google Cloud.

## Key Design Decisions

- **Regional High Availability (GKE Standard)**: Creates a regional control plane (`location = var.region`) replicated across three availability zones, paired with separately managed `google_container_node_pool` resources (`remove_default_node_pool = true`) using balanced multi-zone autoscaling (`location_policy = "BALANCED"`) and zero-unavailable surge upgrades (`max_surge = 1, max_unavailable = 0`).
- **System Add-on Isolation**: Provisions a dedicated `system` node pool tainted with `components.gke.io/gke-managed-components=true:NoSchedule` alongside workload node pools (`var.node_pools`), ensuring product team pods cannot starve cluster-critical components (`kube-dns`, `metrics-server`, `konnectivity`, `gke-metadata-server`, Cilium).
- **Network Team VPC Convention Built-In**: Derives the shared environment VPC (`apps-staging` or `apps-prod`), regional subnet (`<vpc>-gke-<region>`), and IP alias secondary ranges (`pods` and `services`) directly from `environment` and `region`.
- **Private & Multi-Tenant Hardened**:
  - Private worker nodes (`enable_private_nodes = true`) using Private Service Connect by default (no `/28` VPC peering CIDR exhaustion across clusters in the same VPC), optional `enable_private_endpoint`, and Control Plane Authorized Networks enabled by default (`gcp_public_cidrs_access_enabled = false`).
  - **Dataplane V2** (`ADVANCED_DATAPATH`) with `CiliumClusterwideNetworkPolicy` CRDs and Hubble observability so the platform team can enforce namespace isolation across product teams.
  - Dedicated least-privilege node Google Service Account (`roles/container.defaultNodeServiceAccount` + `roles/artifactregistry.reader`), Shielded GKE Nodes with Secure Boot, `COS_CONTAINERD`, legacy metadata & client certificates disabled, `LIMITED` anonymous API auth, Security Posture + container vulnerability scanning (`BASIC`), and `deletion_protection = true`.
- **First-Class Access to Pub/Sub, Cloud Storage & Cloud SQL**:
  - **Workload Identity Federation for GKE** (`<project_id>.svc.id.goog` + `GKE_METADATA` on every node pool) eliminates static service account keys and broad VM scopes.
  - Optional `var.workload_identities` provisions dedicated Google Service Accounts (or binds existing ones), assigns project IAM roles (e.g., `roles/cloudsql.client`, `roles/cloudsql.instanceUser`, `roles/pubsub.subscriber`), binds `roles/iam.workloadIdentityUser` to `namespace/ksa_name`, and outputs the exact `iam.gke.io/gcp-service-account` Kubernetes ServiceAccount annotation.
  - Enables **Cloud Storage FUSE CSI driver**, **Secret Manager CSI add-on**, **NodeLocal DNSCache**, and **VPC-native Pod IPs** for direct private routing to Cloud SQL Private IP / PSC endpoints.
- **Shared-Cluster Operations & Cost Attribution**: Regular release channel with US weekend late-night maintenance windows (16h/week, satisfying GKE's >= 48h/32d requirement), change-freeze `maintenance_exclusions`, GKE Cost Allocation per namespace/label, Cloud Logging (system, workload, and control plane audit/component logs), and Managed Service for Prometheus.

## Minimal Usage

```hcl
project_id  = "acme-apps-prod"
name        = "prod-us-central1-01"
environment = "prod"
region      = "us-central1"
```

## Example: Multi-Pool Cluster with Workload Identity (Cloud SQL, Pub/Sub, GCS)

```hcl
project_id  = "acme-apps-prod"
name        = "prod-us-east4-01"
environment = "prod"
region      = "us-east4"

authorized_networks = [
  {
    cidr_block   = "10.10.0.0/16"
    display_name = "corp-vpn"
  },
]

node_pools = {
  general = {
    machine_type       = "n2-standard-4"
    min_nodes_per_zone = 2
    max_nodes_per_zone = 12
    disk_size_gb       = 100
  }
  batch-spot = {
    machine_type       = "e2-standard-8"
    min_nodes_per_zone = 0
    max_nodes_per_zone = 20
    spot               = true
    labels             = { "workload-tier" = "batch" }
    taints = [
      {
        key    = "workload-tier"
        value  = "batch"
        effect = "NO_SCHEDULE"
      },
    ]
  }
}

workload_identities = {
  orders-service = {
    namespace = "orders"
    ksa_name  = "orders-api"
    project_roles = [
      "roles/cloudsql.client",
      "roles/cloudsql.instanceUser",
      "roles/pubsub.publisher",
    ]
  }
}
```
