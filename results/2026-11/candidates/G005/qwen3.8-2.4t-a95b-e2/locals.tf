locals {
  # The network team creates one GKE subnet per region in each environment VPC,
  # named "<vpc>-gke-<region>", with secondary ranges "pods" and "services".
  subnetwork_name = coalesce(var.subnetwork_name, "${var.network_name}-gke-${var.region}")

  # Workload Identity pool for this project: product teams map Kubernetes
  # service accounts to their Google service accounts
  # (roles/iam.workloadIdentityUser) to reach Pub/Sub, Cloud Storage,
  # Cloud SQL, etc.
  workload_pool = "${var.project_id}.svc.id.goog"

  # Dedicated, least-privilege service account for the nodes (instead of the
  # project's default Compute Engine service account).
  node_sa_account_id = substr("gke-${var.cluster_name}-nodes", 0, 30)

  # Minimal OAuth scopes recommended by Google for GKE nodes. Access to other
  # Google Cloud services is granted to workloads via Workload Identity, not
  # via node scopes.
  node_oauth_scopes = [
    "https://www.googleapis.com/auth/devstorage.read_only",
    "https://www.googleapis.com/auth/logging.write",
    "https://www.googleapis.com/auth/monitoring",
    "https://www.googleapis.com/auth/trace.append",
  ]
}
