# Production GKE Standard clusters

This root module creates a regional **GKE Standard** cluster in the same project as the network team's pre-created VPC. It intentionally creates no VPC, subnet, or secondary ranges.

## Fixed network contract

For `environment = "staging"` or `"prod"` and a US `region`, the module selects:

| Resource | Name |
|---|---|
| VPC | `apps-<environment>` |
| GKE subnet | `apps-<environment>-gke-<region>` |
| Pod secondary range | `pods` |
| Service secondary range | `services` |

Those networks and ranges must already exist, and the subnet must be in the selected project and region. The control-plane `master_ipv4_cidr_block` is a required, unique, non-overlapping `/28` for each cluster; it is not taken from the pod or service ranges.

Because nodes have no public IP addresses, the network team must also provide an outbound path to Google APIs and any required internet endpoints. Enable **Private Google Access** on the GKE subnet for Google API access and provide Cloud NAT where general internet egress is required. This module deliberately does not alter network-team-owned subnets or create competing NAT configuration.

`minimal.tfvars` is the smallest valid configuration. Replace its example project ID and control-plane range with real values, then run:

```sh
tofu init
tofu plan -var-file=minimal.tfvars
tofu apply -var-file=minimal.tfvars
```

The module can enable the APIs it needs. The identity running OpenTofu therefore needs permission to manage Service Usage, IAM service accounts and project IAM members, and GKE clusters/node pools. Set `enable_apis = false` if API activation is handled centrally. The runner also needs permission to use the existing network, but does not need to administer it.

## Production decisions made by the module

- A **regional** control plane and regional node pools, rather than a zonal cluster.
- VPC-native networking using the supplied `pods` and `services` ranges.
- Private nodes and, by default, a **private-only control-plane endpoint**. A public endpoint is permitted only when at least one authorized network is explicitly supplied; Google public CIDR access remains disabled.
- GKE Dataplane V2, which supplies Kubernetes NetworkPolicy enforcement without the legacy Calico add-on. Product teams must still author appropriate NetworkPolicies.
- Legacy ABAC, legacy client-certificate issuance, and Kubernetes Service `externalIPs` are disabled.
- The STABLE release channel (REGULAR is optional), automatic node repair and upgrades, a daily UTC maintenance window, and zero-unavailable surge upgrades.
- Independently managed, autoscaling node pools. In a regional pool, `min_nodes` and `max_nodes` are **per zone**. The default `general` pool uses one to six non-Spot `e2-standard-4` nodes per zone, 100 GB balanced persistent disks, and the Container-Optimized OS containerd image.
- Shielded nodes with secure boot, integrity monitoring, legacy metadata endpoints disabled, and the GKE metadata server.
- A dedicated node service account with only image-pull and telemetry-related roles. Nodes receive the `cloud-platform` OAuth scope so IAM, rather than a collection of broad OAuth scopes, remains the authorization boundary. Applications must not use this identity.
- Cluster Workload Identity, system/workload logging, system monitoring, Managed Service for Prometheus, NodeLocal DNSCache, the persistent-disk CSI driver, HPA, and VPA support.
- Deletion protection by default. To destroy a cluster intentionally, first apply with `deletion_protection = false`.

Control-plane changes require quota and time. Surge upgrades also require quota for one extra node per upgrading pool. GKE may use any available zone in the region unless `node_locations` is set on a pool.

## Accessing a private cluster

The default control plane has no public endpoint. Run `gcloud container clusters get-credentials` and `kubectl` from a VM, bastion, Cloud Shell with private access, VPN/interconnect-connected host, or another environment with a working private route and firewall path to the control plane. A CI runner on the public internet cannot manage the default cluster directly.

`master_global_access_enabled = false` means that private control-plane access is regional by default. Enable it only when the operating model requires cross-region private access. Authorized networks can further restrict private control-plane access.

If `enable_private_endpoint = false` is unavoidable, supply every trusted public CIDR in `master_authorized_networks`; the module rejects an unrestricted public control plane.

## Product workload identities

Use `workload_service_accounts` to create a distinct Google service account for each Kubernetes service account and bind it with Workload Identity. This supports Pub/Sub, Cloud Storage, Cloud SQL Auth Proxy, and other Google APIs without service-account key files and without granting application permissions to nodes.

Example input:

```hcl
workload_service_accounts = {
  orders-publisher = {
    kubernetes_namespace       = "orders"
    kubernetes_service_account = "publisher"
    display_name               = "Orders Pub/Sub publisher"
    project_roles              = ["roles/pubsub.publisher"]
  }
}
```

Then annotate the Kubernetes service account (create it with the workload's normal deployment process):

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: publisher
  namespace: orders
  annotations:
    iam.gke.io/gcp-service-account: orders-publisher@PROJECT_ID.iam.gserviceaccount.com
```

Use the `workload_service_account_emails` output rather than constructing the annotation manually when another root module owns the workload. Project-level role support is convenient for small deployments, but resource-level IAM (for example, publisher on one Pub/Sub topic) is preferable for stronger tenant isolation. Such resource-level bindings can reference the same output.

Each map key is the actual Google service account ID and must be unique within the project, including against the generated node service account ID. The module does not create Kubernetes namespaces or service accounts, Kubernetes RBAC, NetworkPolicies, or workload resources; those remain application/platform configuration concerns.

## Custom node pools

Set `node_pools` to replace the default map. Omitted object attributes receive the defaults described in `variables.tf`. For example, a second pool can isolate a workload with taints and labels:

```hcl
node_pools = {
  general = {
    min_nodes = 1
    max_nodes = 6
  }
  batch = {
    machine_type = "n2-standard-8"
    min_nodes    = 0
    max_nodes    = 4
    labels       = { workload = "batch" }
    taints = [{
      key    = "workload"
      value  = "batch"
      effect = "NO_SCHEDULE"
    }]
  }
}
```

Keep at least one non-Spot pool with spare capacity for cluster-system components. Spot nodes are suitable only for interruption-tolerant production workloads. Node network tags and node locations can be set per pool when required by network policy or zonal capacity planning.

## Operations and optional integrations

- `upgrade_notification_topic` accepts an existing full Pub/Sub topic ID for GKE notifications. The project's GKE service agent must have permission to publish to that topic.
- `gke_security_group` can enable Google Groups for Kubernetes RBAC. Configure the required `gke-security-groups@<domain>` group and grant users Google IAM access to the cluster separately.
- The CA certificate output is marked sensitive. Kubernetes credentials themselves should be obtained through short-lived Google identity credentials, not stored in module outputs.
- Cluster teardown does not disable Google APIs. IAM resources are non-authoritative `*_iam_member` resources, so they do not replace unrelated role bindings.
