# Production GKE Standard root module

This root creates **one regional GKE Standard cluster** in an existing project. Run a separate root/state per cluster. There are no remote modules, Kubernetes-provider bootstrap dependencies, VPC creations, or service-account keys.

## Quick start

1. Copy `minimal.tfvars`, replacing the example project, cluster name, region, CIDRs and environment with real values. The project must be the project that owns the environment VPC. The example values are illustrative, not a project or subnet this module provisions.
2. Authenticate OpenTofu with Application Default Credentials, preferably through CI workload identity federation or service-account impersonation, not a downloaded key.
3. Run:

   ```sh
   tofu init
   tofu fmt -check
   tofu validate
   tofu plan -var-file=minimal.tfvars -out=cluster.plan
   tofu apply cluster.plan
   ```

4. From an authorized private network, run the `get_credentials_command` output. Install `gke-gcloud-auth-plugin`. Google IAM authentication and appropriate Kubernetes RBAC are still required; network access is not authorization.
5. Bootstrap namespaces, quotas, RBAC, admission policies, NetworkPolicies, alerting and backup/restore configuration with your GitOps tooling. This module deliberately does not manage Kubernetes resources in the same apply as cluster creation.

Use an access-controlled, versioned remote state backend with locking for production; configure your organization's bucket/prefix at initialization. The root leaves backend choice to the operator and does not create a backend bucket. State and saved plans must be protected even though no private keys are created. Commit the provider lock file.

## Required inputs

| Input | Meaning |
| --- | --- |
| `project_id` | Existing project ID, not number; owns the VPC and cluster |
| `cluster_name` | Unique cluster name, 2–40 lower-case characters |
| `environment` | `staging` or `prod` |
| `region` | US region with at least three zones |
| `master_ipv4_cidr_block` | Unique, non-overlapping RFC1918 /28 allocated by the network team |
| `control_plane_authorized_cidrs` | Map of descriptive names to private runner/VPN/bastion CIDRs; nonempty |

The network is `apps-<environment>`. The regional subnet is `apps-<environment>-gke-<region>`. Existing secondary ranges **must** be named `pods` and `services`. Data sources check ownership, range names and Private Google Access without modifying network resources. These checks may run during apply when project APIs are first enabled.

### Network prerequisites and responsibilities

* The network team must enable Private Google Access on the existing subnet. This is checked, not silently changed.
* Reserve the master /28 across connected VPCs, on-premises routes, secondary ranges and other cluster master ranges. The module checks its format, not all route overlap relationships.
* Nodes have **no public IPs**. Private Google Access enables Google API access. For Docker Hub, third-party APIs, downloads and other public destinations, the network team must provide controlled Cloud NAT/proxy egress and appropriate DNS, routes and firewall policy. This module does not install a VPC-wide NAT that might conflict with network ownership.
* The Kubernetes API is **private-only**. It permits listed CIDRs on the private endpoint, with global private master access enabled for runners in other regions. Supply a real reachable CIDR and arrange VPN/Interconnect/bastion connectivity and control-plane return routes where required. Ordinary public Cloud Shell or a public CI runner cannot connect. The OpenTofu Google provider itself uses Google APIs and does not need direct Kubernetes API connectivity.
* GKE creates its normal cluster-managed firewall rules. Organization/hierarchical firewall policy must allow the documented GKE control-plane, node, health-check and webhook traffic; do not blanket-block the control-plane /28. NetworkPolicy alone does not secure node/host-network traffic.
* Size the existing primary and secondary ranges for all clusters sharing them, maximum pool size, GKE allocations and upgrade surges. Each durable node has at most 64 Pods and ordinarily consumes a /25 Pod block. The temporary bootstrap pool can use the GKE default Pod allocation, so reserve headroom for it too.

## Defaults and design choices

* **Regional control plane**, with nodes in the first three alphabetically sorted UP zones returned for the region. Plan reviews must catch zone-list changes; a change in regional availability can change pool placement. No single-zone shortcut for staging.
* One `general` pool: on-demand `e2-standard-4`, **one minimum / three maximum nodes per zone**, hence 3–9 nodes in total. A minimum node in each zone provides a baseline, not a guarantee that workloads fit during a zone outage. Measure capacity and increase minima/maxima before admitting production workloads. Quota must include surge and replacement capacity.
* Separate durable node pools, no default pool retained. All have autoscaling, auto-repair, auto-upgrade, COS_CONTAINERD, balanced persistent disks (100 GiB minimum), Shielded VM integrity monitoring and Secure Boot. No Spot nodes for the production baseline.
* `REGULAR` release channel; GKE chooses the supported version, rather than a stale pinned patch. Recurring maintenance is Saturday and Sunday 00:00–24:00 **UTC**, anchored by the RFC5545 start/end dates in `main.tf`. Surge upgrades allow one extra node and zero unavailable nodes **per zone**. Maintenance windows are best-effort, not a promise that emergency upgrades never happen outside them. PodDisruptionBudgets must permit safe draining.
* VPC-native aliases on existing ranges; Dataplane V2 provides Kubernetes NetworkPolicy enforcement without the incompatible legacy network-policy addon. **There are no default-deny policies until GitOps installs them.**
* Workload Identity Federation is enabled at cluster and node-pool level. A dedicated node service account has only `roles/container.defaultNodeServiceAccount` for GKE node telemetry and `roles/artifactregistry.reader` for same-project image pulls. The OAuth scope is `cloud-platform`; actual permissions are restricted by IAM, not scopes. Cross-project registry grants belong with the registry owner. Workloads must not receive node identity privileges.
* Legacy ABAC, legacy metadata endpoints, client certificates, public nodes and public API access are disabled. Node disks and GKE data use Google-managed encryption; no customer-managed encryption key dependency is introduced.
* System, workload and control-plane logs, system metrics, managed Prometheus and basic security/vulnerability posture scanning are enabled. Budget for telemetry/scanning, retention and cardinality. GCP audit logs retain their platform behavior; enable any required Data Access audit logging at the project/org level. Monitoring data is not an alerting policy: create SLOs, alerts and routing in the platform observability stack.
* HPA, HTTP load balancing and PD CSI are enabled. An application's public Ingress can still create a public frontend—private nodes do not make every application private. Enforce ingress policy with admission controls as appropriate.
* Deletion protection defaults to true. To intentionally delete, set `deletion_protection = false`, apply that change, then destroy using the same variable file. API enablement persists after destroy to avoid disrupting other project users. Cluster deletion is not a data backup strategy.

