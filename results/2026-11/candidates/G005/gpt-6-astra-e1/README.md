# Production GKE Standard root module

A standalone OpenTofu root, with directly authored Google resources and no remote modules. Use one copy/state per cluster. This module owns the cluster, node pools, dedicated service accounts, additive IAM grants, and API enablement. It does **not** own the project, VPC, subnets, routes, NAT, application deployments, or organization policies.

## Quick start

Requirements: OpenTofu >= 1.6, Google provider 6.20–6.x (use the generated lock file), a billing-enabled project, and application-default credentials supplied by your environment. No credentials are stored in this module.

```sh
tofu init
# Copy minimal.tfvars to your cluster's tfvars and replace the illustrative values.
tofu validate
tofu plan -var-file=minimal.tfvars
tofu apply -var-file=your-cluster.tfvars
```

`minimal.tfvars` is the smallest example: all four required inputs have literal values. Its project ID is illustrative; replace it with the actual project before applying. A plan does not verify that the network exists or that the caller has apply permissions. See `examples/production.tfvars` for access, two pools, image pulls, and a workload identity.

For production, configure an access-controlled, encrypted, versioned remote state backend with locking before applying (for example, a separately provisioned GCS backend). Do not commit state, saved plans, credentials, or kubeconfigs. No backend is hard-coded so every cluster can have its own state location. Check the generated provider lock file into the deployment repository. Review replacements carefully: network, region, name, and CIDR changes may replace infrastructure. Create a new cluster and migrate workloads rather than replacing a live production cluster in place.

## Inputs operators must choose

| Input | Meaning |
| --- | --- |
| `project_id` | Existing project containing both the network and cluster |
| `cluster_name` | 2–24 character name; use a project-wide unique name because the node GSA is project-scoped |
| `environment` | `staging` or `prod`; selects `apps-staging` or `apps-prod` |
| `master_ipv4_cidr_block` | Unique unused RFC1918 `/28`, allocated with the network team |

`region` defaults to `us-central1`. For another US region, its subnet must already exist. Network references are constructed as:

- VPC: `projects/<project>/global/networks/apps-<environment>`
- Subnet: `projects/<project>/regions/<region>/subnetworks/apps-<environment>-gke-<region>`
- Existing secondary ranges: **`pods`** and **`services`**

The module intentionally does not import, resize, recreate, or modify network-team resources. It uses fully qualified references, so there are no network data-source calls during planning. The names and available capacity must be verified before apply.

## Network and access prerequisites — before apply

1. Allocate non-overlapping primary, secondary, and control-plane ranges. Check overlaps with peered networks, VPN/on-prem routes, other clusters, and existing control planes; syntax validation cannot detect them.
2. Provide Google API access for private nodes (Private Google Access and appropriate DNS/routes/firewall rules). GKE normally enables Private Google Access on a private cluster's same-project subnet; coordinate this service-managed behavior with the network team's desired state. Neither public node addresses nor a NAT gateway are created here.
3. Have the network team provide Cloud NAT or an approved egress proxy if workloads need public registries, third-party APIs, or other Internet destinations. Google API access alone does not provide general Internet egress. Prefer private Artifact Registry mirrors. Cloud SQL private-IP routing/private services access is also a separate network prerequisite.
4. Allow required GKE control-plane/node and node-to-node traffic. Hierarchical firewall policies must not block GKE-managed firewall rules. Some admission webhooks require additional control-plane-to-pod ports; coordinate those rules with the network team.
5. **Set `authorized_networks` to your real management/VPN/CI source ranges.** Private nodes and a private control-plane endpoint are the defaults. Authorized-network enforcement also applies to the private endpoint. With the minimal empty list, only GKE's automatically allowed cluster ranges can access it; it is intentionally not accessible from an arbitrary laptop. Establish VPN/Interconnect or a controlled management runner with routing to the private endpoint. Global private endpoint access is enabled, but does not itself create routes or connectivity.
6. If private management access is impossible, explicitly set `enable_public_endpoint = true` and supply trusted public egress CIDRs (normally `/32`s). Public access cannot be enabled with an empty allowlist. No `0.0.0.0/0` or Google-wide public allowlist is permitted. Changing endpoint exposure is a reviewed security decision.

The OpenTofu runner needs Google API access, not Kubernetes API access. After apply, use `tofu output -raw get_credentials_command` from an authorized connected host, with `gcloud` and `gke-gcloud-auth-plugin` installed. Authentication uses Google identity; client certificates and legacy ABAC are disabled. Cluster IAM and Kubernetes RBAC are separate from the source-network allowlist.

