# Regional GKE Standard baseline

Standalone OpenTofu root; no remote modules or Kubernetes provider. One state per cluster. Requires OpenTofu >= 1.9 and Google provider 6.20–7.x; retain the generated provider lock file. Credentials come from Application Default Credentials / the execution environment, never tfvars.

## Start

```sh
tofu init
tofu plan -var-file=minimal.tfvars
tofu apply -var-file=minimal.tfvars
tofu output -raw get_credentials_command
```

`minimal.tfvars` provides literal example values for all five required inputs. Replace its project and allocated control-plane range with your real values before applying. The example expects `apps-prod` and `apps-prod-gke-us-central1` in `platform-prod-12345`, with existing `pods` and `services` secondary ranges. This module neither creates nor takes ownership of networking. Initial plans defer network lookups until project APIs are enabled; a successful initial plan does not prove those existing resources or their IP capacity exist. Apply validates subnet ownership and named ranges.

Required inputs: `project_id`, `cluster_name` (2–24 characters, project-unique), `environment` (`staging` or `prod`), `region` (US), `control_plane_cidr` (allocated non-overlapping RFC1918 /28). Same secure defaults apply to staging and prod. Other inputs customize machine size, total autoscaling bounds, labels, UTC maintenance times, and deletion protection. Defaults are deliberately small, not a workload sizing recommendation.

## Design and operations

* **Regional, not zonal:** replicated regional control plane; GKE chooses three node zones. A separately managed, on-demand general-purpose pool starts with one node per zone. Autoscaling uses **total** minimum 3 / maximum 9 nodes, balanced across zones on a best-effort basis (not a strict per-zone floor). Nodes are e2-standard-4, COS/containerd, 100 GiB balanced persistent boot disks. Max 64 pods/node. Change bounds and machine type based on requests, disruption tolerance and quota. There are no Spot nodes.
* **Upgrades:** REGULAR release channel, automatic repair and upgrades, surge 1 and unavailable 0 **per zone**. Reserve quota and IPs for up to three surge nodes plus temporary bootstrap nodes. Daily maintenance defaults to 05:00–09:00 UTC, exceeding GKE's 48 hours/32 days requirement. Customize for your traffic pattern; emergency maintenance may override windows. Versions intentionally follow the supported release channel instead of aging pinned versions. Test changes in staging first.
* **Private networking:** nodes have no external IPs and the Kubernetes control-plane public endpoint is disabled. Global private endpoint access permits routed administration from other regions; it does not establish connectivity. There is no public-access escape hatch. VPC-native routing reuses the named secondary ranges; Dataplane V2 implements Kubernetes NetworkPolicy without adding Calico or the incompatible legacy network-policy configuration.
* **Identity and hardening:** Workload Identity Federation and GKE metadata server on all nodes, no service-account keys, Shielded nodes with Secure Boot and integrity monitoring, legacy metadata disabled, no legacy ABAC or client certificates. Google IAM/OIDC credentials and Kubernetes RBAC authorize administrators. A dedicated node service account has only logging/monitoring/resource metadata writes or reads and project-local Artifact Registry read, not Editor or application data access. The cloud-platform OAuth scope is intentional: IAM restricts access. Project-wide Artifact Registry read is a baseline convenience; use separate repositories/projects and repository-level grants if image isolation is required. Cross-project registries need explicit external grants. Google-managed encryption at rest is used, not customer-managed keys.
* **Visibility:** system, workload and control-plane logs; system metrics; managed Prometheus; basic security posture/vulnerability scanning; GKE cost allocation. These have ingestion/storage costs. Prometheus application collection needs PodMonitoring resources. Configure alerting, log retention, budgets and on-call routing separately. HPA, VPA and persistent-disk CSI are enabled; applications still supply autoscaling policies. Do not apply VPA CPU/memory updates and resource-utilization HPA to the same workload without a compatible design.
* **Safe lifecycle:** deletion protection is enabled. Intentional destruction requires a separate successful apply setting `deletion_protection = false`, then destroy using that same tfvars. Back up workload data first. Project APIs are never disabled on destroy; IAM grants are additive, not authoritative policies. No node count is continuously reconciled against the autoscaler.

## Networking and bootstrap prerequisites

The network team must arrange:

