# Cloud SQL PostgreSQL module

Reusable module for the DBA team to stand up and manage Cloud SQL for
PostgreSQL instances consistently across `apps-dev`, `apps-staging`, and
`apps-prod`.

## Design decisions (owned by the module)

These are fixed so no two instances drift apart:

- **PostgreSQL 15**, pinned via `database_version`.
- **Private networking only** — `ipv4_enabled = false` and the instance is
  attached to the VPC that the network team already owns (private services
  access is expected to exist there). No public IP, no authorized networks.
- **Identity-based access** — the `cloudsql.iam_authentication` flag is always
  on, and every database user is created as a `CLOUD_IAM_USER` whose name is a
  Google principal email. No stored database passwords.
- **TLS required** — `ssl_mode = TRUSTED_CLIENT_CERTIFICATE_REQUIRED`.
- **Daily automated backups with PITR** — always on, with transaction-log
  retention for point-in-time recovery.
- **Deletion protection** on by default, with a matching `prevent_destroy`
  lifecycle guard.
- **Query Insights** enabled on every instance.
- **Random instance name suffix** so names never collide after a delete/recreate
  cycle in the same project.

## What the DBA still decides

Everything else is a variable: sizing (`tier`, disk), availability
(`availability_type`, `zone`), backup timing/retention, maintenance windows,
the attached VPC network, labels, database name, database flags, and the map of
PostgreSQL roles to Google identities.

## Minimal usage

```hcl
module "postgres" {
  source = "../path/to/this/module"

  name         = "orders"
  project_id   = "my-project"
  region       = "us-central1"
  network_name = "apps-dev"
  environment  = "dev"
  database_name = "orders"

  users = {
    app_svc = "app-svc@my-project.iam.gserviceaccount.com"
  }
}
```

Connecting applications authenticate with their Google identity (Service
Account / Workload Identity on GKE, or instance service account on Compute
Engine) over the private IP.