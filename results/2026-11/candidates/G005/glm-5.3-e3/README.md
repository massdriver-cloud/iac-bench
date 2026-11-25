# Standard GKE module — the platform team's cluster factory

Every new Kubernetes cluster comes from here. This module creates and
operates a production GKE **Standard** cluster — shared by several product
teams, resilient and secure by default. Platform engineers fill in what is
genuinely specific to each cluster; the module owns every other GKE design
decision so that all clusters behave identically.

It is applied directly as a root module, once per cluster (one directory, one
state per cluster). Credentials come from the environment; the provider is
configured from the variables below.

## What you decide per cluster

Four inputs, plus your node pools:

| Input | Example | What it is |
|---|---|---|
| `project_id` | `acme-apps-prod` | The project hosting the environment VPC. The cluster always lives in the same project as its VPC. |
| `region` | `us-central1` | A US region where the network team has a GKE subnet. |
| `vpc_name` | `apps-prod` | The environment VPC (`apps-staging` or `apps-prod`). |
| `control_plane_ipv4_cidr` | `172.16.8.0/28` | One unused RFC 1918 /28 per cluster — get each allocation from the network team, they must not overlap between clusters in a VPC. |

With the defaults, the cluster is then named `<vpc>-<region>` (for example
`apps-prod-us-central1`) and attaches to the network team's
`<vpc>-gke-<region>` subnet, using its `pods` and `services` secondary ranges.

## Quick start

Each cluster is one OpenTofu root module instance. Create a directory for the
cluster, write a `cluster.tfvars` (see `minimal.tfvars` in this directory for
the smallest valid one) and apply:

```sh
tofu init
tofu plan  -var-file=cluster.tfvars
tofu apply -var-file=cluster.tfvars
```

A `cluster.tfvars` for a typical production cluster:

```hcl
project_id              = "acme-apps-prod"
region                  = "us-west2"
vpc_name                = "apps-prod"
control_plane_ipv4_cidr = "172.16.16.0/28"

node_pools = [
  {
    name         = "services"
    machine_type = "n2-standard-4"
    min_size     = 2
    max_size     = 10
  },
  {
    name         = "batch"
    machine_type = "e2-standard-8"
    min_size     = 0
    max_size     = 20
    spot         = true
    taints       = [{ key = "workload", value = "batch", effect = "NO_SCHEDULE" }]
  },
]
```

## What the module guarantees on every cluster

**Resilience**

- Regional clusters: control plane and node pools are replicated across the
  region's zones, so a zone failure does not take the cluster down.
- Auto-repair and auto-upgrade on every node pool, with surge upgrades
  (`max_surge 1`, `max_unavailable 0`): nodes are replaced with standing
  capacity instead of being drained into a shrinking pool.
