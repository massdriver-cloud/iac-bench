# GKE Standard module

The single module every new GKE **Standard** cluster is created from. Clusters
built from it are regional, private, release-channel managed and hardened, and
are meant to be **shared by several product teams** running production
workloads that also use Google services such as Pub/Sub, Cloud Storage and
Cloud SQL.

The platform team supplies the handful of per-cluster facts — project, name,
region, environment, and the networks allowed to reach the Kubernetes API
server — and the module owns every other decision. This README records those
decisions so nobody has to reverse-engineer them.

The module is applied as a root module: the `google` provider is configured in
`providers.tf` from `project_id` and `region`, and credentials come from the
environment (Application Default Credentials).

## Quick start

```sh
tofu init
tofu plan  -var-file minimal.tfvars
tofu apply -var-file minimal.tfvars
```

`minimal.tfvars` in this directory is the smallest valid instantiation:

```hcl
project_id  = "acme-platform"
name        = "shared-usc1"
region      = "us-central1"
environment = "prod"

master_authorized_networks = {
  platform-vpn = "203.0.113.0/24"
}
```

## What the module creates

| Resource | Purpose |
| --- | --- |
| `google_container_cluster` | Regional (multi-zone), private GKE Standard cluster |
| `google_container_node_pool` | One managed, autoscaling pool per entry in `node_pools` |
| `google_service_account` | Dedicated node identity `gke-<name>-nodes` |
| `google_project_iam_member` | Least-privilege roles for that node identity |
| `google_service_account_iam_binding` | Optional Workload Identity bindings (Kubernetes SA -> Google SA) |

The module deliberately creates no Kubernetes objects (namespaces, quotas,
RBAC). Those change faster than infrastructure and belong to the teams, who
apply them with kubectl or their CD tooling — not to a Terraform state that
has to talk to the API server.

## Required inputs

| Variable | Notes |
| --- | --- |
| `project_id` | Same project as the environment's VPC. |
| `name` | Cluster name; also drives the node service account id, so <= 20 chars. |
| `region` | Must be a US region; there is a standard GKE subnet in each. |
| `environment` | `staging` or `prod` today. Selects VPC `apps-<environment>` and subnet `apps-<environment>-gke-<region>`. |
| `master_authorized_networks` | Map of display name -> IPv4 CIDR allowed to reach the API server. Deliberately required: an empty set would leave the endpoint world-reachable. |

## Optional inputs

| Variable | Default | Purpose |
| --- | --- | --- |
| `node_pools` | one `general` pool | Map of node pools; see below. |
| `release_channel` | `REGULAR` | GKE release channel; versions are never pinned. |
| `enable_private_endpoint` | `false` | Drop the public control plane endpoint entirely. |
| `master_ipv4_cidr_block` | `null` | Fixed /28 for the control plane; null auto-allocates. |
| `authenticator_security_group` | `null` | RBAC Google Groups (`gke-security-groups@...`). |
| `database_encryption_kms_key` | `null` | CMEK for Kubernetes Secrets. |
| `enable_network_policy` | `true` | NetworkPolicy enforcement. |
| `enable_gateway_api` | `true` | Gateway API for per-team ingress. |
| `deletion_protection` | `true` | Block accidental `tofu destroy`. |
| `maintenance_window` | Sat 09:00–13:00 UTC | Weekly window, in UTC. |
| `workload_identity_bindings` | `{}` | Kubernetes SA -> Google SA impersonation. |
| `additional_node_service_account_roles` | `[]` | Escape hatch for legacy non-WI workloads. |
| `labels` | `{}` | Extra labels on cluster and node pools. |

## Design decisions the module makes

- **Regional, not zonal.** `location` is the region: the control plane and
  nodes spread over three zones, so a zone loss degrades rather than deletes
  the cluster.
- **Private nodes, restricted endpoint.** Nodes never get public IPs. The
  control plane endpoint is public but limited to `master_authorized_networks`
  (VPN/office/CI); set `enable_private_endpoint = true` to drop the public
  endpoint entirely. Private nodes still reach the control plane privately.
- **Versions come from the release channel.** `REGULAR` by default, no pinned
  versions anywhere. Channels are how GKE delivers tested upgrades; pinned
  versions drift. Node pools use auto-repair/auto-upgrade so they follow the
  channel.
- **VPC-native networking on the network team's ranges.** Pods and Services
  use the subnet's `pods` and `services` secondary ranges — the network team's
  naming convention is encoded here, not retyped per cluster.
- **Dedicated least-privilege node identity.** `gke-<name>-nodes` with only
  log/metric writing and image reading. Workload-level access to Pub/Sub,
  Cloud Storage and Cloud SQL goes through Workload Identity instead, so the
  node identity never grows workload roles.
