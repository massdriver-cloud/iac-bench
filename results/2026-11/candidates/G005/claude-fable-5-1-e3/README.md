# gke-standard-cluster

Standard module for every production GKE Standard cluster run by the platform team.

## What you fill in

| Variable | Meaning |
|---|---|
| `project_id` | Project that owns the `apps-<env>` VPC; the cluster is created there. |
| `name` | Cluster name (also prefixes the node service account). |
| `environment` | `staging` or `prod` – selects VPC `apps-<env>` and subnet `apps-<env>-gke-<region>`. |
| `region` | US region, e.g. `us-central1`. |
| `master_authorized_networks` | CIDRs allowed to reach the Kubernetes API (office, VPN, CI). `0.0.0.0/0` is rejected. |

Everything else has a production default (see `variables.tf`): node pools, release channel, maintenance window,
KMS secrets encryption, Binary Authorization, private-endpoint-only mode, Workload Identity service accounts.

```hcl
module "cluster" {
  source = "./"   # or the registry path once published

  project_id  = "apps-platform-project"
  name        = "apps-prod-us-central1"
  environment = "prod"
  region      = "us-central1"

  master_authorized_networks = [
    { cidr_block = "203.0.113.0/24", display_name = "office-egress" },
  ]

  node_pools = {
    general = {}
    batch   = { machine_type = "n2-standard-8", spot = true, max_nodes_per_zone = 10,
                taints = [{ key = "workload", value = "batch", effect = "NO_SCHEDULE" }] }
  }

  workload_service_accounts = {
    orders-api = {
      namespace                  = "orders"
      kubernetes_service_account = "orders-api"
      project_roles              = ["roles/pubsub.publisher", "roles/cloudsql.client"]
    }
  }
}
```

## What the module decides for you

**Resilience**
- Regional cluster: HA control plane and nodes across all zones in the region.
- Node pools autoscale per zone, auto-repair, auto-upgrade with surge (0 unavailable), balanced across zones.
- Release channel (REGULAR by default) with a weekend maintenance window.
- Deletion protection on by default.

**Security**
- Private nodes (no public IPs); API endpoint reachable only from `master_authorized_networks` and the VPC.
- Workload Identity enabled; dedicated node service account with only logging/monitoring/Artifact Registry read.
- Shielded nodes with Secure Boot and integrity monitoring; COS with containerd; legacy metadata endpoints off;
  no client certificates.
- Dataplane V2 (NetworkPolicy enforced), intranode visibility, security posture + vulnerability scanning.
- Optional CMEK for etcd secrets and Binary Authorization.

**Shared operations**
- Cost allocation per namespace, VPA, HPA, managed Prometheus, system + workload logs.
- Gateway API, GCE PD and GCS FUSE CSI drivers, NodeLocal DNSCache.

## Giving a workload access to Google services

Declare it in `workload_service_accounts`; the module creates the Google service account, binds it to the
Kubernetes service account through Workload Identity, and grants the project roles. Then annotate the KSA with the
value from the `workload_service_accounts` output (`iam.gke.io/gcp-service-account=<email>`). For Cloud SQL, grant
`roles/cloudsql.client` and run the Auth Proxy sidecar or use the Go/Java/Python connectors.
