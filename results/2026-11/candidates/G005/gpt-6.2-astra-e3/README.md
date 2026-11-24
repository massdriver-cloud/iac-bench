# Regional GKE Standard

Use one root deployment and one protected state per cluster. Copy `minimal.tfvars`, replace the sample project, cluster name, region, environment and control-plane CIDR, then run `tofu init` and `tofu plan -var-file=minimal.tfvars -out=cluster.plan`. Review and `tofu apply cluster.plan`. Use your platform's access-controlled remote backend for real deployments.

## Before apply

- Enable the Kubernetes Engine, Compute Engine, IAM, Logging and Monitoring APIs in the project. The caller needs cluster management, service account creation/use and project IAM binding permissions. API enablement, organization policy and network provisioning are project prerequisites, not owned per cluster.
- Confirm `apps-<environment>-gke-<region>` exists on `apps-<environment>` with secondary ranges `pods` and `services`. Allocate a unique nonoverlapping private /28; check connected networks too. Reserve addresses and regional CPU/disk quota for maximum worker count plus surge and replacement capacity.
- Nodes have no public IPs. Confirm Private Google Access and any required NAT or private registry routes. If using Artifact Registry, grant the output node service account reader access **on the required repositories**, not data-plane roles across the project.
- The Kubernetes API uses a private IP endpoint. Run the output credentials command on an authorized, privately connected administrator host with regional reachability, the gcloud GKE auth plugin and appropriate IAM/RBAC permissions. This module does not install an internet-facing management path.

## Operating model

GKE distributes the regional control plane and general-purpose worker pool across zones. `worker_capacity` limits are per zone: at three zones the default is 3–15 workers. Use multiple workload replicas, resource requests, topology spread and PodDisruptionBudgets; a regional cluster alone does not make a singleton workload resilient. Autoscaling is not a substitute for reserving enough headroom to lose a zone. Workers auto-repair and follow the Regular release channel with surge upgrades; routine maintenance windows are Saturday and Sunday 05:00–13:00 UTC. Monitor capacity and disruption budgets before rollouts. Deletion protection must be explicitly disabled and applied before intentional cluster destruction.

## Team onboarding (post-provisioning)

Create team namespaces with scoped RBAC, quotas and restricted Pod Security Admission. Dataplane V2 supports Kubernetes NetworkPolicy; it does **not** deny traffic by default. Install namespace default-deny ingress/egress policies and allow only DNS, workload identity metadata and application dependencies as needed before handing namespaces to teams.

Use a distinct Kubernetes service account (KSA) per workload and set `serviceAccountName` on its pods. With Workload Identity Federation, a resource owner can grant a role directly to `principal://iam.googleapis.com/projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/PROJECT_ID.svc.id.goog/subject/ns/NAMESPACE/sa/KSA`, for example `roles/pubsub.subscriber` on one subscription. For APIs needing a Google service account, bind the KSA for impersonation and annotate it; do not distribute JSON keys. Coordinate namespace/KSA names across clusters in the same project because they share the identity pool. Cloud SQL also needs network connectivity and database authorization. The module grants no application data permissions to nodes or workloads.

System/workload logs, system metrics and managed Prometheus are enabled. Configure alerting, retention, application scrape targets and workload backup/restore policies to match each service's objectives.