The provisioning identity needs permissions to enable services, create/manage GKE clusters, use the subnet, create service accounts and act as the node account, and manage the IAM grants it owns. Common provisioning roles include Kubernetes Engine Admin, Service Account Admin/User, Service Usage Admin, and Project IAM Admin, or a narrower custom role. Optional repository IAM grants require repository IAM permissions in that repository's project. These are privileged **provisioner** permissions, not roles to grant to product teams or workloads. Respect organization policies and existing GKE service-agent grants; this module does not replace project IAM policies.

## Built-in decisions

- **Regional GKE Standard**: replicated control plane; three node zones chosen by GKE unless at least three explicit in-region zones are supplied. No Autopilot and no lasting default pool.
- **One default on-demand pool**: `general`, `e2-standard-4`, 100 GiB balanced persistent boot disks, COS/containerd. All pools are shielded with Secure Boot and integrity monitoring. Spot/preemptible nodes are intentionally not offered for this production baseline.
- **Autoscaling**: default total minimum 3, total maximum 12 nodes across zones, with balanced scale-up. Initial creation is one node per zone; the autoscaler subsequently reconciles the configured totals. Each pool has its own total bounds, and at least one pool must be untainted. The autoscaler provides best-effort balance, not a guarantee of one node per zone at every instant. Changing autoscaler bounds does not make OpenTofu fight autoscaled node counts.
- **Managed lifecycle**: STABLE release channel, auto-repair, auto-upgrade. No pinned Kubernetes version that operators must babysit. REGULAR is available explicitly. Surge upgrades allow one extra node and zero unavailable nodes **per zone**. Keep quota, IP capacity, and disruption budgets compatible with upgrades. GKE can override maintenance restrictions for critical repairs/security updates.
- **Maintenance**: daily 06:00–12:00 UTC by default; start/end timestamps define a recurring window, not a one-off maintenance date. Custom RFC5545 recurrence must provide at least 48 hours in each rolling 32-day period in blocks of at least four hours. The module validates timestamp order/duration; GKE validates recurrence availability.
- **Networking**: VPC-native alias IPs with existing named ranges, private nodes, Dataplane V2 (built-in Kubernetes NetworkPolicy enforcement). No separate Calico/network-policy add-on is configured with Dataplane V2. HTTP load-balancing and HPA add-ons and the persistent disk CSI driver are enabled.
- **Keyless access to Google Cloud**: Workload Identity Federation and the GKE metadata server on every pool. No service-account keys. Host-network/privileged pods are not safe tenants and need special restrictions.
- **Node IAM**: dedicated per-cluster GSA with log writer, monitoring metric writer/viewer, and resource metadata writer only. No Editor or application access. `cloud-platform` OAuth scope is deliberately paired with narrow IAM, not used as an authorization grant. Private image pulls are granted only to repositories explicitly listed in `artifact_registry_repositories`.
- **Observability**: Cloud Logging for system/workload and control-plane components; Cloud Monitoring system/control-plane metrics; managed Prometheus; basic security posture and vulnerability scanning. Logging and metrics have usage costs. Configure retention, alert routing, SLOs, and budget alerts in the team's central observability stack; Prometheus application scraping still needs PodMonitoring/ClusterPodMonitoring resources.
- **Deletion safety**: `deletion_protection = true`. For intentional removal, set false, apply that change, back up/migrate workloads, then destroy. Shared APIs stay enabled. This guard protects cluster deletion, not removal of an individual pool from the map.

## Capacity and availability are shared responsibilities

Pool `min_nodes` / `max_nodes` are **total**, not per-zone. All pools use 64 max pods per node by default (configurable powers of two from 8–256). GKE normally reserves an entire `/25` pod block per 64-pod node, rather than only the addresses currently in use. Size the shared `pods` range for all clusters using it, maximum pools, surge nodes, and temporary bootstrap nodes. The short-lived default pool can use GKE's default 110 pods/node (`/24` allocation). Check primary node-IP capacity and `services` capacity as well.

A regional cluster does not make a single replica highly available. Teams must set resource requests/limits, at least three replicas where appropriate, zone topology-spread constraints/anti-affinity, HPA targets, and workable PodDisruptionBudgets. Size minimum capacity to sustain a zone loss or upgrade **before** demand requires scaling; default node sizes/counts are a starting floor, not a workload sizing guarantee. Regional persistent disks or application-level replication, backups, and tested restores are needed for stateful availability. The module does not create backup policies or promise an RPO/RTO.

Do not change an existing pool's immutable properties in place during a critical deployment. Add a differently named replacement pool, verify capacity, cordon/drain with appropriate disruption controls, then remove the old pool. Allow for both pools' quota/IP usage during migration.

