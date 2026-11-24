# GKE Standard cluster module

Creates a production-grade **regional GKE Standard** cluster in one of the network team's VPCs
(`apps-staging` / `apps-prod`), using the pre-created subnet `<vpc>-gke-<region>` and its
`pods` / `services` secondary ranges.

## What you fill in

| Variable | Meaning |
|---|---|
| `project_id` | Project that holds the VPC; the cluster is created there too. |
| `region` | US region (`us-central1`, `us-east4`, ...). |
| `environment` | `staging` or `prod` – picks the VPC. |
| `cluster_name` | Cluster name. |
| `master_authorized_networks` | CIDRs allowed to talk to the API server (VPN, CI, bastion). |

Everything else has a sensible default. The most common optional knob is `node_pools`:

```hcl
node_pools = {
  general = { machine_type = "n2-standard-8", min_nodes_per_zone = 1, max_nodes_per_zone = 10 }
  batch = {
    machine_type = "n2-standard-16"
    spot         = true
    taints       = [{ key = "workload", value = "batch", effect = "NO_SCHEDULE" }]
  }
}
```

## What the module decides for you

* **Resilience** – regional control plane and nodes across 3 zones, node auto-repair /
  auto-upgrade on a release channel inside a weekend maintenance window, surge upgrades,
  per-pool autoscaling, `deletion_protection = true`.
* **Security** – private nodes, control plane reachable only from `master_authorized_networks`
  (never from the public internet), Workload Identity, dedicated least-privilege node service
  account (no default compute SA), shielded nodes with secure boot, Dataplane V2 with
  NetworkPolicy enforcement, legacy ABAC and client certs disabled, security posture and
  vulnerability scanning, optional CMEK for etcd (`database_encryption_kms_key`) and
  Binary Authorization (`enable_binary_authorization`).
* **Operations** – Cloud Logging for system and workloads, Managed Prometheus, VPA, GKE cost
  allocation per namespace, Gateway API, GCE PD / GCS FUSE CSI drivers, NodeLocal DNSCache.

## Accessing Google Cloud services from workloads

Nodes carry no application permissions. Use Workload Identity: create a Google service account
with the roles the app needs (Pub/Sub, GCS, Cloud SQL Client...), bind it with
`roles/iam.workloadIdentityUser` to `serviceAccount:<project>.svc.id.goog[<namespace>/<ksa>]`,
and annotate the Kubernetes service account with `iam.gke.io/gcp-service-account`.

## Prerequisites the network team provides

* VPC `apps-<environment>` with subnet `apps-<environment>-gke-<region>` and secondary ranges
  `pods` and `services`.
* Cloud NAT on that region (nodes are private and need it for outbound internet, e.g. pulling
  images from public registries).
* Private Google Access on the subnet.
