# GKE Standard module for production clusters

The platform team's standard building block for shared, production GKE
(Standard mode) clusters. Every new cluster comes from this module; per-cluster
specifics go in a small tfvars file and the module owns every other decision.

## What the module decides

| Area | Decision | Why |
| --- | --- | --- |
| Topology | Regional Standard cluster, one `primary` node pool, default pool removed | Control plane replicated across all zones; a zone outage survives |
| Networking | VPC-native on the environment VPC; subnet `<vpc>-gke-<region>`; secondary ranges `pods` / `services` | Matches the network team's naming exactly |
| Privacy | Private nodes, private control-plane endpoint, master global access on, API server limited to RFC 1918 authorized networks | Control plane never exposed to the public internet |
| Identity | Workload Identity on, dedicated least-privilege node SA (no Compute default SA), shielded nodes + secure boot, legacy metadata endpoints off | Workloads reach Pub/Sub, Cloud Storage and Cloud SQL as their own IAM principals, no node keys |
| Upgrades | REGULAR release channel, surge upgrades (`max_surge=1`, `max_unavailable=0`), auto-repair/auto-upgrade, Saturday maintenance window (08:00-16:00 UTC, overnight in US) | Capacity is never reduced during upgrades |
| Scaling | Cluster autoscaler per zone, min 1 node per zone by default | Every zone keeps capacity at all times |
| Observability | Dataplane V2, control-plane logs (system + workloads), Cloud Monitoring + Managed Prometheus, NodeLocal DNS cache | Day-2 operations without extra components |
| Extras | Optional KMS application-layer secrets encryption, optional Pub/Sub upgrade notifications | Flip on by setting a variable |

## Prerequisites (owned by other teams)

- **Network team**: one VPC per environment (`apps-staging`, `apps-prod`) with a
  subnet named `<vpc>-gke-<region>` in each region, carrying secondary ranges
  named `pods` and `services`.
- Nodes have no external IPs: the subnet needs **Cloud NAT** (or equivalent
  egress) for image pulls.
- The identity running OpenTofu needs permission to create GKE clusters,
  service accounts and project IAM bindings in the project.

## Usage

```hcl
module "apps_prod_main" {
  source = "<path to this module>"

  cluster_name = "apps-prod-main"
  region       = "us-central1"
  vpc_name     = "apps-prod"
}
```

Apply with the module's variables:

```sh
tofu init
tofu plan  -var-file minimal.tfvars
tofu apply -var-file minimal.tfvars
```

`project_id` is omitted above on purpose: the module defaults to the project
the provider/credentials point at — the same project that owns the environment
VPCs. Set it explicitly only when that default is wrong.

Fetch kubeconfig afterwards (from a network that reaches the private endpoint,
e.g. over VPN):

```sh
tofu output get_credentials_command
```

## Connecting workloads to Google Cloud services

Grant a Kubernetes service account an IAM binding to a Google service account:

```sh
gcloud iam service-accounts add-iam-policy-binding \
  WORKLOAD_GSA@PROJECT.iam.gserviceaccount.com \
  --role roles/iam.workloadIdentityUser \
  --member "serviceAccount:PROJECT.svc.id.goog[NAMESPACE/KSA]"
```

Annotate the Kubernetes service account with
`iam.gke.io/gcp-service-account=WORKLOAD_GSA@PROJECT.iam.gserviceaccount.com`
and pods using it authenticate to Pub/Sub, Cloud Storage or Cloud SQL without
any exported keys.

## Common knobs

Everything has a safe production default; override only what differs:
`machine_type`, `disk_size_gb`, `disk_type`,
`autoscaling_min_nodes_per_zone`, `autoscaling_max_nodes_per_zone`,
`release_channel`, `kubernetes_version`, `master_ipv4_cidr_block`,
`master_authorized_networks`, `maintenance_start_time_utc`,
`maintenance_end_time_utc`, `maintenance_recurrence`,
`database_encryption_kms_key`, `upgrade_notifications_topic`, `labels`,
`deletion_protection` (switch on once the cluster is in service).
