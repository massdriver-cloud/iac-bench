# GKE Standard cluster (platform standard)

Root OpenTofu module that creates one production-grade GKE Standard cluster on
the network team's VPC. One state per cluster.

```hcl
# shared-01.tfvars
name        = "shared-01"
environment = "prod"        # staging | prod  -> VPC apps-staging | apps-prod
region      = "us-central1" # subnet apps-<environment>-gke-<region>, ranges "pods" / "services"
```

```sh
tofu apply -var-file=shared-01.tfvars
$(tofu output -raw get_credentials_command)
```

The project comes from `GOOGLE_PROJECT` / `GOOGLE_CLOUD_PROJECT` unless
`project_id` is set. See `examples/prod.tfvars` for a fuller definition.

## What you fill in

| Variable | Required | Purpose |
|---|---|---|
| `name` | yes | Cluster name |
| `environment` | yes | `staging` or `prod`; selects the VPC and the release channel |
| `region` | yes | US region; selects the subnet |
| `node_pools` | no | Pools keyed by name: machine type, per-zone min/max, spot, labels, taints. Default: one `general` pool of `e2-standard-4`, 1-3 nodes per zone |
| `zones` | no | Restrict node zones (at least two). Default: GKE's zones for the region |
| `release_channel` | no | Default `REGULAR` in staging, `STABLE` in prod |
| `maintenance_window` | no | Default Tue-Thu 08:00-12:00 UTC |
| `master_authorized_networks` | no | Private CIDRs allowed on the control plane's private IP |
| `rbac_security_group` | no | `gke-security-groups@<domain>` for group-based RBAC |
| `secrets_encryption_kms_key` | no | Bring your own KMS key instead of the module-created one |
| `deletion_protection` | no | Default `true` |
| `labels` | no | Extra resource labels |

## What the module decides for you

**Resilience**
- Regional cluster: replicated control plane, nodes spread over the region's zones.
- Node pools autoscale, auto-repair, auto-upgrade and upgrade by surge (one
  extra node first, zero unavailable).
- Release channel upgrades, staging one channel ahead of prod, restricted to a
  mid-week, middle-of-the-night maintenance window.
- At least one on-demand, untainted pool with a node in every zone is required.
- Deletion protection is on.

**Security**
- Private nodes (no public IPs) and no public control plane IP endpoint. The
  Kubernetes API is reached through the DNS endpoint, which authenticates and
  authorises every request with IAM (the caller needs the
  `container.clusters.connect` permission on the cluster) before Kubernetes
  RBAC applies as usual.
- Workload Identity on the cluster and every pool. Workloads get to Pub/Sub,
  Cloud Storage, Cloud SQL etc. by granting IAM roles to the principal shown in
  the `workload_identity_principal_format` output; no key files.
- Nodes run as a dedicated service account with only the node role and
  Artifact Registry read access, never the Compute Engine default account.
- Kubernetes Secrets encrypted with a per-cluster Cloud KMS key (90-day rotation).
- Dataplane V2, so Kubernetes `NetworkPolicy` is enforced between teams'
  namespaces (you still have to write the policies).
- Shielded nodes with secure boot, Container-Optimized OS, legacy metadata
  endpoints and the kubelet read-only port off, no client certificates, no ABAC.

**Operations**
- System, workload and control plane logs; system, control plane and
  kube-state metrics; Managed Prometheus.
- GKE cost allocation, so billing export breaks cost down by namespace.
- Persistent Disk and Cloud Storage FUSE CSI drivers, NodeLocal DNSCache, HPA, VPA.

## Things to know

- **Internet egress.** Nodes have no public IPs. Pulling from Artifact Registry
  works through Private Google Access (the plan warns if the subnet lacks it);
  anything on the public internet (Docker Hub, third-party APIs) needs Cloud
  NAT on the VPC, which is the network team's to provide.
- **Images in other projects.** Grant `roles/artifactregistry.reader` on those
  repositories to the `node_service_account_email` output.
- **Decommissioning.** Set `deletion_protection = false`, apply, then destroy.
  The KMS key ring cannot be deleted by Google Cloud and stays behind, empty
  and free; key versions are scheduled for destruction and recoverable for 30 days.
- **APIs.** The module enables `container.googleapis.com` and
  `cloudkms.googleapis.com` and never disables them.
- **Bring-your-own KMS key.** It must be in the cluster's region and the GKE
  service agent (`service-<project-number>@container-engine-robot.iam.gserviceaccount.com`)
  needs `roles/cloudkms.cryptoKeyEncrypterDecrypter` on it before you apply.
