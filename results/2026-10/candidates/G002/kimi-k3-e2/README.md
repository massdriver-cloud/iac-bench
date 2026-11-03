# Standard Cloud SQL for PostgreSQL

The DBA team's module for every Cloud SQL for PostgreSQL instance. It encodes
the decisions that must be identical everywhere, and exposes — as inputs —
the decisions that genuinely belong to the DBAs.

## Enforced on every instance (not re-decided per instance)

| Decision              | Standard |
| --------------------- | -------- |
| Connectivity          | Private IP only (`ipv4_enabled = false`) on the environment VPC, via the private services access the network team has already provisioned on `apps-dev` / `apps-staging` / `apps-prod` |
| Authentication        | IAM database authentication forced on (`cloudsql.iam_authentication = "on"`), merged last so `database_flags` cannot switch it off. Humans and workloads log in with their Google identities — that is what the security team audits |
| Transport encryption  | `ssl_mode = ENCRYPTED_ONLY` by default (relaxing it is possible but must be a conscious input) |
| Observability         | Query Insights always enabled (knobs tunable) |
| Data protection       | Automated backups + point-in-time recovery on by default |
| Safety                | `deletion_protection = true` by default |
| Activation / pricing  | `ALWAYS` / `PER_USE` |

## Owned by the DBAs (module inputs)

Instance identity and placement (`project_id`, `region`, `name`, `network`),
sizing (`edition`, `tier`, disk floor/type/autoresize), PostgreSQL version,
`availability_type` (ZONAL vs REGIONAL HA), backup window and retention,
maintenance window, `database_flags`, `databases`, `iam_users`, optional CMEK,
optional password policy for built-in roles, labels.

## Usage

```hcl
module "orders_db" {
  source = "./modules/cloudsql-postgres"

  project_id = "apps-prod"
  region     = "europe-west1"
  name       = "pg-orders-prod-01"
  network    = "apps-prod"

  tier              = "db-custom-4-16384"
  availability_type = "REGIONAL"

  databases = {
    orders = {}
  }

  iam_users = {
    orders_service = {
      email = "orders-svc@apps-prod.iam.gserviceaccount.com"
      type  = "CLOUD_IAM_SERVICE_ACCOUNT"
    }
    dba_group = {
      email = "dba@example.com"
      type  = "CLOUD_IAM_GROUP"
    }
  }

  database_flags = {
    log_min_duration_statement = "250"
  }

  labels = {
    environment = "prod"
    team        = "orders"
  }
}
```

## Assumptions

- Private services access is already configured on the target VPC network
  (owned by the network team); the module deliberately does not manage it.
- The Cloud SQL Admin API is enabled in the target project.
- IAM principals named in `iam_users` already exist.
