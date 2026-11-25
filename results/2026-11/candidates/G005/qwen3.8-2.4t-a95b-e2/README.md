# GKE Standard production cluster module

One root module that every new shared, production GKE Standard cluster is
created from. Platform engineers supply the four cluster-specific inputs; the
module makes and documents every other design decision.

```hcl
module "gke" {
  source = "." # or wherever this module lives

  project_id   = "apps-platform"
  cluster_name = "apps-staging-shared"
  region       = "us-central1"
  network_name = "apps-staging" # or "apps-prod"
}
```

Only `project_id`, `cluster_name`, `region` and `network_name` are required.
See `variables.tf` (every variable is documented) and `minimal.tfvars` for the
smallest valid instantiation.

## Design decisions

**Resilience**

- Regional cluster: the control plane and the single `default-pool` node pool
  span every zone of the region, so losing one zone costs neither.
- Cluster autoscaler per pool (defaults: 1-5 nodes per zone), auto-repair and
  auto-upgrade on, upgrades follow the release channel (default `STABLE`).
- Surge upgrades (`max_surge = 1`, `max_unavailable = 0`): replacements join
  before old nodes drain, so upgrades never reduce capacity.
- Maintenance window defaults to Sundays 02:00-08:00 UTC (`maintenance_window`).

**Networking**

- VPC-native cluster in the network team's VPC. The subnet is derived from the
  convention `<network_name>-gke-<region>` (override with `subnetwork_name`);
  pod/Service IPs come from its `pods` and `services` secondary ranges.
- Nodes get private IPs only. The control plane gets a private IP in the VPC
  (always reachable from inside the network) plus, by default, a public
  endpoint that is firewalled off until `master_authorized_networks` lists
  CIDRs (office/VPN). Set `enable_private_endpoint = true` for a strictly
  private control plane (e.g. managed from a bastion).
- The control plane's /28 is auto-assigned by default so multiple clusters can
  share one VPC; pin it with `master_ipv4_cidr_block` if needed.

**Security**

- Workload Identity enabled (`workload_identity_config`, GKE Metadata Server on
  nodes). This is how product workloads reach Pub/Sub, Cloud Storage, Cloud SQL
  etc.: each team binds its Kubernetes service account to its own Google
  service account via `roles/iam.workloadIdentityUser` on
  `serviceAccount:<project>.svc.id.goog[<namespace>/<ksa>]`.
- Nodes run under a dedicated, least-privilege service account created by the
  module (log/metric writers + image-pull roles only), not the Compute Engine
  default SA. OAuth scopes are Google's recommended minimum.
- Dataplane V2 (built-in network policy enforcement and observability),
  shielded nodes with secure boot and integrity monitoring, legacy metadata
  endpoints disabled.
- GKE Security Posture (BASIC posture checks + node vulnerability scanning by
  default), Binary Authorization available via `binary_authorization_mode`,
  optional customer-managed KMS encryption of Kubernetes Secrets
  (`database_encryption_key_name`).
- `deletion_protection = true` by default.

**Operations**

- System-component logging/monitoring into Cloud Logging/Cloud Monitoring by
  default (add `WORKLOADS` to `logging_components` to ingest app logs).
- Horizontal Pod Autoscaling, L7 ingress controller, NodeLocal DNSCache,
  VPA addon, and L4 ILB subsetting enabled.
- Optional upgrade/health notifications to a Pub/Sub topic
  (`upgrade_notification_pubsub_topic`).

## Prerequisites (already in place per platform conventions)

- APIs enabled in the project: `container.googleapis.com`,
  `compute.googleapis.com`, `iam.googleapis.com`.
- The network team's VPC contains subnet `<network_name>-gke-<region>` with
  secondary ranges `pods` (large enough for max nodes x pods-per-node) and
  `services`.
- Access to managed services such as Cloud SQL is arranged at the network
  level (Private Service Access / PSC) or per workload (Cloud SQL Auth Proxy
  with the workload's Google service account); neither is cluster-specific, so
  it lives outside this module.

## Outputs

Endpoints (public/private), CA certificate, master version, the Workload
Identity pool, the node service account email, and the subnet in use -
everything a team needs to configure kubectl and IAM bindings.
