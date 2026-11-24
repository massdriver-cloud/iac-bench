# Standard Cloud SQL PostgreSQL

This root module is the DBA team's baseline for Cloud SQL for PostgreSQL. It creates an instance, optional additional databases, and optional IAM database principals. It intentionally does **not** create VPCs, subnets, allocated IP ranges, private services access connections, Google identities, or built-in/password users.

## Non-negotiable baseline

- Private IP only in the supplied VPC; no public IP or authorized networks.
- TLS-only connections (`ENCRYPTED_ONLY`). Cloud SQL connectors/Auth Proxy can use the instance connection name output.
- IAM database authentication enabled for every instance. Only `CLOUD_IAM_USER` and `CLOUD_IAM_SERVICE_ACCOUNT` users are exposed by the module.
- Automated backups, point-in-time recovery, transaction-log retention, and bounded backup retention.
- SSD storage and storage autoresize by default; regional HA by default (DBAs can deliberately choose `ZONAL`).
- Stable maintenance track and a consistent weekly maintenance window.
- Query Insights, connection/disconnection logging, lock-wait logging, and DDL logging.
- Deletion protection at both Cloud SQL and OpenTofu layers. Additional databases use `ABANDON` on removal by default.
- A `managed_by=opentofu` label, plus caller-supplied labels.

PostgreSQL version, edition, machine tier, HA choice, disk configuration, preferred zone, backup policy, maintenance window, additional flags, labels, databases, and IAM principals are the DBA-controlled inputs. Security-critical IAM authentication and private/TLS-only connectivity cannot be switched off through inputs.

## Minimal use

The included `minimal.tfvars` is a syntactically complete example:

```hcl
project_id        = "my-gcp-project"
region            = "us-central1"
instance_name     = "postgres-dev"
network_self_link = "projects/my-gcp-project/global/networks/apps-dev"
```

```sh
tofu init
tofu plan -var-file=minimal.tfvars
tofu apply -var-file=minimal.tfvars
```

Replace the example project with the target Google Cloud project. The target VPC (`apps-dev`, `apps-staging`, or `apps-prod`) must already exist and the network team must already have configured private services access. For Shared VPC, pass the host project's full network self link.

## Databases and identities

```hcl
databases = {
  orders = {}
  reporting = {
    charset   = "UTF8"
    collation = "en_US.UTF8"
  }
}

iam_users = {
  "dba@example.com" = "CLOUD_IAM_USER"
  "orders-sa@my-gcp-project.iam.gserviceaccount.com" = "CLOUD_IAM_SERVICE_ACCOUNT"
}
```

For each entry, the module:

1. creates the Cloud SQL IAM database user;
2. grants `roles/cloudsql.instanceUser` at project scope, which Cloud SQL requires for IAM login; and
3. grants `roles/cloudsql.client` at project scope for Auth Proxy/connector access.

Cloud SQL's IAM integration exposes these login/connector roles as project IAM grants. Because the grants are project-scoped, they permit the corresponding IAM operations against other instances in the same project too; actual database login still requires the identity to be provisioned as a SQL user on the target instance. Use separate projects where stronger instance-level IAM isolation is required. The bindings are non-authoritative and do not replace the project's existing policy.

Applying a configuration with IAM users therefore requires Project IAM Admin (or equivalent narrower permissions) in addition to Cloud SQL and SQL user administration. Google users and service accounts must already exist. GKE workloads should use Workload Identity to impersonate their listed Google service account; Compute Engine workloads should run as theirs.

IAM login identifies the database session, but PostgreSQL object privileges still need to be granted by the DBA inside each database. Creating an IAM SQL user does not implicitly grant table or schema privileges.

## Deliberate destruction

With the default `deletion_protection = true`, OpenTofu and Cloud SQL both reject deletion. To retire an instance deliberately, first apply with `deletion_protection = false`, review the resulting plan, and only then run the destroy operation. Removing an additional database from `databases` abandons it on the instance by default rather than dropping it; use that database's `deletion_policy = "DELETE"` only when a drop is intended.
