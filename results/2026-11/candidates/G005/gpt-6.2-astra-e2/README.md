# Regional GKE Standard

Use one state per cluster. Copy `minimal.tfvars` to a cluster-specific file and replace the example project and CIDR. Choose `staging` or `prod`; the module references (never creates) `apps-<environment>`, its regional GKE subnet, and that subnet's `pods` and `services` ranges. Coordinate a unique control-plane /28 and check for overlap with connected networks. Size the subnet, Pod range and regional CPU/disk quota for the per-zone maximum **plus upgrade surge**.

Enable Kubernetes Engine, Compute Engine, IAM, Cloud Logging and Cloud Monitoring APIs before applying. Use environment credentials authorized to create clusters and service accounts, attach the node identity and add its project IAM membership. Ensure private nodes can reach Google APIs and image registries (Private Google Access, and NAT or another egress path where required). Grant the node service account reader access on specific private image repositories if needed.

```
tofu init
tofu plan -var-file=cluster.tfvars -out=cluster.plan
tofu apply cluster.plan
```

The regional cluster uses GKE's default zone placement, with a minimum of one on-demand worker in each selected zone. GKE repairs and upgrades nodes on the Regular channel; reserve room for a surge worker per zone. Deploy replicated workloads with zone topology constraints, disruption budgets and resource requests: regional infrastructure alone does not make an application highly available.

For kubectl, run `gcloud container clusters get-credentials NAME --region REGION --project PROJECT --internal-ip` from a host with private connectivity to the control plane. Restrict that connectivity to management networks. Configure team namespaces, Kubernetes RBAC, Pod Security Admission, quotas and default-deny NetworkPolicies before team onboarding. Dataplane V2 enforces policies, but does not isolate namespaces without policies.

Use separate Kubernetes service accounts per workload. Grant the Workload Identity Federation principal for its namespace/service account the narrowest role on its specific topic, bucket or other resource. Do not distribute keys or grant application roles to the node identity. Workload pools are project-wide: identically named namespace/service-account pairs in different clusters in one project can represent the same principal; coordinate names or constrain grants by cluster. Cloud SQL also needs a network path and database authentication.

Keep state access restricted and backed up. Deletion protection is on for the cluster; it is not a workload backup or a lock on individual pools. To retire a cluster, migrate workloads and data, set `deletion_protection = false`, apply, then review a destroy plan.
