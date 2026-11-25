# GKE Standard cluster - platform standard

One module, one production-grade GKE Standard cluster. Fill in three values;
the module decides the rest.

```hcl
name        = "apps-prod-use4"
environment = "prod"       # staging | prod  -> VPC apps-staging | apps-prod
region      = "us-east4"   # -> subnet apps-prod-gke-us-east4
```

```sh
tofu init
tofu apply -var-file=my-cluster.tfvars
$(tofu output -raw get_credentials_command)
```

Use one state (workspace / backend key) per cluster. `examples/full.tfvars`
shows every optional setting.

## What you get

| Area | Decision |
|---|---|
| Availability | Regional cluster: control plane and every node pool spread across the region's zones. Node pools autoscale, auto-repair, and upgrade by surge so capacity never drops. |
| Network | VPC-native on the network team's `apps-<env>-gke-<region>` subnet, pods and services on its `pods` / `services` secondary ranges. Dataplane V2, so Kubernetes `NetworkPolicy` is enforced. |
| Exposure | Nodes have no public IPs. The control plane has no public IP endpoint. |
| Access to the API server | Through the cluster's DNS endpoint, authenticated and authorised by Cloud IAM - works from laptops and CI without a VPN or IP allowlist. The private IP endpoint is additionally open to `control_plane_authorized_networks`, if you set any. |
| Workload access to Google Cloud | Workload Identity Federation for GKE. Pods authenticate to Pub/Sub, Cloud Storage, Cloud SQL etc. as their Kubernetes service account - no key files. |
| Node identity | A dedicated service account per cluster with only logging/monitoring and Artifact Registry read. Shielded nodes with Secure Boot, Container-Optimized OS, legacy metadata endpoints off. |
| Authentication | No client certificates, no basic auth, no legacy ABAC. Optional Google Groups for RBAC. |
| Upgrades | Release channel: `REGULAR` in staging, `STABLE` in prod, so staging sees each version first. Maintenance only Tue-Thu 06:00-12:00 UTC unless you change it. |
| Observability | System, workload and control-plane logs to Cloud Logging; system and kube-state metrics plus Managed Service for Prometheus; GKE cost allocation by namespace/label. |
| Add-ons | HTTP load balancing, Gateway API, HPA, VPA, PD CSI driver, Cloud Storage FUSE CSI driver, NodeLocal DNSCache. |
| Safety | Deletion protection on. |

## Things the module relies on (not created here)

- The VPC `apps-<environment>` and subnet `apps-<environment>-gke-<region>` with
  secondary ranges `pods` and `services`, in the same project as the cluster.
- **Outbound internet for nodes**: nodes are private, so pulling images from
  registries outside Google (Docker Hub, GHCR, ...) or calling external APIs
  needs Cloud NAT on the VPC in that region - ask the network team. Google
  APIs and Artifact Registry work without it (Private Google Access).
- The Kubernetes Engine API (`container.googleapis.com`) enabled in the project.
- `name` unique within the project.

## Giving a workload access to a Google Cloud service

Grant the IAM role directly to the Kubernetes service account:

```
principal://iam.googleapis.com/projects/<PROJECT_NUMBER>/locations/global/workloadIdentityPools/<workload_identity_pool output>/subject/ns/<NAMESPACE>/sa/<KSA_NAME>
```

Never grant application roles to the node service account.

## Sizing node pools

Counts are **per zone**. The default pool is `e2-standard-4`, 1-5 nodes per
zone, i.e. 3-15 nodes in a three-zone region. The pods range of the subnet
caps the total: each node reserves a /24 from it.

## Retiring a cluster

Apply with `deletion_protection = false`, then `tofu destroy`.