## Workload access: Pub/Sub, Storage, Cloud SQL

Workload Identity is always enabled; the optional `workload_identities` map also creates a Google service account, binds exactly one namespace/Kubernetes-service-account pair to it with `roles/iam.workloadIdentityUser`, and optionally grants explicit project roles. Project basic roles (Owner/Editor/Viewer) are rejected.

```hcl
workload_identities = {
  orders-prod-worker = {
    namespace                  = "orders"
    kubernetes_service_account = "worker"
    project_roles              = ["roles/cloudsql.client"]
  }
}
```

Use the exported GSA email in separately managed, resource-scoped IAM for a particular Pub/Sub subscription (`roles/pubsub.subscriber`), topic (`roles/pubsub.publisher`), or bucket (`roles/storage.objectViewer`/`roles/storage.objectUser`). Prefer those narrow resource grants to project-wide data permissions. `roles/cloudsql.client` supports the Cloud SQL Auth Proxy/connector, but does not configure databases, network paths, or SQL authentication; IAM database authentication may also need `roles/cloudsql.instanceUser` and database users/grants.

Create the namespace and Kubernetes service account through the team's GitOps/bootstrap system, not through this root's apply:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: worker
  namespace: orders
  annotations:
    iam.gke.io/gcp-service-account: orders-prod-worker@YOUR_PROJECT.iam.gserviceaccount.com
```

Set `spec.serviceAccountName: worker` on the pod template and use standard Google client libraries/Application Default Credentials. Do not distribute JSON keys or use the node identity for applications. The annotation and IAM binding are both needed. Outputs expose exact annotations. If you already manage GSAs/IAM elsewhere, leave the map empty and configure Workload Identity bindings there instead. Direct federated-principal resource grants are also supported by GKE, but this module's helper implements the GSA impersonation pattern for broad client compatibility.

**Important project boundary:** clusters in one project share the `<project>.svc.id.goog` pool. The same namespace/KSA identity in another cluster in that project can use the same binding. Use project-wide namespace/KSA naming conventions and trusted cluster administrators, or separate projects for stronger identity isolation. Workload GSA map keys must be project-wide unique; do not give two cluster states ownership of the same GSA or IAM member.

## Shared-cluster tenant baseline

These are shared clusters for mutually trusted internal teams, not a hard security boundary between hostile tenants. Dataplane V2 enables enforcement but does **not** install default-deny policies. Before onboarding workloads, the platform GitOps bootstrap must:

- Create team namespaces with Pod Security Admission `restricted` enforcement/audit/warn labels (review and pin the Kubernetes policy version for upgrades).
- Assign namespace-scoped RBAC to team groups, without cluster-admin, node access, privileged pods, host networking, or cross-team secret access. Reserve privileged system exemptions for the platform team.
- Apply ResourceQuotas/LimitRanges so one team cannot exhaust cluster resources.
- Install default-deny ingress/egress NetworkPolicies and explicit allows for DNS, required cross-team services, monitoring, and approved Google APIs. Permit the GKE metadata server (`169.254.169.254:80` with Dataplane V2) where Workload Identity is required; test policy behavior with the installed GKE version. Account for provider-specific metadata/control-plane traffic before rollout.
- Configure service account identities per application, ingress TLS/access policies, admission controls, audit routing, alerts, backup schedules, and restore tests.

Bootstrap is deliberately a separate stage: no Kubernetes or Helm provider is coupled to creation of an initially unreachable private endpoint. Google-managed encryption at rest is used; customer-managed application-layer secret encryption, Binary Authorization policies, and regulated-compliance controls require a separately reviewed extension, not an implied guarantee here.

## Operating the root

All configuration variables have types and descriptions in `variables.tf`. Optional maps use stable keys; deleting a pool, repository binding, or workload identity key plans its removal. APIs are project-wide and remain enabled on destroy; if another state centrally owns API activation, consolidate/import ownership rather than managing the same API from competing states. IAM uses additive members rather than authoritative bindings; avoid overlapping authoritative IAM ownership elsewhere.

The outputs provide cluster ID/location, network/subnet references, node and workload GSA emails, annotation maps, pool names, and a credentials command. Endpoint and CA outputs are marked sensitive to reduce accidental log exposure, but state still contains cluster connection metadata and must be protected. No user tokens or kubeconfig are generated.

Plan/validate are necessary checks, not an apply test or proof of production readiness. Review plans, ensure network/IAM prerequisites and quota, apply in staging, bootstrap tenant controls, and validate access, pod-to-Google authentication, zone disruption behavior, upgrade drain behavior, and restore procedures before promoting to production.
