# Regional GKE Standard

This OpenTofu root module creates one regional GKE Standard cluster and one separately managed general-purpose node pool. Use a separate state for each cluster. The module consumes the network team's existing VPC, subnet, and secondary ranges; it does not create or take ownership of them.

## Before provisioning

- Enable GKE and Compute Engine in the target project, plus the APIs used for provisioning and telemetry (IAM, Cloud Resource Manager, Cloud Logging, and Cloud Monitoring). Enable the IAM Service Account Credentials API when using service-account impersonation for workloads. Keep API enablement and Google-managed service-agent IAM in project bootstrap, not in each cluster's state.
- Confirm that `apps-<environment>-gke-<region>` exists in `apps-<environment>` in the cluster project with secondary ranges `pods` and `services`. Check the available subnet IPs, Pod IP blocks, Service IPs, and Compute quotas for the full autoscaling maximum **plus** upgrade surge (up to one extra node per zone). If another cluster uses the subnet, verify supported secondary-range sharing and remaining capacity before deploying.
- Coordinate private-node connectivity with the network team: reach Google APIs and image registries (typically via Private Google Access for Google APIs), and provide Cloud NAT or another approved egress path only where workloads require public destinations. Private Cloud SQL requires a compatible private connectivity setup and DNS/routing; Workload Identity provides authentication, not network reachability.
- Use environment-provided Google application credentials. The provisioning identity must be able to manage GKE, create and attach the node service account, and grant its project-level node role. Use separate, narrowly scoped identities for day-to-day access. Use a protected, access-controlled remote state backend for production; configure it separately so the state bucket is not owned by the cluster it tracks.

## Deploy and connect

Copy `minimal.tfvars` to a per-cluster file and replace its four example values (`project_id`, `region`, `environment`, and `cluster_name`). The example is valid for planning, but its project is illustrative. `node_zones` is optional; leave it unset to let GKE choose three zones, or set exactly three zones in the selected region. Override `node_pool` only if you need different capacity. The default is one to four on-demand `e2-standard-4` nodes per zone with 100 GB balanced persistent boot disks (3–12 nodes in steady state across three zones).

```sh
tofu init
tofu plan -var-file=cluster.tfvars -out=cluster.plan
tofu apply cluster.plan
tofu output -raw get_credentials_command
```

Run the printed command with a recent `gcloud`, `kubectl`, and `gke-gcloud-auth-plugin`. The cluster exposes only the Google-managed, IAM-authenticated DNS endpoint; both IP-based client endpoints and Kubernetes certificate/token access via DNS are disabled. The DNS endpoint can be reached wherever the client can access the relevant Google API endpoint; it is **not** a VPC-only endpoint. Grant operator identities `container.clusters.get` and `container.clusters.connect` for discovery and connection, and grant only the intended Kubernetes permissions, typically through namespace-scoped RBAC for product teams. Avoid giving product teams broad GKE IAM roles. For organization-level network restriction of DNS access, coordinate VPC Service Controls separately.

## Workload access to Google Cloud

Create a distinct Kubernetes service account per workload and set the Pod's `serviceAccountName`. For supported APIs, bind the federated principal directly on the target resource (for example, Pub/Sub Subscriber on a subscription or Storage Object Viewer on a bucket):

```text
principal://iam.googleapis.com/projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/PROJECT_ID.svc.id.goog/subject/ns/NAMESPACE/sa/KSA_NAME
```

Use the **cluster project's** number and ID in this principal, even if the target resource is elsewhere. If an API or integration requires Google service account impersonation, grant the Kubernetes account `roles/iam.workloadIdentityUser` on a dedicated Google service account, annotate the Kubernetes account with `iam.gke.io/gcp-service-account`, and give the Google account only the needed resource roles. For example, use a dedicated Cloud SQL connector identity with Cloud SQL Client (and Cloud SQL Instance User if using IAM database authentication), in addition to network access and database grants. Don't issue service-account keys or grant application permissions to the node identity. Private Artifact Registry image pulls use the **node** identity; grant it Artifact Registry Reader only on the repositories it needs.

Workload Identity pools are project-scoped. Identical namespace/service-account names in different clusters in the same project can represent the same IAM principal. Use distinct identities across trust boundaries or restrict access with cluster-aware IAM conditions where supported. Use separate projects for clusters that must have hard identity separation.

## Operate the cluster

- GKE handles control-plane and node upgrades through the Regular release channel. The recurring maintenance window is Saturday and Sunday, 06:00–12:00 UTC; GKE can apply some urgent maintenance outside it. Nodes have auto-repair, Secure Boot, and integrity monitoring. Surge upgrades retain existing nodes until replacement capacity is ready under normal conditions. Test significant changes in staging.
- A regional cluster is not by itself application HA or disaster recovery. Spread workload replicas across zones using topology spread constraints, set realistic resource requests and disruption budgets, and verify two zones have sufficient capacity for a zone outage. Configure backups and alerting separately. Review Cloud Logging and Cloud Monitoring volumes; the module enables system and workload logs, system and control-plane metrics, and managed Prometheus (configure scrape targets for application metrics).
- Namespace creation, RBAC, resource quotas, Pod Security Admission, and per-team network policies are platform responsibilities outside this root. Dataplane V2 enforces Kubernetes NetworkPolicy, but does not create policies or isolate namespaces by itself. Apply default-deny policies with explicit DNS, Workload Identity metadata access, and service connectivity exceptions before onboarding workloads. Namespaces alone are not a hard boundary for mutually untrusted tenants.
- Google-managed encryption at rest applies by default. To add application-layer encryption of Kubernetes Secrets, set `secrets_kms_key` after granting the cluster project's GKE service agent (`service-PROJECT_NUMBER@container-engine-robot.iam.gserviceaccount.com`) `roles/cloudkms.cryptoKeyEncrypterDecrypter` on that regional key. Maintain key availability and do not destroy key versions still in use.
- Cluster deletion protection defaults to enabled. For planned retirement, migrate workloads and retain required data, apply `deletion_protection = false` to record the explicit opt-out in state, then review a separate destroy plan. Do not run destroy to test this guard: it protects the cluster resource, not independent resources such as the node pool.
