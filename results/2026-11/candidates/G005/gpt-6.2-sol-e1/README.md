# Regional GKE Standard

Use this root configuration with **one state per cluster**. For production, configure a protected, access-controlled remote backend with locking and versioning as part of deployment; do not share or commit local state files. Use Google credentials from the environment rather than placing credentials in tfvars.

```sh
tofu init
tofu plan -var-file=minimal.tfvars
```

`minimal.tfvars` has the four required inputs: `project_id`, `cluster_name`, `environment` (`staging` or `prod`), and `region`. Before applying, copy it and replace the example project and cluster details with your own. Planning does not look up the existing network or guarantee that the example can be applied unchanged.

## Before applying

- Confirm that `apps-<environment>` and `apps-<environment>-gke-<region>` exist in the cluster project and that the subnet has usable `pods` and `services` secondary ranges. The module does not create or change network resources. Check range allocation and size, Compute Engine quota, and zonal capacity for the temporary bootstrap pool, configured autoscaling maxima, and upgrade surge.
- Nodes have no public IPs. Have the network team ensure nodes and Pods can reach required Google APIs (for example, via Private Google Access on the subnet with appropriate DNS, routes, and firewall rules). Arrange approved egress such as Cloud NAT if nodes or Pods need access to public destinations. Private Cloud SQL connectivity and its DNS or routing must be configured separately.
- The module enables `container.googleapis.com` and leaves it enabled upon destruction. The project should already be set up with billing and the supporting Compute Engine, IAM, Cloud Logging, and Cloud Monitoring APIs. Enable any additional application APIs in the projects that own those resources.
- The applying identity needs permission to enable the GKE API, provision GKE in the existing subnet, create and attach a node service account, and grant its node role on the project. The node identity gets only `roles/container.defaultNodeServiceAccount` from this module. If pulling private images from Artifact Registry, grant that identity `roles/artifactregistry.reader` on the relevant repositories rather than on the entire project.

## What you get

- A regional, VPC-native Standard cluster. GKE selects three node zones by default; set `node_locations` to choose the three zones explicitly. The default general pool uses on-demand `e2-standard-4` COS nodes and autoscaling of one to three nodes **per zone** (three to nine total). `node_pools` lets you replace this pool configuration without changing the cluster defaults. GKE creates a temporary default pool at cluster creation; OpenTofu removes it and manages the replacement pools separately.
- Private, Shielded nodes with Secure Boot and integrity monitoring, plus Dataplane V2 for Kubernetes NetworkPolicy enforcement. The Kubernetes API is available only through the IAM-authenticated DNS endpoint; direct IP access and legacy ABAC are disabled. The DNS endpoint can be reached via Google APIs, including from outside the VPC; it is not a private IP endpoint.
- Regular release-channel upgrades, node auto-repair and auto-upgrade, and surge upgrades with one extra node per zone and zero intentionally unavailable nodes. Routine maintenance is scheduled in a daily four-hour window starting at 08:00 UTC by default (`maintenance_start_time`). Use topology spread, replicas, and PodDisruptionBudgets to carry this availability through to workloads. System and workload logs, system metrics, and managed Prometheus are enabled; configure workload scrape targets, dashboards, and alerting separately.

## Access and team onboarding

- To connect, run the command from `tofu output -raw get_credentials_command` using a current `gcloud` and `gke-gcloud-auth-plugin`. Give operators the IAM permissions needed to discover the cluster and connect to its DNS endpoint (`container.clusters.get` and `container.clusters.connect`), then use namespace-scoped Kubernetes RBAC for product teams instead of granting cluster-wide admin access.
- Create a Kubernetes service account per workload. Use Workload Identity Federation for GKE to grant that identity narrowly scoped permissions on the bucket, Pub/Sub resource, or Cloud SQL project as appropriate. Where needed, use federated impersonation of a dedicated Google service account; do not distribute keys or grant application roles to the node identity. In a project with multiple clusters, identical namespace/service-account names can represent the same workload identity for IAM. Use distinct names where privileges must differ, or use cluster-scoped IAM conditions where supported.
- Before onboarding teams, configure namespace RBAC, quotas, Pod Security Admission, and default-deny NetworkPolicies with explicit exceptions (including required DNS and metadata traffic). Dataplane V2 enforces policies you apply; it does not create tenant isolation by itself. Shared clusters are not a substitute for separate clusters for mutually untrusted tenants.
- Deletion protection defaults to on. Before attempting a destroy, drain or migrate workloads and back up their data, then set `deletion_protection = false` and apply that change. Cluster deletion protection does not independently protect node pools from deletion.