### Pool overrides

```hcl
node_pools = {
  general = {
    machine_type       = "e2-standard-8"
    min_nodes_per_zone = 2 # 6 total minimum
    max_nodes_per_zone = 6 # 18 total maximum
    disk_size_gb       = 150
    labels             = { workload-class = "general" }
  }
}
```

Pool names identify resources; renaming/removing a pool deletes it. Machine/disk changes can roll or recreate nodes: review every plan, maintain spare capacity, and migrate workloads between pools when necessary. The module intentionally does not set `node_count` or ignore autoscaler state, avoiding fights with autoscaling.

## Keyless access to Pub/Sub, Storage and Cloud SQL

No blanket product permissions are granted to nodes. Each Kubernetes ServiceAccount (KSA) should have its own least-privilege GCP service account (GSA), or use direct Workload Identity resource IAM bindings where the target API supports them.

Optional `workload_identities` creates GSAs and `roles/iam.workloadIdentityUser` bindings for explicitly named KSAs. It can also grant explicitly requested **project-wide** roles; the default is no product roles. Prefer resource IAM (a particular bucket or subscription) managed alongside that resource:

```hcl
workload_identities = {
  orders = {
    namespace                  = "orders"
    kubernetes_service_account = "orders-api"
    # Cloud SQL IAM connectivity; database authentication/SQL grants remain separate.
    project_roles = ["roles/cloudsql.client"]
  }
}
```

After apply, use the `workload_identities` output to create/annotate the KSA in GitOps:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: orders-api
  namespace: orders
  annotations:
    iam.gke.io/gcp-service-account: REPLACE_WITH_OUTPUT_EMAIL
```

Set the Pod's `spec.serviceAccountName: orders-api`. Use Google client-library ADC (or the Cloud SQL Auth Proxy/connector); never mount a GSA JSON key. For Pub/Sub, grant e.g. `roles/pubsub.subscriber` on the intended subscription; for Storage, `roles/storage.objectViewer` on the intended bucket. For Cloud SQL, separately configure private connectivity, Cloud SQL APIs, database users/authentication and SQL privileges. Workload APIs and databases/buckets/topics are not provisioned here. The module enables only cluster/identity/telemetry and image registry APIs.

**Same-project trust boundary:** GKE identity pools are project-scoped, not cluster-scoped. The same namespace/KSA name in another cluster of this project can match the same impersonation binding. Reserve names project-wide or use separate projects for mutually untrusted tenants. Kubernetes namespaces alone are not hard tenant isolation. For sharing a cluster, enforce namespace-scoped RBAC (including restrictions on selecting/creating service accounts), resource quotas, Pod Security Admission `restricted` where possible, default-deny ingress/egress policies with explicit DNS/API allowances, and restrictions on privileged/host-network/hostPath workloads. Privileged/host-network access can bypass normal workload identity isolation. The project should not give the default Compute Engine service account automatic Editor privileges.

## Production operating checklist

* Replicas spread across zones using topology spread constraints/anti-affinity, appropriate requests/limits, HPA and tested PDBs. A regional cluster alone does not make a single Pod or zonal disk highly available.
* Cloud SQL HA, storage recovery, backups and restore tests must be designed separately. Consider Backup for GKE or application-native backups before storing production data.
* IAM/RBAC onboarding and periodic access review, security findings triage, audit-log retention and monitoring alerts have explicit owners.
* Test module/provider upgrades in staging first, review disruption and replacements, and keep state secured. Monitor IP utilization and quotas before scaling. Regional resilience is not cross-region disaster recovery.
* The deploying principal needs Service Usage administration (with Service Usage API already available), GKE/Compute read and cluster-management permissions, service-account creation and `actAs`, project IAM modification for the additive role grants, and service-account IAM modification. Use a dedicated platform automation identity, not basic project Editor. Product deployers do not need these provisioning privileges.

## Outputs

Cluster name/location, private endpoint, sensitive base64 cluster CA, a `gcloud ... --internal-ip` command, node pool names, node service account email, workload pool, and per-workload GSA annotation details are exposed in `outputs.tf`.
