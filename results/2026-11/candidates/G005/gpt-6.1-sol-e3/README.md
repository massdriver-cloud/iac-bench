# Production GKE Standard root module

One invocation/state per cluster. All resources are authored here; there are no remote modules. Credentials use Google Application Default Credentials from the environment. Pin the generated provider lockfile in your repository and use a separately secured, access-controlled remote state backend for production; no backend bucket or credentials are embedded here.

## Quick start

```sh
tofu init
# Copy and edit minimal.tfvars for YOUR project, name, region and reserved /28.
tofu plan -var-file=minimal.tfvars
tofu apply -var-file=minimal.tfvars
```

`minimal.tfvars` uses an illustrative project ID, not a project this module creates. The five required inputs are `project_id`, `name`, `environment` (`prod` or `staging`), `region` (US), and `control_plane_ipv4_cidr` (unique RFC1918 /28). The rest have production-oriented defaults; see variable descriptions. This is a **regional Standard** cluster, not zonal or Autopilot. Expect at least three paid nodes, plus upgrade surge capacity, logging, monitoring and control-plane charges.

## Network and bootstrap prerequisites

* Project and billing already exist. The applying principal needs permission to enable services, create/manage GKE clusters and service accounts, set the additive project/SA IAM grants, use the VPC/subnet, and act as the node service account. Repository IAM changes additionally require permission in the repository's project. Bootstrap Service Usage permissions must already exist.
* Network team owns `apps-<environment>` and the regional subnet `apps-<environment>-gke-<region>` in **the same project**. Secondary ranges must be named exactly `pods` and `services`. No VPC, subnet, secondary range, routes, firewall rules or Cloud NAT are created or modified. Ensure sufficient secondary IP capacity for every pool's maximum size **and** surge (default max pods per node 64 reserves a /25 per node); avoid overlapping control-plane /28s and routed/peered ranges.
* Private nodes need Private Google Access on the existing subnet and suitable DNS/routing/firewall access to Google APIs and registries. The network team must provide Cloud NAT or equivalent controlled egress where public endpoints/external images are needed. Permit GKE control-plane-to-node and required node/pod traffic; account for custom webhook ports and any hierarchical firewall policies.
* API access is **private only**. Add `authorized_networks = { platform = "10.20.0.0/24" }` with your real CI/operator source CIDRs and establish VPN/Interconnect or an in-VPC runner/bastion with the required routes. Global private endpoint access is enabled, but is NOT public access. An empty map is deliberately fail-closed for operator clients, not an automatic allow-all; GKE retains required cluster/node access. Include expanded node source ranges if required by your subnet layout. No public endpoint fallback is exposed.
* Run the `get_credentials_command` output from that network, with `gke-gcloud-auth-plugin`. IAM and Kubernetes RBAC still control authorization; network reachability grants no Kubernetes privileges. Do not grant developers cluster-admin. `security_group` optionally enables Google Groups RBAC; configure its required Google Workspace group hierarchy separately.

## Design and operations

* Regional control plane and three GKE-selected node zones by default; `node_locations` can explicitly select three or more zones in the chosen region. Every pool is on-demand, minimum one node **per zone**, autoscaling 1–3 per zone by default. No mutable `node_count` fights autoscaling. Machine type, disk, pool labels, max pods and autoscaler limits can be set per pool.
* COS/containerd, Shielded nodes, Secure Boot, integrity monitoring, no legacy metadata, no legacy ABAC, no client certificate issuance. Nodes use a dedicated service account with `roles/container.defaultNodeServiceAccount`, not a default Compute Engine account or Editor. Broad OAuth scope is constrained by IAM, not broad IAM access. Nodes have no external IPs.
* Workload Identity Federation for GKE is mandatory. Product workloads must never use node credentials or downloaded service-account keys. No application IAM roles are granted by default. Optional repository-reader grants are scoped to explicitly listed Artifact Registry repositories (including cross-project repositories). Without these, public images can be used with suitable egress, but private Artifact Registry pulls will fail.
* Dataplane V2 supplies native Kubernetes NetworkPolicy enforcement. **It does not install deny policies**: use GitOps to create namespace default-deny ingress/egress, explicit DNS/API/service allowances, restricted Pod Security Admission, ResourceQuotas, LimitRanges and tightly scoped RBAC before onboarding teams. Do not enable a separate Calico/network-policy addon on Dataplane V2. Kubernetes-level resources are deliberately outside this infrastructure root so an unreachable cluster cannot block infrastructure planning.
* REGULAR release channel, automatic node upgrades and repair, surge 1/unavailable 0 per zone. Daily four-hour UTC maintenance window defaults to 06:00–10:00; change `maintenance_start_time` to shift it. GKE may perform emergency maintenance outside windows. Reserve compute/IP quota for surges and use PDBs that allow voluntary disruption. Spread replicas with topology spread/anti-affinity across zones; three nodes alone do not make a single-replica app resilient.
* System/workload/control-plane logs, system monitoring and managed Prometheus are enabled. Configure collection policies, retention, alerting and SLOs outside this root; collection has cost implications. Basic security posture and vulnerability scanning are enabled. Google-managed encryption at rest is used; this module does not promise application-layer CMEK or organization-specific compliance controls.
* Cluster deletion protection defaults on. To destroy, explicitly set `deletion_protection = false`, apply, then destroy. This is not a data backup mechanism. Define PV/database backup and recovery plans, retention and restore drills separately. APIs stay enabled on destroy because this is a shared project. IAM uses additive members, never authoritative policy replacement.

## Application access to Google Cloud

Example optional inputs (not needed for the minimal cluster):

```hcl
workload_identities = {
  orders = {
    namespace       = "orders-prod"
    service_account = "orders-api"
    project_roles   = ["roles/cloudsql.client"]
  }
}
artifact_registry_repositories = {
  apps = { project = "apps-prod-platform", location = "us-central1", repository = "apps" }
}
```

The module creates a dedicated GSA and `roles/iam.workloadIdentityUser` binding to that namespace/KSA pair. Create the Kubernetes ServiceAccount via GitOps, annotate it with the `workload_service_accounts` output's annotation, and use `serviceAccountName` in the Deployment. Cloud SQL Auth Proxy/connectors use ADC; private SQL additionally needs network connectivity. Cloud SQL instances, database users and API enablement for application services are not created here.

Prefer grants on individual Pub/Sub topics/subscriptions and Storage buckets (outside this module) to the output GSA email. `project_roles` is an explicit convenience for genuinely project-wide permissions, not a recommendation to grant broad access; primitive roles are rejected. Do not reuse the same GSA for unrelated teams. Enable the Pub/Sub, Storage or SQL Admin APIs as needed in the owning project. GKE's workload pool is project-wide: the same namespace/KSA name in another cluster in this project can impersonate the same GSA. Use distinct namespace/KSA pairs across clusters, restrict who can create/use these identities with RBAC/admission, or separate projects for stronger trust isolation. Shared clusters are not a hard hostile-tenant security boundary.

Inputs for node pools and identities affect persistent resource names: changing map keys or the cluster name may replace resources. Review all plans, test upgrades in staging first, and keep state protected from concurrent writers. No passwords, access tokens, service-account keys or kubeconfig are output.
