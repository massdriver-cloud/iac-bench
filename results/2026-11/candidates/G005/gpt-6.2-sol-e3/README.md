# Regional GKE Standard

This OpenTofu root module manages **one cluster per state**. It uses the existing `apps-staging` or `apps-prod` VPC and `<vpc>-gke-<region>` subnet in the cluster project, attaching the existing `pods` and `services` secondary ranges. It does not create or change the VPC, subnet, secondary ranges, or project-wide service settings.

## Deploy

1. Give each cluster its own state. Use a secured remote backend with state locking for production (a pre-existing GCS backend is one option); this root module does not provision a backend. Supply Google Cloud Application Default Credentials through the environment. The provisioning identity needs permission to manage GKE clusters, create and attach the node service account, and add its project IAM binding.
2. Confirm that the project has billing and the required APIs enabled: Kubernetes Engine, Compute Engine, IAM, Cloud Resource Manager, Cloud Logging, and Cloud Monitoring. The network team should confirm the names, Private Google Access, routes and firewall rules for private nodes and Google APIs. Arrange Cloud NAT or another approved egress path if nodes or workloads need external registries or other internet destinations. Check node IPs, secondary range capacity, and regional VM and disk quota at peak autoscaling **plus surge capacity**, including other clusters using the subnet.
3. Copy `minimal.tfvars` and edit the four required settings: `project_id`, `cluster_name`, `region`, and `environment`. The example project ID is illustrative. The plan constructs network resource paths without looking them up; GKE verifies the network and ranges at creation.

```sh
tofu init
tofu plan -var-file=cluster.tfvars -out=cluster.plan
tofu apply cluster.plan
```

## Defaults and access

- The regional control plane and node pools use GKE's default regional zone placement (normally three zones). The default `general` pool scales from **1 to 4 on-demand `e2-standard-4` nodes per zone** (typically 3–12 total before surge). GKE repairs and upgrades nodes automatically. Surge upgrades target one extra node and zero planned unavailable nodes per zone; leave quota and IP headroom. Use the optional `node_pools` map to set additional or differently sized pools and their per-zone limits, Kubernetes labels, and taints. Keep the pool keys stable: renaming a key creates a different pool and removes the old one.
- The cluster follows the **Regular** release channel, with a daily maintenance window starting at **05:00 UTC** unless overridden. Maintenance windows are not a guarantee against emergency maintenance. Application owners must still use multiple replicas, topology spread, and realistic disruption budgets for availability.
- Nodes have no public addresses and use Shielded VMs with Secure Boot. The API server's public and private IP endpoints are disabled. The **DNS endpoint** accepts connections through Google's API front end, including from outside the VPC; it is not VPC-only. Google IAM gates connection, and Kubernetes authorization still applies. Client certificate and Kubernetes bearer-token authentication through that endpoint are disabled. Grant operators `container.clusters.get` and `container.clusters.connect` as needed (for example, via `roles/container.clusterViewer`), and scope their Kubernetes RBAC separately. With a current `gcloud` and the GKE auth plugin, run the command printed by `tofu output -raw get_credentials_command`.
- Dataplane V2 enforces Kubernetes NetworkPolicy, but does not create policies for tenants. Use namespaces, namespace-scoped RBAC, default-deny policies with explicit allowances, Pod Security Admission, and quotas. Do not give teams cluster-admin or unrestricted privileged pod access. A shared cluster is not a hard isolation boundary for mutually untrusted tenants.
- Cloud Logging collects system and workload logs; Cloud Monitoring collects system metrics and Managed Service for Prometheus is enabled. Configure application scrape resources and operational alerts separately, and budget for ingestion. Applications and their backups are not managed by this module.

## Access to Google Cloud from workloads

Use **Workload Identity Federation for GKE**, not downloaded keys or the node identity. Give each workload its own Kubernetes ServiceAccount and set `serviceAccountName` on its Pods. Grant that workload principal only the role it needs on its target resource (for example, Pub/Sub Subscriber on one subscription or Storage Object Viewer on one bucket). The principal for direct IAM bindings has this form:

```text
principal://iam.googleapis.com/projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/PROJECT_ID.svc.id.goog/subject/ns/NAMESPACE/sa/KSA_NAME
```

Clusters in one project share this identity pool. For name-based bindings, the same namespace and ServiceAccount name in another cluster in that project represent the **same IAM identity**. Coordinate names and who can create or use them across clusters, and use separate projects where a hard IAM trust boundary is required. For APIs or integrations that require an IAM service account, use a dedicated IAM service account with narrowly scoped impersonation from the Kubernetes ServiceAccount. For private-IP Cloud SQL, also arrange network reachability and database authentication; Workload Identity Federation does not supply a route or database grants.

The module's dedicated node service account gets the GKE default node service account role, not application roles. If you pull from private Artifact Registry repositories, grant the node service account Reader on only the required repositories. The node service account email and workload pool are available as outputs.

## Intentional teardown

Cluster deletion protection defaults to on. Back up any workloads and data you need, set `deletion_protection = false`, apply the change, and only then destroy with that cluster's variable file. Existing network resources are not destroyed. Review plans before changing the cluster's project, region, name, or network selection, as these settings can require replacement.
