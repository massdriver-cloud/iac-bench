# Regional GKE Standard root module

A directly applied OpenTofu root, with no remote modules. One state per cluster. It never creates or takes ownership of the network team's VPC, subnet, routes, NAT or secondary ranges.

## Apply

1. Set up a secured, versioned remote state backend and state locking according to platform policy (backend credentials must not be committed). State is sensitive. This root deliberately leaves the backend selection to deployment tooling.
2. Authenticate with Google Cloud using short-lived ADC / workload federation. The deployment identity needs permission to enable project APIs, create GKE clusters/node pools and service accounts, manage the narrow IAM grants in this root, and use the existing subnet. Do not run as the node identity.
3. Copy/edit `minimal.tfvars`: project ID, cluster name and environment are required. The checked-in project ID is an example, not a project this module creates. Default region is `us-central1`.
4. Run:

   ```sh
   tofu init
   tofu plan -var-file=minimal.tfvars
   tofu apply -var-file=minimal.tfvars
   ```

### Network contract (confirm with the network team before applying)

* Existing project-local VPC `apps-prod` or `apps-staging`, and subnet `<vpc>-gke-<region>` with `pods` and `services` secondary ranges. The root checks the range names and network membership. It does not resize or allocate them. Budget pod space for 110 pods per node (GKE's usual default), maximum pool sizes and upgrade surge; also budget node IPs.
* **Private Google Access must already be enabled** on the subnet; an apply-time precondition checks this. Private nodes have no external IPs. Firewall/routing/DNS must permit Google API access, GKE control-plane communication, inter-node/pod traffic and required egress. GKE manages its own normal cluster firewall rules; organization policies must allow them.
* Choose an unused RFC1918 control-plane `/28` via `control_plane_cidr`. The default `172.16.0.0/28` is only a starting point: confirm no subnet, secondary range, peering, VPN, on-premises or other control-plane overlap. This module cannot discover every connected network.
* Operators and any Kubernetes/GitOps automation need routed private control-plane connectivity (for example a management VM in the VPC or an appropriately configured VPN). No public Kubernetes API is enabled. Global private endpoint access allows cross-region clients, not arbitrary transit across peerings. Use `get_credentials_command` output with `gke-gcloud-auth-plugin`, then authorize users through least-privilege IAM/RBAC. This root needs Google API access, not Kubernetes API connectivity, to create the cluster.
* Network-owned Cloud NAT or an approved egress proxy is needed if workloads must contact the public Internet. This root intentionally does **not** create potentially conflicting NAT on a shared subnet. Private Google Access handles supported Google APIs, not general Internet egress. Configure private service connectivity, DNS and firewall access separately for private-IP Cloud SQL. Creating a cluster does not create databases, topics or buckets.

## Defaults and operational model

* Standard (not Autopilot), regional control plane and three node zones. The first three available zones are chosen by default; pin `node_locations` to three explicit zones for long-lived predictable placement. Zone changes can cause disruptive pool updates. Regional HA is not cross-region disaster recovery.
* A separate on-demand `general` node pool, `e2-standard-4`, COS/containerd, 100 GiB balanced persistent boot disks. Autoscaling defaults to **3–9 total nodes across zones**, balanced placement. Additional pools support sizes, labels and taints. Minimum three nodes is not a guarantee that Kubernetes spreads every workload. Reserve quota and IPs for regional upgrades (surge one per zone) and a zone outage. Set maxima to fit application capacity and budgets. Machine types must exist in all selected zones.
* Regular release channel; automatic node upgrades and repair. No hardcoded Kubernetes minor version to become stale. Zero planned unavailable nodes and one surge node per zone. Daily 09:00–13:00 UTC maintenance satisfies GKE's maintenance availability requirement; override `maintenance_window` for local schedules. GKE may perform emergency maintenance outside the window. APIs remain enabled after destroy because they are shared project resources.
* VPC-native networking and Dataplane V2 (NetworkPolicy enforcement without a separate Calico configuration), private nodes and control plane, Shielded Nodes with Secure Boot and integrity monitoring, no legacy ABAC or client certificate issuance, GKE metadata server and Workload Identity Federation.
* Dedicated node service account with `roles/container.defaultNodeServiceAccount` for GKE node telemetry, **not** Editor or application-data access. The cloud-platform OAuth scope is constrained by IAM, not an application credential. No service account keys are created. App Pods must not use node identity.
* System/workload Cloud Logging, system Cloud Monitoring, managed Prometheus and basic security posture/vulnerability scanning are enabled. Configure PodMonitoring resources, actionable alert policies, notification destinations, log retention and cost controls in platform observability tooling. Managed Prometheus and workload logging can incur material ingestion charges.
* HPA, VPA support, HTTP load balancing, Gateway API, DNS cache and PD CSI driver enabled. Autoscaling workloads still need resource requests and HPA/VPA objects; do not put HPA and VPA in control of the same resource without a deliberate configuration.
* Cluster deletion protection is on. Intentional deletion requires first applying `deletion_protection = false`, then destroying. Removing the flag from config is not sufficient to delete. This is not protection from deleting application resources through Kubernetes.

## Application identities and Google Cloud access

Workload Identity Federation is always enabled. Prefer direct, resource-scoped federated IAM grants where the target service supports them. A KSA's principal uses this form (the numeric project number is distinct from its project ID):

```
principal://iam.googleapis.com/projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/PROJECT_ID.svc.id.goog/subject/ns/NAMESPACE/sa/KSA
```

For APIs/tools that need Google service account impersonation, optionally declare:

```hcl
workload_identities = {
  orders = {
    namespace                  = "orders-prod"
    kubernetes_service_account = "orders-api"
  }
}
```

This creates a dedicated Google service account and grants only that KSA `roles/iam.workloadIdentityUser` on it. Deployment tooling creates the namespace/KSA and annotates it with `iam.gke.io/gcp-service-account=<workload_service_accounts["orders"]>`. It must also set the Pod's `serviceAccountName`. No Kubernetes provider credentials or application resources are mixed into this infrastructure root.

Grant the resulting GSA only the needed roles on the specific Pub/Sub topic/subscription, storage bucket or other resource in the service-owning configuration. For Cloud SQL, arrange `roles/cloudsql.client` (and `roles/cloudsql.instanceUser` if using IAM database authentication), database-level grants and connectivity separately; IAM alone does not authorize SQL queries. This root intentionally grants no workload data roles or project-wide Editor permissions.

**Project-wide trust caveat:** GKE clusters in the same project share a workload identity pool; an identical namespace/KSA name in another cluster can represent the same federated identity. Use unique environment/cluster-specific namespace/KSA pairs or separate projects for stronger boundaries. Likewise namespace admins must not be able to create privileged service accounts used by another tenant.

Private Artifact Registry image pulls use the **node** service account, not the Pod's workload identity. Grant repository-level `roles/artifactregistry.reader` to `node_service_account_email` in the repository's configuration (preferred). Alternatively list trusted repository projects in `artifact_registry_projects` for broader project-level read grants. Default is no private registry grants. The deployer must have IAM permissions in any such projects.

## Shared-cluster responsibilities

This is a secure infrastructure baseline, not a complete multi-tenant Kubernetes policy stack. Before onboarding production teams, use a separate GitOps/bootstrap layer to enforce:

* Namespaces and least-privilege team RBAC; no blanket cluster-admin bindings.
* Pod Security Admission (normally `restricted`), restrictions on privileged/host-network Pods, hostPath and node access. Host-network/privileged workloads can bypass workload identity isolation.
* Default-deny ingress/egress NetworkPolicies with explicit DNS, metadata-server, monitoring and application dependencies allowed. Dataplane V2 supplies enforcement but **does not install default-deny policies**. Test GKE metadata-server traffic allowances before enforcing egress deny.
* ResourceQuota/LimitRange, resource requests, multiple replicas, topology spread/anti-affinity and realistic PodDisruptionBudgets. Cluster HA alone does not make a single replica resilient.
* Controlled ingress/Gateway creation, TLS, external exposure policy, secret management, supply-chain admission and audit/alert routing.
* Tested backup and restore for Kubernetes objects and persistent application data, plus cross-region DR where required. No backup plans are implicitly created. Google-managed encryption at rest is used; this root does not provision customer-managed KMS keys.

Plan/apply the root separately from that bootstrap layer so a fresh private cluster does not require a working Kubernetes provider during infrastructure planning. Do not treat mutually untrusted teams as a hard security boundary inside one cluster; use separate clusters/projects if required.
