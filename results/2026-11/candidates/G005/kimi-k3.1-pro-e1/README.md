# Production GKE Standard clusters

This root module creates one regional **GKE Standard** cluster in an existing, network-team-owned VPC. It is intentionally opinionated about cluster security and operability while leaving application identities, node capacity, and cluster-specific addressing configurable.

No remote modules or Kubernetes-provider resources are used. In particular, the module does not need `kubectl` access to apply, which is important when the control-plane endpoint is private.

## Quick start

1. Copy `minimal.tfvars` for the new cluster and replace every literal with the real cluster values. `project_number` must be the numeric project number corresponding to `project_id`, not another project ID.
2. Coordinate a unique `/28` control-plane CIDR with the network team.
3. Ensure the network prerequisites below are met.
4. Run:

   ```sh
   tofu init
   tofu plan -var-file=minimal.tfvars
   tofu apply -var-file=minimal.tfvars
   ```

The six required inputs are:

| Input | Purpose |
|---|---|
| `project_id` | Project containing both the cluster and existing VPC |
| `project_number` | Numeric project number, used for the Google-managed GKE service-agent identity without a plan-time lookup |
| `cluster_name` | Cluster name and supporting-resource prefix |
| `environment` | `staging` for `apps-staging`, or `prod` for `apps-prod` |
| `region` | US region; a regional cluster is created, not a zonal cluster |
| `master_ipv4_cidr_block` | Unique, non-overlapping `/28` for the private control plane |

All other inputs have production-oriented defaults. See `variables.tf` for the complete interface and validation rules.

## Network contract

For `environment = "prod"` and `region = "us-central1"`, the module references:

- VPC: `apps-prod`
- Subnet: `apps-prod-gke-us-central1`
- Pod secondary range: `pods`
- Service secondary range: `services`

For staging, the VPC and subnet prefix are `apps-staging`. The resources must already exist in `project_id`; the module never creates, deletes, or changes them. References are deterministic self-links rather than data sources, so planning does not require network-read API calls. GKE validates the subnet and secondary-range names during apply.

The network team must also provide:

- Enough pod and service address capacity for a multi-team cluster. The default node pools permit at most 64 pods per node.
- A unique control-plane `/28` that does not overlap routed networks.
- Routing to Google APIs and image repositories for nodes without external IPs. Private Google Access on the subnet is the usual choice; an equivalent Private Service Connect/NAT design can also work.
- Private control-plane access through a bastion, VPN, Interconnect, or another connected network when `enable_private_endpoint = true` (the default). Global private-endpoint access is enabled by default for cross-region administration.
- Any organization-specific egress/firewall rules. GKE still creates its required cluster firewall rules through its service agent.

If a public control-plane endpoint is explicitly selected, populate `master_authorized_networks`; do not expose an unrestricted endpoint.

## What the module standardizes

### Resilience and lifecycle

- Regional control plane and regional node placement across the region's default zones; `node_locations` can select specific zones.
- Two default, separately managed node pools:
  - `system`: one to three `e2-standard-2` nodes **per zone**, with a `CriticalAddonsOnly=true:NoSchedule` taint.
  - `applications`: one to six `e2-standard-4` nodes **per zone**, without that taint.
- Per-pool autoscaling, automatic repair, automatic upgrades, balanced persistent disks, and surge upgrades (`max_surge = 1`, `max_unavailable = 0`).
- `REGULAR` release channel, a daily four-hour maintenance window starting at 03:00 UTC by default, and upgrade/security notifications on a dedicated Pub/Sub topic.
- Node-local DNS cache, HTTP load balancing, horizontal pod autoscaling, vertical pod autoscaling, persistent-disk CSI, GCS FUSE CSI, Gateway API, and the Backup for GKE agent.
- System and workload logs, system metrics, managed Prometheus, advanced Dataplane V2 metrics, and GKE cost allocation.

A node-pool map supplied by the caller **replaces the whole default map**. Pool autoscaling limits are per zone. For example, the default application pool has a regional baseline of three nodes in a three-zone region, not one. Use `spot = true` only for pools whose workloads tolerate interruption. Do not put critical system workloads only on Spot capacity.

Backup for GKE's agent is not itself a backup. Create protected-application selections and backup plans separately for each stateful application, and test restores. Attach subscriptions and alerting to `cluster_notifications_topic`; a topic without a subscriber does not page anyone. Applications remain responsible for pod disruption budgets, topology spread, replicas, and health checks.

### Security

