# Regional GKE Standard root module

An opinionated foundation for shared production clusters in `apps-staging` or
`apps-prod`. All resources are authored here; there are no remote modules. Deploy
one root/state per cluster. Staging uses the same security and availability defaults
as production.

## Quick start

1. Copy `minimal.tfvars` to a cluster-specific file. Replace the illustrative
   project ID, name, region, control-plane CIDR and administrative source range
   with real, allocated values. All six required inputs are present in the sample.
2. Meet the network and IAM prerequisites below. Authenticate OpenTofu through
   environment credentials or Application Default Credentials; do not put keys in
   tfvars. Prefer CI service-account impersonation or federation.
3. Run:

   ```sh
   tofu init
   tofu fmt -check
   tofu validate
   tofu plan -var-file=minimal.tfvars -out=cluster.plan
   tofu apply cluster.plan
   tofu output -raw get_credentials_command
   ```

   Run the emitted command from an authorized, network-connected workstation with
   `gke-gcloud-auth-plugin` installed. Network allowlisting is not authentication:
   callers also need GKE IAM and appropriate Kubernetes RBAC permissions.
4. Complete the tenant bootstrap checklist before deploying product workloads.

Use an encrypted, access-controlled remote state backend with locking and a unique
state prefix per cluster. No backend is hard-coded because the state bucket is a
platform bootstrap concern. Keep the generated provider lock file under version
control. State and saved plans are sensitive even when outputs are marked sensitive.
This root only calls Google APIs: applying infrastructure does not require the runner
to reach the private Kubernetes API. Tenant bootstrap does.

## Design and defaults

| Area | Decision |
| --- | --- |
| Availability | Regional Standard control plane; GKE's default three node zones within the region. No single-zone or Autopilot mode. |
| Worker capacity | Separate managed pools; disposable default/bootstrap pool removed. Default `general` pool: on-demand `e2-standard-4`, COS/containerd, 100 GB balanced PD. |
| Autoscaling | Total 3–30 nodes **across all zones**, balanced placement; 32 pods per node. No fixed `node_count` fighting the autoscaler. Each pool starts with one node per zone, then autoscaler adjusts to configured minimum. |
| Upgrades | REGULAR release channel, automatic node upgrade and repair, one surge and zero unavailable per zone. No version pin that can strand a cluster on an unsupported release. |
| Maintenance | Saturday 00:00 through Monday 00:00 UTC weekly. Emergency GKE maintenance can bypass windows; this is not a no-disruption guarantee. |
| Networking | Existing environment VPC/subnet only; VPC-native aliases from `pods` and `services`. No VPC, subnet, NAT, routes or shared firewall resources are owned here. |
| API access | Private endpoint by default. Required source allowlist enforced on the private endpoint too; Google public ranges are not implicitly trusted. Private endpoint global access permits routed admins in other regions, not public internet access. An allowlisted public endpoint is an explicit opt-in. |
| Node security | No external IPs, dedicated custom node SA with `roles/container.defaultNodeServiceAccount`, Shielded nodes, Secure Boot, integrity monitoring, legacy metadata endpoints disabled. |
| Workload identity | GKE Workload Identity Federation and GKE metadata server on every pool; no service account keys. Optional narrowly bound KSA-to-GSA identities. Application permissions never go on the node identity. |
| Isolation support | Dataplane V2 provides Kubernetes NetworkPolicy enforcement. Legacy ABAC and client certificate issuance are disabled. Tenant policies must still be installed (below). |
| Image admission | Binary Authorization enabled against the existing project-wide policy. This root does **not** overwrite that shared policy. |
| Observability | System/workload/control-plane logging, system/control-plane monitoring, Managed Service for Prometheus and basic security/vulnerability posture. Logs/scans/metrics can incur charges. |
| Storage | GCE PD CSI enabled. GKE encryption at rest remains in effect; optional KMS key adds application-layer Secret encryption. |
| Safety | Cluster deletion protection enabled. IAM uses additive members; shared APIs remain enabled on destroy. |

