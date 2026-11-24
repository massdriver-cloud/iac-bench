# SRE App Service module

One standard way to run the product teams' containerized HTTP APIs on Azure
App Service. Point it at a container image and it produces a service that is
scaled, healthy, rolled out safely, and observable - without per-app tuning of
App Service internals.

The module is a standalone OpenTofu root module: apply it directly with a
tfvars file per service (see `minimal.tfvars` for the smallest valid one).

## What it deploys

| Concern | What you get |
| --- | --- |
| Capacity | Linux App Service plan (P1v3 default) with CPU-driven autoscaling between `min_instances` and `max_instances`. The plan's live instance count is owned by the autoscale engine, not reconciled on every apply. |
| Availability | Always On, HTTPS-only, multi-instance capacity floor, HTTP/2, no session affinity; unhealthy instances are removed from rotation automatically. |
| Health | `health_check_path` probed on every instance; failing instances leave the load balancer and are restarted. Optional auto-heal recycling on 5xx/slow-request bursts. |
| Rollouts | A `staging` deployment slot mirroring production (same settings, same health checks) so candidate builds are verified before promotion. |
| Observability | Dedicated Log Analytics workspace, workspace-based Application Insights (connection string injected as `APPLICATIONINSIGHTS_CONNECTION_STRING`), platform/HTTP/console/audit logs for the app and its slot, plan capacity metrics, and baseline metric alerts. |
| Identity | System-assigned managed identity for the app and the slot; optional `AcrPull` grant on your container registry so image pulls need no stored credentials. |

Hardened defaults applied everywhere: FTPS and FTP/webdeploy basic auth
disabled, TLS 1.2 minimum, `/home` app-service storage off, standard tags
(`managed_by`, `module`, `app`).

## Quick start

```hcl
name            = "orders-api"
location        = "westeurope"
container_image = "myregistry.azurecr.io/team/orders-api:1.4.2"
acr_resource_id = "/subscriptions/<sub>/resourceGroups/shared-rg/providers/Microsoft.ContainerRegistry/registries/myregistry"

alert_emails = ["sre-oncall@example.com"]
```

Everything else has a sensible default. Apply with:

```sh
tofu init
tofu apply -var-file=orders-api.tfvars
```

## Capacity

- `min_instances` / `max_instances` are the autoscale bounds (default 2-6).
  Set them equal for a fixed-size plan.
- The service plan is created at `min_instances` and the autoscale profile
  then owns the live count; `worker_count` changes are deliberately ignored
  after creation so applies never fight the autoscale engine.
- Rules: scale out +1 when average CPU > 70% for 10 min (5 min cooldown),
  scale in -1 below 25% (10 min cooldown).

## Rolling out a new build

1. Set `staging_container_image` to the candidate build and apply. Only the
   staging slot changes; production keeps serving.
2. Verify on the `staging_url` output - the slot runs the same health checks,
   so an unhealthy build is visible before promotion.
3. Promote by moving the image reference into `container_image` (and clearing
   `staging_container_image`), then apply. If you prefer warm-swap semantics,
   `az webapp deployment slot swap` against the module-created slot works too.

Alternatively, `container_image` can be updated in one step; App Service
updates production and the health check gates instances back into rotation.

## Health and alerting

- Set `health_check_path` to a real endpoint that returns 2xx (default `/`).
  Instances failing it are evicted from the load balancer after
  `health_check_eviction_time_in_minutes` and restarted.
- `auto_heal = { ... }` opts into process recycling on error/slow-request
  bursts; off by default since health check eviction usually suffices.
- Alerts (HTTP 5xx rate, health check score, plan CPU saturation) are created
  as soon as there is a destination: set `alert_emails` and/or point
  `action_group_ids` at your existing paging groups. Thresholds via
  `alert_thresholds`.

## Observability

- All platform logs (HTTP, console, app, audit, IPSec, platform), site
  metrics, and plan capacity metrics flow into the service's Log Analytics
  workspace, retained `log_retention_days` (default 30).
- The container gets `APPLICATIONINSIGHTS_CONNECTION_STRING` injected;
  instrumentation sampling is `app_insights_sampling_percentage`.

## Registry authentication

- **Azure Container Registry (recommended):** set `acr_resource_id`. The app
  and slot pull with their managed identities; the module grants `AcrPull`.
  The login server is derived as `https://<registry>.azurecr.io` (override
  with `container_registry_url` if needed).
- **Other private registries:** set `container_registry_url` plus
  `container_registry_username` / `container_registry_password`.
- **Public images:** just `container_image` (defaults to Docker Hub).

## Networking

Set `virtual_network_subnet_id` (subnet delegated to `Microsoft.Web`) to
integrate the app with a VNet for private backends.

## Inputs (summary)

Required: `name`, `location`, `container_image`.

| Variable | Default | Notes |
| --- | --- | --- |
| `sku_name` | `P1v3` | Standard+ required for slots/autoscale/Always On |
| `min_instances` / `max_instances` | `2` / `6` | autoscale bounds |
| `create_resource_group` / `resource_group_name` | `true` / `null` | own RG (`<name>-rg`) or existing one |
| `acr_resource_id` | `null` | managed-identity pulls + AcrPull grants |
| `container_registry_url/_username/_password` | `null` | non-ACR registry auth |
| `app_settings` | `{}` | env vars for the container |
| `websockets_enabled` | `false` | for long-lived sockets |
| `virtual_network_subnet_id` | `null` | VNet integration |
| `health_check_path` | `/` | must return 2xx |
| `health_check_eviction_time_in_minutes` | `10` | eviction grace |
| `auto_heal` | `null` | optional recycle policy |
| `enable_staging_slot` / `staging_slot_name` | `true` / `staging` | rollout slot |
| `staging_container_image` | `null` | candidate build (defaults to prod image) |
| `log_retention_days` | `30` | workspace retention (30-730) |
| `app_insights_sampling_percentage` | `100` | telemetry sampling |
| `alert_emails` / `action_group_ids` | `[]` / `[]` | alert destinations |
| `alert_thresholds` | see variables.tf | 5xx / health / CPU thresholds |
| `tags` | `{}` | merged with module tags |

## Outputs

`app_url`, `default_hostname`, `staging_url` (candidate verification
endpoint), `app_service_id`, `service_plan_id`, `resource_group_name`,
`log_analytics_workspace_id`, `application_insights_id`,
`application_insights_connection_string` (sensitive),
`managed_identity_principal_id` (for granting access to backing services),
`staging_managed_identity_principal_id`.
