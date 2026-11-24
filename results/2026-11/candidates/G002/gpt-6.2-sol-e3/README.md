# Cloud SQL for PostgreSQL

This OpenTofu root module manages one Cloud SQL primary instance. Use a separate state per instance. Set the Google provider project (for example, `GOOGLE_PROJECT`) and supply credentials through the environment. The Cloud SQL Admin and Compute Engine APIs must already be enabled. The project must contain `apps-dev`, `apps-staging`, or `apps-prod` as selected by `environment`, with private services access and available address space. This module reads that network; it does not create or modify it or its peering.

```sh
tofu init
tofu plan -var-file=minimal.tfvars
```

`minimal.tfvars` creates the instance only. `example.tfvars` also shows application database and identity enrollment; replace the sample emails with identities that exist before applying. The deployer needs Cloud SQL management and network read permissions. If enrolling identities, the deployer also needs project IAM policy read/write permissions because the module manages conditional grants. It does not manage the identities themselves.

### What is standardized

- **Network and transport:** Private IP only, on `apps-${environment}`. All connections require encryption. Prefer Cloud SQL Auth Proxy or a language connector in private-IP mode; it still needs VPC reachability to the instance. For direct PostgreSQL connections, configure TLS with CA/identity verification on the client; the server's encryption requirement alone does not verify server identity for the client.
- **Login:** IAM database authentication is always enabled. The module provisions no password users and sets no built-in account passwords. The Cloud SQL built-in administrative account is outside the module's identity enrollment; do not use shared admin credentials for routine access. For each enrolled identity the module creates a PostgreSQL IAM login and grants `roles/cloudsql.instanceUser` for IAM login and `roles/cloudsql.client` for using the Auth Proxy or a connector. The grants are additive and scoped to this instance by an IAM condition. The module enables PostgreSQL connection and disconnection logging; statement auditing and log retention are separate decisions.
- **Recovery and guardrails:** Daily automated backups (14 retained), seven days of point-in-time recovery logs, automatic disk growth, and deletion protection in both OpenTofu and Cloud SQL. To intentionally delete the instance, first set `deletion_protection = false` and apply, then review the destroy plan. Removing a database from `databases` plans to delete it, independently of instance deletion protection; review plans and recovery needs before doing so.

### What DBAs choose

Set the instance name, environment, region, PostgreSQL version, and tier. Choose edition, HA, creation-time storage size, backup start time, maintenance window, extra supported PostgreSQL flags, databases, and approved identities as needed. The default edition is Enterprise; production defaults to regional HA, and other environments default to zonal. `initial_disk_size_gb` only affects creation: Cloud SQL can grow storage after creation and OpenTofu ignores that size drift rather than trying to shrink the disk.

Use `connection_name` for a connector and `private_ip_address` for direct connections. Configure the connector for private IP **and** automatic IAM authentication (for Auth Proxy v2, `--private-ip --auto-iam-authn`). GKE and Compute Engine workloads should authenticate as the enrolled Google service account. Its IAM grant uses the full email; its PostgreSQL login omits `.gserviceaccount.com`. The `iam_database_logins` output gives the exact login names. For manual IAM database authentication, use a short-lived IAM access token rather than a static password.

IAM login and connector roles do not assign application-specific SQL privileges. DBAs still manage database ownership, `CONNECT`, and schema/object grants in PostgreSQL. Review default `PUBLIC` privileges when restricting database access. Before removing managed IAM database users, transfer any objects they own and clean up dependent grants so PostgreSQL can drop the roles.