- Autoscaling on every pool. Node counts are per zone (regional clusters
  replicate each pool across the region's zones).

**Networking (on the network team's infra)**

- VPC-native (alias IP) cluster on the `<vpc>-gke-<region>` subnet; pod IPs
  come from the `pods` secondary range and Service ClusterIPs from `services`.
- Private nodes: no public IP addresses on any node.
- Private control-plane endpoint by default (reachable from the VPC: jump
  host, VPN or Interconnect; add `master_authorized_networks` for on-prem
  ranges). A public endpoint is opt-in — and the module **refuses to plan**
  one unless authorized networks are configured, so no internet-exposed
  control planes.
- Dataplane V2 (eBPF) with network policy enforcement, which is what lets
  product teams isolate their namespaces from each other with
  `NetworkPolicy` on a shared cluster.
- Intranode visibility enabled for east-west traffic debugging.

**Security**

- Workload Identity Federation (`<project>.svc.id.goog`): workloads reach
  Pub/Sub, Cloud Storage, Cloud SQL and other Google Cloud services as their
  own IAM identities, bound to Kubernetes service accounts. Node credentials
  are never shared with pods (`GKE_METADATA` metadata mode).
- A dedicated per-cluster node service account, created by the module with
  only `roles/monitoring.metricWriter` and `roles/logging.logWriter`. Nodes
  never run on the Compute Engine default service account — the module
  refuses to plan if you try.
- Least-privilege node OAuth scopes (no `cloud-platform` scope).
- Shielded GKE nodes: Secure Boot and integrity monitoring on every pool,
  COS containerd images.
- No static client certificates; access goes through Google identities.
- Optional hardening, off by default: CMEK for Kubernetes Secrets
  (`database_encryption_key_name`) and Google-group RBAC
  (`rbac_security_group`).

**Operations**

- `REGULAR` release channel: Kubernetes versions that have passed GKE's
  testing, upgraded on a predictable cadence; control-plane upgrades land in
  the daily maintenance window (`04:00` UTC by default).
- System and workload logs, system metrics, and managed Prometheus.
- A module-managed `system` node pool so GKE add-ons and observability agents
  never compete with product workloads for capacity.
- Cluster deletion protection: `tofu destroy` fails until `deletion_protection`
  is explicitly set to `false`.

## Operating the clusters

### Getting access

By default the endpoint is private. Reach it from inside the VPC — a jump
host with IAP TCP forwarding, a VPN, or Interconnect — then either:

```sh
tofu output -raw get_credentials_command   # gcloud container clusters get-credentials ...
```

or write a complete kubeconfig and use it directly (requires
`gke-gcloud-auth-plugin`):

```sh
tofu output -raw kubeconfig > kubeconfig.yaml
KUBECONFIG=kubeconfig.yaml kubectl get nodes
```

If the platform team has no VPC access path yet, set
`enable_private_endpoint = false` together with the office/VPN CIDRs in
`master_authorized_networks`; the public endpoint is then restricted to
those ranges.

### Onboarding a product team

The module deliberately stops at the cluster: namespaces, RBAC and workload
identity bindings belong to the teams (or a later onboarding step). To let a
team's workload use a Google Cloud service, bind their Kubernetes service
account to a Google service account:

```sh
gcloud iam service-accounts add-iam-policy-binding payments@acme-apps-prod.iam.gserviceaccount.com \
  --role roles/iam.workloadIdentityUser \
  --member "serviceAccount:acme-apps-prod.svc.id.goog[payments/default]"
```

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: default
  namespace: payments
  annotations:
    iam.gke.io/gcp-service-account: payments@acme-apps-prod.iam.gserviceaccount.com
```

Each team should also deploy a default-deny `NetworkPolicy` in their
namespace — enforcement is already on.

### Upgrades

GKE controls versions through the release channel. Node pools auto-upgrade
after the control plane, with surge. The only knobs are `release_channel`
and `maintenance_start_time`.

### Retiring a cluster

Set `deletion_protection = false`, apply, then destroy. This two-step is
intentional.

## Prerequisites

- The network team's `<vpc>-gke-<region>` subnet exists with secondary ranges
  `pods` and `services` (override the names with `pods_secondary_range_name`
  / `services_secondary_range_name` if they differ).
- `container.googleapis.com` is enabled in the project.
- If using `database_encryption_key_name`: the KMS key exists and the GKE
  service agent can use it (`roles/cloudkms.cryptoKeyEncrypterDecrypter`).
- If using `rbac_security_group`: the Cloud Identity group exists and is
  named `gke-security-groups@...`.
- If the cluster pulls images from private Artifact Registry repositories,
  grant `roles/artifactregistry.reader` to the node service account (append
  it to `node_service_account_roles`).

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `project_id` | string | *(required)* | Project hosting the environment VPC; the cluster lives there too. |
| `region` | string | *(required)* | US region for the cluster; the `<vpc>-gke-<region>` subnet must exist there. |
| `vpc_name` | string | *(required)* | Environment VPC name (`apps-staging` or `apps-prod`). |
| `control_plane_ipv4_cidr` | string | *(required)* | Unique /28 for the private control plane, allocated by the network team. |
| `cluster_name` | string | `null` | Cluster name; defaults to `<vpc>-<region>`. |
| `subnet_name` | string | `null` | GKE subnet name; defaults to `<vpc>-gke-<region>`. |
| `pods_secondary_range_name` | string | `"pods"` | Secondary range holding pod IPs. |
| `services_secondary_range_name` | string | `"services"` | Secondary range holding Service ClusterIPs. |
| `enable_private_endpoint` | bool | `true` | Keep the control-plane endpoint private (recommended). |
| `master_authorized_networks` | list(string) | `[]` | CIDRs allowed to reach the control plane; required for a public endpoint. |
| `release_channel` | string | `"REGULAR"` | GKE release channel (`RAPID`, `REGULAR`, `STABLE`). |
| `maintenance_start_time` | string | `"04:00"` | UTC HH:MM start of the daily maintenance window. |
| `deletion_protection` | bool | `true` | Refuse accidental cluster destruction. |
| `node_pools` | list(object) | `[]` | Workload node pools (see the schema in `variables.tf`). |
| `create_system_node_pool` | bool | `true` | Create the module-managed `system` pool. |
| `system_node_pool_machine_type` | string | `"e2-standard-2"` | Machine type of the `system` pool. |
| `system_node_pool_min_size` | number | `1` | Minimum `system` nodes per zone. |
| `system_node_pool_max_size` | number | `2` | Maximum `system` nodes per zone. |
| `create_node_service_account` | bool | `true` | Create the dedicated node service account. |
| `node_service_account_email` | string | `null` | Existing node service account (when not creating one). |
| `node_service_account_roles` | list(string) | metricWriter, logWriter | Roles granted to the created node service account. |
| `node_oauth_scopes` | list(string) | GKE least-privilege set | OAuth scopes on node credentials. |
| `database_encryption_key_name` | string | `null` | CMEK key for Kubernetes Secrets. |
| `rbac_security_group` | string | `null` | Google group for RBAC group bindings (`gke-security-groups@...`). |
| `labels` | map(string) | `{}` | Labels on the cluster resource. |

## Outputs

| Name | Description |
|---|---|
| `cluster_name` | Name of the cluster. |
| `cluster_id` | Fully qualified cluster id. |
| `cluster_endpoint` | HTTPS endpoint of the control plane (private by default). |
| `cluster_ca_certificate` | Base64 CA certificate (sensitive). |
| `kubeconfig` | A complete kubeconfig file (sensitive). |
| `get_credentials_command` | `gcloud` command to configure kubectl. |
| `workload_identity_pool` | The cluster's Workload Identity pool (`<project>.svc.id.goog`). |
| `node_service_account_email` | Service account the nodes run as. |
| `node_pool_names` | Names of the module-managed node pools. |
| `control_plane_version` | Current control-plane Kubernetes version. |
