# Aurora PostgreSQL global database module

This module provisions a production Aurora PostgreSQL global database across two
AWS regions. It is intended to be used directly as an OpenTofu root module.

## How it works

- Primary Aurora cluster in `primary_region`.
- Cross-region Aurora secondary cluster in `secondary_region`, attached to the
  same global database.
- Aurora storage-level replication keeps cross-region recovery point close to
  real time (typically under a second, and no more than a few seconds).
- Both clusters use private database subnets only (`publicly_accessible = false`),
  envelope encryption via customer-managed KMS keys, `rds.force_ssl`, IAM
  database authentication, deletion protection, Performance Insights, enhanced
  monitoring, and CloudWatch PostgreSQL log export.

## Existing network requirements

Each region must already contain:

- One VPC for the target environment.
- Private database subnets tagged `tier = database` in that VPC.

The module can discover those subnets automatically. For environments that want
to pass explicit subnet IDs (or that do not have the subnets discoverable at
plan time), use `primary_subnet_ids` and `secondary_subnet_ids`.

## Minimal usage

```hcl
name              = "checkout"
environment       = "apps-prod"
primary_region    = "us-east-1"
secondary_region  = "us-west-2"
primary_vpc_id    = "vpc-..."
secondary_vpc_id  = "vpc-..."
database_name     = "checkout"
allowed_cidr_blocks = ["10.0.0.0/16"]
```

## Region failover

Aurora Global Database does not automatically fail over. The promotion path is
intentionally manual so it can be tested and coordinated with the application
edge. During a regional outage:

1. Promote the secondary cluster to a standalone primary cluster.
2. Point the service at the promoted cluster's writer endpoint.
3. Run `tofu plan` again after the outage to repair/recreate any failed regional
   resources.

The secondary endpoint is available in `secondary_cluster_endpoint` output.