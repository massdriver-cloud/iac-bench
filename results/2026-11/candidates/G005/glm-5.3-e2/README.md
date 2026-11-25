# GKE Standard cluster module

The platform team's standard module for Google Kubernetes Engine (Standard)
clusters. Every new cluster that product teams deploy to comes from this
module; the module encodes everything a production, multi-team cluster needs,
so an engineer only has to answer five questions (see [Required
inputs](#required-inputs)) to get a cluster that is resilient and secure by
default.

The module assumes the network team's conventions: one VPC per environment
(`apps-staging`, `apps-prod`) in the same project, with a subnet named
`<vpc>-gke-<region>` in each region carrying secondary ranges named `pods`
and `services`.

## Quick start

```hcl
module "gke" {
  source = "..." # this module

  project_id             = "my-project"
  name                   = "apps-prod-usw1"
  region                 = "us-west1"
  vpc_name               = "apps-prod"
  master_ipv4_cidr_block = "172.16.1.0/28"
}
```

Run standalone with `tofu plan -var-file=minimal.tfvars` (see
`minimal.tfvars` for the smallest valid instantiation). When embedding the
module, configure the `google` provider in your root module with the same
project as `project_id` — the provider block in this module only takes effect
in standalone use.

## Required inputs

| Variable | Notes |
|---|---|
| `project_id` | The project that owns the VPC and will own the cluster. |
| `name` | Cluster name, 3-26 chars (also names the node service account `gke-<name>`). |
| `region` | Regional cluster — control plane and nodes span the region's zones. |
| `vpc_name` | `apps-staging` or `apps-prod`. |
| `master_ipv4_cidr_block` | /28 for the control plane; unique per VPC, no overlap with any subnet or peered range. |

Everything else has a default; the notable knobs are documented in
`variables.tf`. The defaults below are decisions the module makes on the
platform team's behalf:

## What the module does by default

**Resilience**

- **Regional clusters.** Control plane and nodes are spread across the
  region's three zones, and node pools always keep at least one node per
  zone (the `system` pool: `min_count = 1`, per zone).
- **Node auto-repair and auto-upgrade** are on for every pool, driven by the
  `REGULAR` release channel (monthly-ish patch cadence, recommended for
  production).
- **Surge upgrades** (`max_surge = 1`, `max_unavailable = 0`): nodes are
  replaced one at a time, and a node is never drained before its replacement
  is Ready, so upgrades never reduce capacity.
- **Autoscaling per pool** with BALANCED location policy, so pods spread
  evenly across zones.
- **Deletion protection**: `tofu destroy` refuses to delete the cluster
  unless `deletion_protection` is explicitly set to false.
- **Maintenance window** (daily 10:00–14:00 UTC by default, i.e. overnight
  in the US) so control-plane upgrades happen at a predictable, low-traffic
  time.

**Security**

- **Private nodes** (no public IPs) and a **private control-plane endpoint**
  reachable only from the VPC (VPN, Interconnect, or a bastion). Global
  access to the private endpoint is enabled so the endpoint is reachable
  from VPC subnets in other regions. If you must expose a public endpoint
  (e.g. for a CI runner outside the VPC), set `enable_private_endpoint =
  false` **and** allow-list your CIDRs in `master_authorized_networks`; the
  module refuses to create an un-restricted public endpoint.
- **Dedicated node service account per cluster** (`gke-<name>`), granted only
  the roles nodes themselves need (`logging.logWriter`,
  `monitoring.metricWriter`, `stackdriver.resourceMetadata.writer`) — never
  the project default compute account. The `cloud-platform` OAuth scope is
  intentional: access is governed by IAM on this service account, not by
  legacy scopes.
- **Workload Identity** is enabled: pods authenticate as their Kubernetes
  service account, not as the node. Product teams get exactly the Google
  Cloud access they need (Pub/Sub, Cloud Storage, Cloud SQL, …) via
  `workload_identity_bindings` (below).
- **Shielded nodes**, no legacy ABAC, no Kubernetes alpha features, and
  Services may not use arbitrary `ExternalIPs`.
- **Dataplane V2** (default for new clusters): Kubernetes `NetworkPolicy` is
  enforced natively, so teams can isolate their namespaces from each other.
- Optional: **CMEK for Kubernetes Secrets** (`database_encryption_key`) and
  **Binary Authorization** (`enable_binary_authorization`).

**Operations**

- System + workload logging, and full system/workload monitoring components.
- L4 ILB subsetting for healthier large Services; Gateway API (stable) so
  teams manage their own ingress.
- Image streaming on all node pools for faster pod startup.
- Cluster `resource_labels` for cost allocation.

## Node pools

The module always creates a `system` node pool (`e2-standard-4`, 1–3 nodes
per zone) for GKE and Kubernetes system components, and removes GKE's
built-in default pool. Product-team pools are declared in `node_pools`,
keyed by pool name; an entry keyed `system` replaces the module's default.
`min_count`/`max_count` are per-zone autoscaling bounds.

```hcl
node_pools = {
  general = { machine_type = "e2-standard-8", min_count = 2, max_count = 8 }
  memory  = {
    machine_type = "n2-standard-8"
    disk_type    = "pd-ssd"
    taints       = [{ key = "pool", value = "memory", effect = "NoSchedule" }]
  }
  batch = { machine_type = "n2-standard-4", spot = true, min_count = 0, max_count = 20 }
}
```

Taint effects use Kubernetes spelling (`NoSchedule`, `PreferNoSchedule`,
`NoExecute`); the module translates them to GKE's API values.

## IP planning

Pods and Services come from the subnet's `pods` and `services` secondary
ranges (the network team sizes these; a /17 pods range supports ~1000 nodes
at the default `default_max_pods_per_node = 32`). The default of 32 pods per
node, instead of GKE's 110, keeps IP headroom on a shared multi-team
cluster; raise it only for genuinely dense nodes. Each cluster also needs
its own /28 `master_ipv4_cidr_block`, unique within the VPC — track these in
a simple registry to avoid collisions between clusters.

## Workload Identity for product teams

Workloads should reach Pub/Sub, Cloud Storage, Cloud SQL and other Google
Cloud services through Workload Identity, never through node credentials.
The module wires the cluster side; per team you only need:

1. A Google service account for the workload (e.g. created by the product
   team in the same project), granted the roles the workload needs, e.g.
   `roles/pubsub.subscriber`, `roles/storage.objectViewer` — for Cloud SQL,
   `roles/cloudsql.client` plus the Cloud SQL Auth Proxy sidecar (which
   authenticates through Workload Identity).
2. A binding in this module:

```hcl
workload_identity_bindings = {
  orders-api = {
    service_account = "orders-api@my-project.iam.gserviceaccount.com"
    namespace       = "orders"
  }
}
```

3. The team annotates their Kubernetes service account
   (`name = "orders-api"` in namespace `orders` in this example):

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: orders-api
  namespace: orders
  annotations:
    iam.gke.io/gcp-service-account: orders-api@my-project.iam.gserviceaccount.com
```

The module grants the Kubernetes service account the
`roles/iam.workloadIdentityUser` role on the Google service account, which
is what lets pods impersonate it.

## CMEK for Secrets

To encrypt Kubernetes Secrets with a Cloud KMS key, pass the key's self-link
in `database_encryption_key`, and grant the GKE service agent permission on
the key once:

```sh
gcloud kms keys add-iam-policy-binding KEY --keyring RING --location LOCATION \
  --member "serviceAccount:service-PROJECT_NUMBER@container-engine-robot.iam.gserviceaccount.com" \
  --role "roles/cloudkms.cryptoKeyEncrypterDecrypter"
```

This grant is left to you (it needs the project number, and the service
agent must exist) rather than performed at plan time.

## Accessing a cluster with a private endpoint

`kubectl` must reach the control plane's private IP: via the network team's
VPN/Interconnect, or from a VM inside the VPC. The `cluster_endpoint` and
`cluster_ca_certificate` outputs contain what a kubeconfig needs. Global
access is enabled, so a bastion or VPN gateway in any region's subnet works.

## Notes

- Cluster `name` also names the node service account, so it is capped at 26
  characters and must be unique per project (service account ids are
  project-scoped).
- Node pool machine types, disks and spot usage are the platform team's per-
  cluster decisions; the defaults (`e2-standard-4`, 100 GB `pd-balanced`)
  suit general system and team pools.
- The google provider is pinned to `~> 6.0`.
