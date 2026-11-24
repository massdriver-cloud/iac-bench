# ---------------------------------------------------------------------------
# Production Aurora PostgreSQL module (cross-region disaster recovery)
#
# What this module builds, per service instantiation:
#   * An Aurora global database with a PRIMARY cluster in `primary_region`
#     and a SECONDARY (hot standby) cluster in `secondary_region`.
#     Aurora global database replication is storage-level and typically
#     lags < 1 second, so a regional failover loses at most a few seconds
#     of writes and the promoted cluster serves again in about a minute.
#   * Multi-AZ capacity in each region (`instance_count >= 2`), so a single
#     AZ failure is absorbed inside the region without any failover to DR.
#   * Discovery of the network team's per-environment VPC (`apps-<env>`)
#     and its private database subnets (tagged `tier = database`).
#   * Encryption at rest with a customer-managed KMS key in each region,
#     TLS-only client connections, IAM database authentication for the
#     EKS workloads, and a master password held in Secrets Manager.
#
# Primary access path for services is IAM database authentication (they
# already reach AWS through IAM roles), so no credentials travel through
# the platform and access follows the same IAM revocation story as the
# rest of the workload.
# ---------------------------------------------------------------------------

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}
