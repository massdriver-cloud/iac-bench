# Aurora PostgreSQL Global Database Module

Production Aurora PostgreSQL for services that must survive an AWS regional
failure with sub-second write loss and a few minutes of recovery time.

## What this creates

- An Aurora Global Database (`aws_rds_global_cluster`) with the primary cluster
  in `primary_region` and a promoted-capable secondary cluster in
  `secondary_region`.
- Provisioned Aurora PostgreSQL instances in both regions.
- Private database subnet groups discovered from the VPCs named after
  `environment` and the subnets tagged `tier = database`.
- Security groups that allow the VPC CIDR by default, plus explicit CIDRs or
  security-group IDs you supply.
- Customer-managed KMS keys (one per region) for storage encryption.
- IAM database authentication enabled.
- Managed master credentials stored in AWS Secrets Manager.
- TLS forced through `rds.force_ssl = 1`.
- Backups, deletion protection, CloudWatch Logs export, and Performance
  Insights.

## Usage

```hcl
service_name     = "checkout"
environment      = "apps-prod"
primary_region   = "us-east-1"
secondary_region = "us-west-2"
database_name    = "checkout"
```

Apply with:

```sh
tofu plan -var-file=minimal.tfvars
tofu apply -var-file=minimal.tfvars
```

## Regional failover

The database is already running as an Aurora Global Database. To fail over from
the primary region to the secondary region:

```sh
aws rds failover-db-cluster \
  --db-cluster-identifier checkout-apps-prod-secondary
```

The secondary becomes writable, typically in about a minute. Point the service
at the secondary cluster endpoint and rotate the global database back (or make
the secondary the new primary) after the primary region recovers.

## IAM authentication from EKS

The cluster has `iam_database_authentication_enabled = true`. EKS pods that use
IRSA can authenticate with their IAM identity using
`aws rds generate-db-auth-token` or a PostgreSQL driver that supports IAM auth.
Create database users with the `rds_iam` role and grant them the same database
permissions as the application role.