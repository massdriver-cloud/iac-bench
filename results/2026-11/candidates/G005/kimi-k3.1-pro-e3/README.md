# Production GKE Standard root module

This module creates one **regional GKE Standard cluster** in the same project as the network team's existing VPC. It is intentionally self-contained: it calls no registry modules and does not create or take ownership of the VPC or subnet.

## Baseline decisions

- A regional control plane and regional node pools spread nodes across multiple zones. The dedicated `system` pool and the default `general` application pool each start with one node **per zone** and autoscale. Node counts in inputs are per zone, not regional totals.
- The default node pool is removed. All real pools use Container-Optimized OS with containerd, shielded VMs with secure boot and integrity monitoring, a dedicated least-privilege node service account, GKE metadata concealment, and image streaming.
- Nodes auto-repair and auto-upgrade. Surge upgrades add one node before removing capacity. The cluster uses the REGULAR release channel and a daily 07:00-11:00 UTC maintenance window by default.
- Nodes are private and the control plane public endpoint is disabled by default. A unique control plane `/28` is required. Enabling the public endpoint also requires at least one authorized network.
- VPC-native networking uses the existing `pods` and `services` secondary ranges. Dataplane V2 enforces Kubernetes NetworkPolicies, NodeLocal DNSCache is enabled, and L4 internal load balancer subsetting is enabled.
- Workload Identity is enabled. Nodes receive only image-read and telemetry permissions, not application access to Pub/Sub, Cloud Storage objects, or Cloud SQL.
- System and workload logs, system metrics, Managed Service for Prometheus, GKE cost allocation, basic security posture and vulnerability reporting, and Binary Authorization project-policy enforcement are enabled.
- GKE node auto-provisioning is disabled; the explicit pools are the only capacity policy. Vertical Pod Autoscaler support is available for workload right-sizing.
- Cluster deletion protection is enabled by default.

The module does **not** install Kubernetes RBAC roles, namespace NetworkPolicies, Pod Security labels, or a Binary Authorization policy. Those are platform workload/onboarding concerns. In particular, enforce default-deny namespace NetworkPolicies and configure the project's Binary Authorization policy/attestors to make image admission match organizational policy.

## Existing network and access requirements

For `environment = "prod"` or `"staging"` and region `REGION`, the module uses:

```text
projects/PROJECT/global/networks/apps-prod|apps-staging
projects/PROJECT/regions/REGION/subnetworks/apps-prod|apps-staging-gke-REGION
secondary ranges: pods, services
```

The subnet must have enough primary and secondary IP capacity for the selected pool sizes and 64 pods per node. It must provide private Google API access (normally Private Google Access), and a Cloud NAT or equivalent approved egress path if workloads pull public images or reach the internet. The network team retains ownership of routing, firewall policy, NAT, and DNS.

Each cluster needs a different, non-overlapping `master_ipv4_cidr_block`. With the default private-only control plane, engineers and CI also need private connectivity to that endpoint. Enable master global access only if control plane access from other regions is required.

The identity applying the module needs permission to manage GKE, service accounts and IAM, enable services (unless `enable_required_apis = false`), and read the referenced network. Application Google service accounts must already exist before adding their Workload Identity bindings.

## Smallest instantiation

Replace the literal project/network-allocation examples in `minimal.tfvars`, then run:

```sh
tofu init
tofu plan -var-file=minimal.tfvars
tofu apply -var-file=minimal.tfvars
```

Only these values are required: `project_id`, `cluster_name`, `environment`, `region`, and `master_ipv4_cidr_block`. All other inputs have production-oriented defaults. Use `outputs.get_credentials_command` after arranging control plane network access.

To destroy intentionally, first apply with `deletion_protection = false`; `tofu destroy` alone does not bypass GKE deletion protection.

## Custom application pools

Pools are keyed by stable names. This example adds an on-demand pool for a namespace that needs more memory and a scale-to-zero Spot pool for interruptible batch jobs:

```hcl
application_node_pools = {
  general = {}

  memory = {
    machine_type   = "n2-highmem-4"
    min_node_count = 1
    max_node_count = 4
    labels         = { capacity = "high-memory" }
    taints = [{
      key = "capacity", value = "high-memory", effect = "NO_SCHEDULE"
    }]
  }

  batch = {
    machine_type   = "e2-standard-4"
    min_node_count = 0
    node_count     = 0
    max_node_count = 10
    spot           = true
    labels         = { capacity = "batch" }
  }
}
```

Do not put required replicas only on Spot nodes. Keep at least two appropriately distributed replicas, PodDisruptionBudgets, topology spread constraints, and resource requests in application manifests; node pool autoscaling and surge upgrades cannot make a single-replica workload highly available by themselves.

## Workload Identity for Google Cloud services

Create an application Google service account and grant it only its own application roles (for example, Pub/Sub publisher on one topic, Storage object access on one bucket, or `roles/cloudsql.client` for a Cloud SQL Auth Proxy sidecar). Then bind it to the Kubernetes identity:

```hcl
workload_identity_bindings = {
  orders_publisher = {
    namespace                    = "orders"
    kubernetes_service_account   = "orders-api"
    google_service_account_email = "orders-api@apps-prod-123456.iam.gserviceaccount.com"
  }
}
```

Create or annotate the Kubernetes service account during application onboarding (this module deliberately does not configure a Kubernetes provider):

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: orders-api
  namespace: orders
  annotations:
    iam.gke.io/gcp-service-account: orders-api@apps-prod-123456.iam.gserviceaccount.com
```

The pod must use that Kubernetes service account. No service account JSON key or broad permission on the node service account is needed.

## Upgrade notifications

Set `notification_pubsub_topic = "projects/PROJECT/topics/TOPIC"` to receive GKE upgrade events. Create the topic separately and grant its publisher permission to the project's GKE service agent (`service-PROJECT_NUMBER@container-engine-robot.iam.gserviceaccount.com`). Application Pub/Sub permissions remain separate.
