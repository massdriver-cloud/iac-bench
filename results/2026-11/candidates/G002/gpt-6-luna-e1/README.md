# Standard Cloud SQL for PostgreSQL

This root module provisions one Cloud SQL for PostgreSQL instance in an existing
custom VPC. It deliberately creates a private-IP-only instance (no authorized
public networks), requires encrypted connections, enables IAM database
authentication, automated backups and point-in-time recovery, and enables Query
Insights. It also enables the Cloud SQL Admin API. The VPC must already have
Private Services Access configured; network allocation and VPC lifecycle remain
owned by the network team.

## Required inputs

- `project_id`: project for the instance.
- `region`: instance region.
- `instance_name`: Cloud SQL instance name.
- `network`: VPC network self-link, such as
  `projects/example-project/global/networks/apps-dev`.

See `variables.tf` for configurable engine version, tier, availability, storage,
maintenance/backup windows, extra PostgreSQL flags, databases, IAM login users,
and labels. Defaults encode the common baseline; DBAs can explicitly tune
workload-specific capacity, resilience, and PostgreSQL settings. Deletion
protection is enabled by default and must be intentionally disabled before
removing an instance.

`iam_database_users` is a map keyed by IAM identity email with value
`CLOUD_IAM_USER` or `CLOUD_IAM_SERVICE_ACCOUNT`. This creates Cloud SQL IAM
login users; it does not create identities or grant PostgreSQL database roles
and privileges. The identity must separately have the Cloud SQL Instance User
IAM role to log in (and Cloud SQL Client when using a connector/proxy). Manage
those project-level IAM grants and PostgreSQL grants through the appropriate
identity/database access workflows.

Use `minimal.tfvars` as the smallest example instantiation. Cloud credentials
are obtained from the Google provider's normal environment configuration.