Defaults are a starting capacity, not a workload SLA. `BALANCED` autoscaling tries
to spread capacity; total minima do not guarantee an exact per-zone distribution.
Use topology spread and adequate spare capacity for zone failure. The cluster is
regional, **not** multi-region disaster recovery. Size compute quotas for bootstrap
nodes and rolling surge (up to one extra node per zone per upgrading pool), and
size shared pod ranges for all clusters and pools at maximum capacity plus surge.
At 32 pods per node GKE normally reserves a /26 per node; pod density changes have
IP-capacity and replacement implications. Changing pool names deletes/recreates
pools: introduce a new pool, migrate/drain workloads, then remove the old one.

## Prerequisites and ownership boundaries

The existing project must have billing enabled. The deployer needs permissions to
enable APIs, create/manage GKE clusters and node pools, read the existing network,
create/act as service accounts, and add the configured project/service-account IAM
members. Optional repository grants require IAM administration on those
repositories; CMEK requires IAM administration on the key. Bootstrap these grants
outside this root; it does not grant privileges to its own deployer. Preserve the
Google-managed GKE service-agent IAM grants.

The network team must provide:

- `apps-<environment>` in **the same project** as the cluster (not Shared VPC).
- Regional subnet `apps-<environment>-gke-<region>`, with IPv4 secondary ranges
  named exactly `pods` and `services`, and Private Google Access enabled. The root
  checks VPC membership, range names and Private Google Access before cluster
  creation. During the initial plan these reads/checks are deferred until the
  prerequisite APIs are enabled; a clean plan is not proof the sample network exists.
- An unused, aligned RFC1918 /28 control-plane allocation. Coordinate it against
  primary/secondary, peered and on-prem ranges; basic format validation does not
  prove global non-overlap or capacity. The subnet/ranges can be shared with other
  clusters subject to GKE range-sharing rules and capacity.
- Private admin connectivity (VPN/Interconnect/routed bastion), routes/return routes
  and suitable firewall policy. Include the **actual source CIDRs** observed at the
  control plane in `authorized_networks`. Do not use node/pod address space for
  external admin clients. The module supplies no VPN or bastion.
- Egress routes/DNS for Google APIs. Private Google Access does not grant arbitrary
  internet access; supply Cloud NAT or controlled egress for public registries and
  internet dependencies. This root deliberately does not create NAT in a shared VPC.
- Any additional control-plane-to-webhook firewall rules and Cloud SQL private
  connectivity (Private Service Access/PSC) required by applications.

Required GKE/IAM/telemetry/Artifact Registry/Binary Authorization APIs are enabled
and not disabled on destroy. Pub/Sub, Storage, SQL, KMS and other workload service
APIs/resources remain with their owning teams. Enabling APIs here is non-destructive,
but coordinate their lifecycle if several cluster states share a project.

## Application credentials and image pulls

`artifact_registry_repositories` grants node image-pull access on specific
repositories, including cross-project repositories. No application repository
access is granted by default. Workload Identity does **not** authenticate kubelet
image pulls. For example, add to your tfvars:

```hcl
artifact_registry_repositories = {
  products = {
    project_id    = "platform-prod-example"
    location      = "us-central1"
    repository_id = "products"
  }
}

workload_identities = {
  prod-orders-api = {
    namespace       = "prod-orders"
    service_account = "api"
    project_roles   = ["roles/cloudsql.client"]
  }
}
```

This creates a GSA, allows only the specified namespace/KSA to impersonate it,
and optionally grants service-specific project roles in the cluster project.
Account IDs must be unique across the project (and distinct from the node SA).
Basic Owner/Editor/Viewer roles are rejected. Treat other role choices as privileged
configuration; validation is not an exhaustive permission-safety checker.