- Private nodes are mandatory; the control-plane endpoint is private by default.
- VPC-native networking uses the network team's named secondary ranges.
- GKE Dataplane V2 and Kubernetes NetworkPolicy enforcement are enabled. Namespaced default-deny and allow policies are deliberately managed with the applications/platform baselines, not by an apply-time Kubernetes provider.
- Shielded nodes use secure boot, integrity monitoring, Container-Optimized OS with containerd, GKE Metadata Server, and disabled legacy metadata endpoints.
- Workload Identity is enabled. Nodes use a dedicated service account with only observability and Artifact Registry read roles, plus any explicitly requested infrastructure roles. Application IAM must not be added to nodes.
- Kubernetes Secrets receive application-layer encryption with a cluster-dedicated regional Cloud KMS key and 90-day key rotation. Only the GKE service agent receives encrypt/decrypt permission on that key.
- Legacy ABAC is disabled, security-posture configuration audits and basic vulnerability scanning are enabled, and deployments use the project's Binary Authorization policy.
- Cluster deletion protection defaults to `true`; the KMS key also has `prevent_destroy` protection.

Binary Authorization and workload vulnerability scanning are integrations, not substitutes for policy. The platform team should centrally maintain the project's Binary Authorization policy/attestors and triage security-posture findings. Likewise, NetworkPolicy support does not create policies automatically.

The module enables required Google APIs and leaves them enabled on destroy. It grants IAM with non-authoritative member resources rather than replacing project or service-account IAM policies. The identity applying the module needs sufficient Service Usage, GKE, Compute/network reference, IAM, KMS, and Pub/Sub permissions. The module also grants `roles/container.serviceAgent` to the standard Google-managed GKE robot.

## Node-pool customization

Example `tfvars` fragment:

```hcl
node_pools = {
  system = {
    machine_type   = "e2-standard-2"
    min_node_count = 1
    max_node_count = 3
    taints = [{
      key    = "CriticalAddonsOnly"
      value  = "true"
      effect = "NO_SCHEDULE"
    }]
    labels = { workload = "system" }
  }

  applications = {
    machine_type      = "n2-standard-4"
    min_node_count    = 1
    max_node_count    = 8
    max_pods_per_node = 64
    tags              = ["product-workloads"]
    labels            = { workload = "applications" }
  }

  batch = {
    machine_type   = "e2-standard-8"
    min_node_count = 0
    max_node_count = 10
    spot           = true
    labels         = { workload = "batch" }
    taints = [{
      key    = "workload"
      value  = "batch"
      effect = "NO_SCHEDULE"
    }]
  }
}
```

When replacing the default pools, retain an untainted pool or give workloads suitable tolerations. A scale-to-zero pool cannot run a workload until cluster autoscaling can create compatible capacity.

## Application access to Google Cloud

`workload_service_accounts` creates application-specific Google service accounts and binds Kubernetes identities to them. It does **not** create Kubernetes service accounts. Example:

```hcl
workload_service_accounts = {
  "orders-api-prod" = {
    project_roles = [
      "roles/cloudsql.client",
      "roles/pubsub.publisher",
    ]
    kubernetes_service_accounts = [
      "orders/orders-api",
    ]
  }
}
```

The product team then creates its Kubernetes service account using the email exposed in the `workload_service_accounts` output:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: orders-api
  namespace: orders
  annotations:
    iam.gke.io/gcp-service-account: orders-api-prod@apps-platform-prod.iam.gserviceaccount.com
```

Pods using that Kubernetes service account can obtain Google credentials through Workload Identity. They do not need service-account key files, node credentials, or a broad node OAuth/IAM grant. The node OAuth scope is `cloud-platform`, but IAM and GKE Metadata Server constrain what can actually be used.

`project_roles` is convenient but deliberately defaults to empty. Grant only what the application needs. Prefer topic-, subscription-, bucket-, or instance-level IAM in the service-owning configuration over broad project roles whenever supported; the output provides each Google service-account email for those external bindings. In particular:

- **Pub/Sub:** grant publish only on required topics and consume only on required subscriptions where practical.
- **Cloud Storage:** grant object access on the specific bucket, not across every project bucket. GCS FUSE CSI is already enabled for workloads that need filesystem semantics.
- **Cloud SQL:** grant the Cloud SQL client permission and use the Cloud SQL Auth Proxy or Language Connector with Workload Identity. Database users/grants and any private-services networking remain application/network concerns.

Application API enablement (apart from cluster-owned integrations) and backup policies should stay with the relevant service/application configuration.

## Operations and teardown

- Use `cluster_endpoint` and the sensitive `cluster_ca_certificate` output for Kubernetes clients. With the default private endpoint, run those clients from an authorized private location.
- Use `rbac_security_group` only after configuring the required Google group; map groups and product-team namespaces through Kubernetes RBAC separately.
- Review release-channel upgrades and subscribe operations tooling to the notification topic. Test stateful workloads with surge upgrades and appropriate PDBs.
- Keep `deletion_protection = true` during normal operations. For intentional teardown, first set it to `false` and apply. The protected KMS key must be handled explicitly after dependent resources are removed; Cloud KMS key destruction is scheduled by Google Cloud rather than immediate.
- APIs are not disabled on teardown because other clusters and applications in the shared project may depend on them.