- **Workload Identity is on.** The pool is `<project>.svc.id.goog`; use
  `workload_identity_bindings` to wire Kubernetes service accounts to Google
  service accounts (see below). No keys, ever.
- **Shielded nodes, secure boot, GKE metadata only.** `enable_shielded_nodes`,
  per-node `shielded_instance_config` and `workload_metadata_config` mode
  `GKE_METADATA` so Pods cannot read the node identity.
- **NetworkPolicy enabled** so product-team namespaces can isolate themselves
  on a shared cluster.
- **Gateway API on** (`gateway_api_config`): each team owns its own Gateway
  instead of annotating one shared LoadBalancer Service.
- **Deletion protection on.** These are shared production clusters; a stray
  `tofu destroy` must fail. Turn `deletion_protection` off explicitly, apply,
  and destroy when decommissioning for real.
- **A weekly maintenance window**, Saturday 09:00–13:00 UTC by default (early
  morning on both US coasts). Node upgrades additionally roll one node at a
  time (`max_surge 1`, `max_unavailable 0`).
- **Logging and Monitoring on**, with the component set GKE recommends for
  Managed Service for Prometheus (per-namespace metrics on shared clusters).

## Node pools

`node_pools` is a map; the key is the pool name and every field has a default,
so a new dedicated pool is a few lines:

```hcl
node_pools = {
  general = {
    machine_type = "c3-standard-8"
    min_count    = 3
    max_count    = 15
  }
  batch-spot = {
    machine_type   = "c3-standard-4"
    spot           = true
    node_locations = ["us-central1-a", "us-central1-b"]
    labels         = { workload = "batch" }
  }
}
```

Counts are **per zone** — `min_count 2` on a regional cluster is 6 nodes. Spot
or preemptible pools are supported (stateless/batch workloads only).

Every pool carries the node label `pool = <pool name>` (plus the cluster
labels), so product teams pin workloads to their pool with a nodeSelector or
node affinity — or with `cloud.google.com/gke-nodepool`, which GKE sets anyway.
Kubernetes taints/tolerations are left to the teams' manifests, which is where
Pod scheduling belongs.

## Workload Identity (Pub/Sub, Cloud Storage, Cloud SQL)

Create the Google service account and its service roles once, then wire the
Kubernetes service account to it from this module:

```hcl
workload_identity_bindings = {
  payments-publisher = {
    google_service_account     = "payments-publisher@acme-platform.iam.gserviceaccount.com"
    namespace                  = "payments"
    kubernetes_service_account = "publisher"
  }
}
```

And annotate the Kubernetes service account (the team's job, not the
module's):

```sh
kubectl annotate serviceaccount publisher -n payments \
  iam.gke.io/gcp-service-account=payments-publisher@acme-platform.iam.gserviceaccount.com
```

Cloud SQL workloads should use the Cloud SQL Auth Proxy or Cloud SQL language
connectors, which authenticate through the same identity — no IP allowlists
or `cloudsql.instances.get` on the node account.

## Prerequisites

Before the first apply, the project and network must be ready:

1. **APIs** in `project_id`:
   `container.googleapis.com`, `iam.googleapis.com`,
   `cloudresourcemanager.googleapis.com` (for project IAM), and
   `artifactregistry.googleapis.com` if you pull from Artifact Registry.
2. **Subnet** `apps-<environment>-gke-<region>` in VPC `apps-<environment>`
   with secondary ranges `pods` and `services`, and
   `private_ip_google_access = true` — private nodes reach Google APIs
   (including the Workload Identity and Pub/Sub/Cloud Storage endpoints)
   through Private Google Access, not through external IPs.
3. **Cloud NAT** on the subnet if workloads pull images from public
   registries or need general internet egress.
4. **Cloud SQL over private IP**: ask the network team for Private Service
   Access (a `google_compute_global_address` of purpose `VPC_PEERING` plus a
   `google_service_networking_connection`) on the environment VPC. It is a
   per-VPC, one-time resource owned by the network team, so it is intentionally
   not created per cluster here.
5. **Google Group** `gke-security-groups@<domain>` if you use
   `authenticator_security_group`.
6. **KMS key** in a key ring in the cluster's region if you use
   `database_encryption_kms_key`.

## Outputs

`cluster_name`, `cluster_id`, `cluster_endpoint`, `cluster_ca_certificate`
(sensitive), `master_version`, `region`, `network`, `subnetwork`,
`workload_identity_pool`, `node_service_account_email`, `node_pool_names`.
