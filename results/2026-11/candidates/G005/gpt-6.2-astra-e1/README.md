# Regional GKE Standard

Use one root instance and a separate protected state per cluster. Copy `minimal.tfvars`, replace the example values, and run `tofu init` and `tofu plan -var-file=<your-file> -out=gke.plan`. Review the target project, network paths and capacity before `tofu apply gke.plan`.

## Before provisioning

- Enable the GKE, Compute, IAM, Cloud Logging and Cloud Monitoring APIs in the project. Use environment credentials authorized to create clusters, use the subnet, manage the node service account and its project IAM membership, and act as that account.
- Confirm the existing subnet and its `pods` and `services` secondary ranges. Reserve a unique control-plane /28 with the network team. Size subnet, secondary ranges and quotas for peak scale, temporary bootstrap nodes and surge upgrades.
- Nodes have no public IPs. Verify Private Google Access and DNS for Google APIs and image registries; arrange Cloud NAT or a proxy if workloads need internet egress. The module does not change shared networking.
- Administrators need a routed private path to the API endpoint (for example, a management VM in the VPC), IAM access to discover the cluster, and Kubernetes authorization. Connect with `gcloud container clusters get-credentials CLUSTER --region REGION --project PROJECT --internal-ip`.

## Operating model

GKE selects the regional cluster's default worker zones (normally three). The worker pool keeps at least one on-demand node per zone by default and scales up to five per zone. `pool` overrides sizing; limits apply separately in each zone. Regular-channel upgrades, node auto-repair and surge upgrades are enabled. Product teams should spread replicas across zones, set resource requests and define disruption budgets; infrastructure redundancy alone does not make a single replica highly available.

The node account has the GKE node runtime role, not application permissions. Grant it reader access on specific private Artifact Registry repositories when required. Give each application a Kubernetes service account; grant its Workload Identity Federation principal only the resource-scoped permissions it needs (e.g. subscriber on one subscription or object viewer on one bucket). Do not distribute service account keys. IAM authorization does not provide network connectivity; coordinate Cloud SQL private routes separately. Within a project the workload pool is shared: namespace/service-account pairs used in IAM grants must not be reusable by untrusted teams or clusters.

Before onboarding teams, configure namespaces, RBAC, Pod Security admission, quotas, and default-deny NetworkPolicies with explicit DNS and application allowances. Dataplane V2 enforces NetworkPolicies, but does not isolate namespaces by default. Set up alerts from Cloud Monitoring and control access and retention for workload logs. Keep protected state and workload backups; deletion protection is not a backup. Intentional cluster retirement requires first changing deletion protection to false and applying that change before destroying the cluster.
