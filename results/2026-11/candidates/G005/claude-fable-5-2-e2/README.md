# GKE Standard cluster for shared production workloads

Root module that creates one regional GKE Standard cluster in the network team's
`apps-<environment>` VPC. Apply it once per cluster, each with its own state.

## Creating a cluster

```hcl
# prod-usc1.tfvars
name        = "prod-usc1"
environment = "prod"        # or "staging"
region      = "us-central1"
```

```sh
tofu apply -var-file=prod-usc1.tfvars
```

`project_id` defaults to the project in the environment (`GOOGLE_PROJECT`); set it
explicitly if you would rather not depend on that. The module has no backend block:
add a remote backend (for example a GCS bucket) with a separate state per cluster
before using it for real clusters.

## What the module decides

| Area | Decision |
|---|---|
| Availability | Regional cluster; every node pool runs in all zones of the region, with at least one on-demand node per zone. Autoscaling, auto-repair, surge upgrades (add a node before draining one). |
| Network | Subnet `apps-<environment>-gke-<region>`, secondary ranges `pods` and `services`. Dataplane V2, so Kubernetes NetworkPolicy is enforced. |
| Exposure | Nodes have internal IPs only. The control plane has no public IP endpoint. |
| Cluster access | Through the DNS-based endpoint, where every request is authenticated and authorized by IAM (`get_credentials_command` output). Can be limited to in-VPC access with `control_plane_dns_endpoint_external_access = false`. |
| Workload access to Google Cloud | Workload Identity Federation for GKE. No service account keys; pods get their own identity instead of the node's (host-network pods excepted). |
| Node identity | Dedicated service account with only logging/monitoring and Artifact Registry read. |
| Node hardening | Container-Optimized OS, Shielded nodes with secure boot, kubelet read-only port off, legacy metadata endpoints off. |
| Auth | No client certificates, no legacy ABAC. |
| Upgrades | Release channel: staging `REGULAR`, prod `STABLE`. Maintenance Tue-Thu 07:00-12:00 UTC. |
| Operations | System, workload and control plane logs; Managed Service for Prometheus; per-namespace cost allocation. |
| Safety | Deletion protection on. |

## What the module expects from the network team

- The subnet and its `pods` / `services` secondary ranges exist in the cluster's project.
- Private Google Access is on for the subnet (nodes have no public IPs and need it to
  reach Artifact Registry, Pub/Sub, Cloud Storage and logging/monitoring).
- Cloud NAT exists in the region if workloads need to reach the internet.
- Private services access exists on the VPC if workloads use Cloud SQL private IP.

## Giving a workload access to a Google Cloud service

Grant the role to the workload's Kubernetes service account directly:

```sh
gcloud pubsub topics add-iam-policy-binding orders \
  --role roles/pubsub.publisher \
  --member "principal://iam.googleapis.com/projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/PROJECT_ID.svc.id.goog/subject/ns/NAMESPACE/sa/KSA_NAME"
```

## Things to know

- Replacing a node pool: changing machine type, disk, spot or taints recreates the pool's
  nodes. Add a new pool, move workloads, then remove the old one.
- Retiring a cluster: set `deletion_protection = false`, apply, then destroy.
- Images in another project: grant `roles/artifactregistry.reader` to the
  `node_service_account_email` output on those repositories.
- Team access by Google Group: set `rbac_security_group` and bind groups in Kubernetes RBAC.
- Optional hardening that needs something outside the module: `secrets_encryption_kms_key`
  (a KMS key) and `enable_binary_authorization` (a project policy).