Consume `workload_service_accounts` in your GitOps/bootstrap layer to create the
Kubernetes SA with annotation
`iam.gke.io/gcp-service-account: <GSA email>` and set the Pod's
`spec.serviceAccountName` to that KSA. Google client libraries use Application
Default Credentials automatically; no JSON key should be mounted.

Prefer granting `roles/pubsub.publisher`/`roles/pubsub.subscriber` on particular
topics/subscriptions and `roles/storage.objectViewer` or other necessary object
roles on specific buckets in the owning services' IaC, using the output GSA email.
Leave `project_roles` empty for those identities. Cross-project grants likewise
belong with the destination resources. Cloud SQL Auth Proxy/connector can use the
GSA and `roles/cloudsql.client`; IAM database authentication also needs the
appropriate IAM role, database user/grants, instance configuration and network path.
Workload Identity grants neither database privileges nor network connectivity.

**Project-wide identity caveat:** GKE's workload pool is shared by all clusters in
a project. Identical namespace/KSA names in another cluster can match the same GSA
binding. Reserve cluster-specific namespace/KSA names, tightly control tenant
namespace creation, or use separate projects for stronger trust boundaries. A
shared cluster is not appropriate for mutually hostile tenants. Restrict privileged
and `hostNetwork` pods: these can bypass ordinary pod-level isolation and potentially
reach node credentials.

## Tenant bootstrap and operations checklist

This root intentionally has no Kubernetes provider and does not try to administer
an as-yet nonexistent private API during planning. The platform's GitOps/bootstrap
stage must apply these controls before onboarding teams:

- Namespace-scoped RBAC and group access; product teams must not receive
  `cluster-admin`, node access, arbitrary impersonation or namespace creation rights.
- Pod Security Admission `restricted` enforcement (with narrow, reviewed system
  exceptions), namespace ResourceQuota/LimitRange, and workload requests/limits.
- Default-deny ingress **and egress** NetworkPolicies per tenant, then explicit
  allowances for DNS, required services and the GKE metadata server
  (`169.254.169.254:80` for Dataplane V2). Enabling Dataplane V2 alone does not deny
  cross-namespace traffic. Test policies before rollout.
- Multiple workload replicas, topology spread/anti-affinity across zones, readiness
  probes, disruption budgets, HPA and tested termination behavior. PDBs must allow
  upgrade progress and are not an indefinite veto on GKE maintenance.
- An approved Binary Authorization project policy/attestations. The project's
  default policy can allow all images; enabling enforcement alone does not establish
  an image allowlist. An existing restrictive policy may require your images to be
  attested before they can deploy.
- Prometheus PodMonitoring resources, dashboards, SLO/availability/error alerts,
  capacity/IP alerts, logging retention and audit-log export policy. Collection is
  enabled here; application alerts are not automatically invented.
- Application-consistent backups and restore drills, appropriate regional storage
  classes where needed, and cross-region recovery plans. A replicated control plane
  does not make a zonal persistent disk highly available or back up application data.

For CMEK, supply an existing compatible key in `database_encryption_key` and enable
Cloud KMS in its project. This module grants the GKE service agent encryption access
on that key before cluster creation. Keep the key enabled and retain old key versions
for recovery; key destruction can render cluster Secrets unrecoverable. The default
API state `DECRYPTED` means no *additional application-layer* encryption, not that
Google stores disks unencrypted.

Review staged plans for replacements, especially network/range/region and node pool
changes. Test release-channel upgrades and policy changes in staging first. Secure
Boot is intentional: custom unsigned kernel modules will not load. Custom machine
types must support the selected region, image and Shielded VM configuration.

To intentionally destroy: set `deletion_protection = false`, apply that change,
back up workloads, clean up workload-created load balancers/disks as appropriate,
then run destroy with the same variables. VPCs, subnets, repositories, application
resources, KMS keys and project APIs are retained; module-owned service accounts and
IAM members are removed. Destroying a cluster does not automatically clean up every
resource created through Kubernetes.