1. The VPC/subnet/ranges above, sufficient unused Pod and Service addresses, and a non-overlapping /28 control-plane allocation. Check overlap with all subnet, peering, VPN and other control-plane ranges; local syntax validation cannot check your topology. With 64 pods/node, GKE normally reserves a /25 pod block per node; allow maximum size, surge and other clusters sharing the range.
2. Private Google Access and appropriate Google API DNS/routes/firewall access for private nodes (or a supported equivalent egress path). GKE may enable Private Google Access for private clusters in a non-Shared VPC, but verify it rather than relying on that side effect. For internet/package/external registry access, provide network-owned Cloud NAT or an egress proxy with the requisite routes. This module does **not** create a competing NAT/router, alter subnet configuration or change network-owned firewall rules.
3. VPN/Interconnect or an administrative host in the VPC, routes to the private control plane, and allowed TCP 443. Peering is not transitive: validate the actual administrator/CI path. The bootstrap OpenTofu runner uses Google APIs and need not contact Kubernetes; subsequent kubectl/GitOps runners must have private access. GKE creates its managed cluster firewall rules; restrictive hierarchical/VPC policies must allow required node/control-plane communication, DNS and workload Google API access. Admission webhooks on nonstandard ports can require network-team firewall changes.

The provisioning identity needs API enablement, cluster management, network read/use, service-account creation/actAs, and additive project IAM management permissions. Use a dedicated deployment identity, not workload credentials, and comply with organization policies and regional quota. Store state remotely in a protected, versioned GCS bucket with tightly restricted access and locking; backend bootstrap is intentionally outside this root. State includes cluster metadata/certificate material and must not be public. Do not check local state or credentials into version control.

Services are project-scoped but enabled idempotently here. With multiple independent cluster states, designate one owner for shared API enablement if importing/consolidating state; never allow API disabling on cluster teardown. Application APIs such as Pub/Sub and Cloud SQL are enabled by their owning application infrastructure, not by this baseline.

## Workloads accessing Google Cloud

Use a dedicated Kubernetes ServiceAccount per workload. Do **not** add Pub/Sub, Storage or SQL privileges to the node service account. Prefer direct Workload Identity Federation IAM grants scoped to the specific topic/subscription/bucket or other target, using this principal form (PROJECT_NUMBER is numeric):

```
principal://iam.googleapis.com/projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/PROJECT_ID.svc.id.goog/subject/ns/NAMESPACE/sa/KSA_NAME
```

Where a service requires Google service-account impersonation, create a dedicated Google service account, grant it only the needed resource roles, grant `roles/iam.workloadIdentityUser` on that account to `serviceAccount:PROJECT_ID.svc.id.goog[NAMESPACE/KSA_NAME]`, and annotate the Kubernetes service account with `iam.gke.io/gcp-service-account=GSA_EMAIL`. Set the pod's `serviceAccountName`. IAM Credentials and STS APIs are enabled. Use Cloud SQL Auth Proxy/connectors with appropriate SQL IAM and network connectivity; authentication alone does not open a route to private SQL instances. All application identities and grants belong in application infrastructure, not this cluster's node identity.

**Important:** Workload Identity pools are project-wide. The same namespace/service-account pair in two clusters in this project can represent the same IAM identity. Use globally unique workload namespace/account names or IAM conditions incorporating cluster identity where supported. Do not assume clusters within one project are an IAM isolation boundary.

## Shared-production responsibilities

This module supplies infrastructure, not automatic tenant isolation. Before onboarding teams, the platform's GitOps/bootstrap layer must create per-team namespaces, least-privilege RBAC (no general cluster-admin), ResourceQuota/LimitRange, Pod Security Admission `restricted` enforcement with audited system exceptions, and default-deny ingress/egress NetworkPolicies with explicit DNS, metadata/WIF and service dependencies allowed. Dataplane V2 makes policies enforceable but does **not** install a default deny by itself. Only trusted platform administrators should manage admission policy, cluster-scoped objects or privileged workloads. Host-networked/privileged workloads have additional identity and escape risks; don't permit them for tenants. Namespaces are not a hard security boundary for mutually untrusted tenants; use separate clusters/projects in that case.

Workloads must use multiple replicas, topology spread/anti-affinity across zones, realistic resource requests, readiness probes and disruption budgets. Autoscaling and surge cannot guarantee application uptime when those are absent. Configure regional/replicated storage where needed; zonal disks remain zonal. A regional cluster is not regional disaster recovery: implement workload/data backups, test restores, and deploy across regions for region-failure requirements. No backup plans, app-specific IAM, SQL instances, Pub/Sub resources, buckets, ingress certificates, DNS records or Kubernetes tenant resources are created here.
