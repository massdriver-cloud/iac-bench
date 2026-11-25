# GKE Standard Production Cluster Module

Reusable OpenTofu root module for provisioning and operating resilient, multi-tenant **GKE Standard** regional clusters in Google Cloud.

## Key Design Decisions

- **Regional GKE Standard Architecture**: Deploys a 3-zone regional control plane (`location = var.region`), removes GKE's immutable default node pool, and manages worker pools via `google_container_node_pool` with `SURGE` upgrades (`max_surge = 1`, `max_unavailable = 0`), auto-repair, auto-upgrade, and `BALANCED` multi-zone Cluster Autoscaler placement.
- **Zero-Boilerplate Network Wiring**: Automatically binds to the network team's pre-provisioned VPC (`apps-<environment>`) and regional GKE subnet (`apps-<environment>-gke-<region>`) using VPC-native alias IP ranges `pods` and `services`. Caps `default_max_pods_per_node` at `64` (`/25` per node instead of `/24`) to preserve shared Pod CIDR capacity.
- **Multi-Team Network Isolation & Ingress**: Enables **GKE Dataplane V2** (`ADVANCED_DATAPATH`) with eBPF/Cilium `NetworkPolicy`, `CiliumClusterwideNetworkPolicy` for platform guardrails, Hubble network observability, NodeLocal DNSCache, and the managed **GKE Gateway API** (`CHANNEL_STANDARD`).
- **Private & Hardened Control Plane / Nodes**: Worker nodes run `COS_CONTAINERD` with private IPs only (`enable_private_nodes = true`), Shielded GKE Nodes (Secure Boot + Integrity Monitoring), legacy metadata/ABAC/client certs disabled, limited anonymous API auth, per-node `pod_pids_limit` protection against noisy neighbors, dedicated least-privilege node IAM service account, GKE Security Posture & workload vulnerability scanning, and `deletion_protection = true` by default.
- **Workload Access to Pub/Sub, Cloud Storage & Cloud SQL**: Enables **Workload Identity Federation for GKE** (`<project_id>.svc.id.goog`) with `GKE_METADATA` enforced on all nodes, Cloud Storage FUSE CSI driver, Persistent Disk CSI driver, Secret Manager add-on, and optional `workload_identities` to provision and bind per-team Google Cloud service accounts directly.
- **Predictable Day-2 Operations**: Enrolls clusters in the `REGULAR` release channel with off-peak US overnight maintenance windows (Tue–Thu 05:00–10:00 UTC), configurable `maintenance_exclusions` for peak events, GKE Cost Allocation by namespace/label, VPA, and Managed Service for Prometheus.

## Minimal Usage

```hcl
# minimal.tfvars
project_id   = "acme-platform-prod"
cluster_name = "shared-us-central1"
environment  = "prod"
region       = "us-central1"
```

```bash
tofu init
tofu plan -var-file="minimal.tfvars"
```

## Accessing Google Cloud Services (Pub/Sub, Cloud Storage, Cloud SQL)

Product team workloads authenticate via **Workload Identity** without JSON keys:

1. Declare a binding in `workload_identities` (or bind an externally managed GCP Service Account to `serviceAccount:<project_id>.svc.id.goog[<namespace>/<k8s_sa>]` with `roles/iam.workloadIdentityUser`).
2. Annotate the Kubernetes `ServiceAccount` with `iam.gke.io/gcp-service-account: <gsa-email>` (emitted in output `workload_identity_service_accounts`).
3. Pods running under that `ServiceAccount` connect directly to Pub/Sub, Cloud Storage (SDK or GCS FUSE CSI volume), and Cloud SQL (Private IP over the shared `apps-<environment>` VPC using Cloud SQL Auth Proxy with `--auto-iam-authn` / Workload Identity).
