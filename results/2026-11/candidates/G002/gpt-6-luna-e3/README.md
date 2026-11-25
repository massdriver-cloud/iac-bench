# Standard Cloud SQL for PostgreSQL

A standalone OpenTofu root module for a PostgreSQL Cloud SQL instance, its initial database, and optional Cloud IAM database users. It uses the Google provider's environment-based credentials (`GOOGLE_APPLICATION_CREDENTIALS`, ADC, or equivalent); no service-account key is stored in the module.

## Network and identity assumptions

- Pass the self-link of the environment's custom VPC (`apps-dev`, `apps-staging`, or `apps-prod`). Private Services Access must already exist on that VPC; the module intentionally does not create or own shared network infrastructure.
- Instances have **no public IPv4 address** and require encrypted TLS connections. Applications must connect over the VPC using private IP (or a compatible Cloud SQL connector).
- Cloud IAM database authentication is enabled. `iam_users` provisions Cloud SQL's IAM database-user records, but does not change project IAM policy. Separately grant identities the Cloud SQL IAM roles required by your connection path (typically `roles/cloudsql.instanceUser`, and `roles/cloudsql.client` when using a connector). PostgreSQL database/schema/table privileges remain DBA-managed.
- No password-based application users are created by this module. Workloads and engineers should use their own Google identities for auditable authentication.

## Standard settings

The defaults provide a regional (HA) instance, SSD storage with automatic growth, seven retained backups and seven days of point-in-time recovery logs, a stable maintenance window, Cloud SQL Query Insights, and deletion protection. TLS is enforced; client addresses are not recorded in Query Insights to avoid collecting that extra client metadata. PostgreSQL is version 16 by default. DBAs can select the engine version, tier, availability, storage size, backup/maintenance time, PostgreSQL flags, labels, and IAM database users through inputs.

Deletion protection is enabled at both the provider resource and Cloud SQL settings layers. Before retiring an instance, deliberately set `deletion_protection = false` and apply that change first.

## Minimal example

See `minimal.tfvars` for a small, literal example. Supply the five required inputs for your project, instance, region, VPC, and initial database, then run:

```sh
tofu plan -var-file=minimal.tfvars
tofu apply -var-file=minimal.tfvars
```

To provision IAM identities, add entries such as:

```hcl
iam_users = {
  "engineer" = {
    email = "engineer@example.com"
    type  = "CLOUD_IAM_USER"
  }
  "workload" = {
    email = "my-workload@my-project.iam.gserviceaccount.com"
    type  = "CLOUD_IAM_SERVICE_ACCOUNT"
  }
}
```
