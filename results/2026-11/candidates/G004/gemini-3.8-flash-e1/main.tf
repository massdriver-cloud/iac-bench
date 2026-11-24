# Aurora PostgreSQL Production Global Database Root Module
#
# Architecture:
# - cluster.tf: Aurora Global Cluster, primary cluster, secondary cluster, cluster instances
# - networking.tf: VPC & database subnet discovery, DB subnet groups, security groups
# - parameters.tf: Cluster parameter groups (enforcing TLS/SSL, audit logging) & DB parameter groups
# - kms.tf: Dedicated customer-managed KMS encryption keys in both regions with automatic rotation
# - iam.tf: Enhanced Monitoring IAM role and IAM Database Authentication connect policy for EKS workloads
# - monitoring.tf: CloudWatch log groups for PostgreSQL audit logs and metric alarms (RPO / replication lag, CPU)
# - providers.tf: AWS providers for primary and secondary disaster recovery regions
# - variables.tf: Input variables with production defaults
# - outputs.tf: Primary & secondary endpoints, credentials in Secrets Manager, IAM policies, and resource IDs
