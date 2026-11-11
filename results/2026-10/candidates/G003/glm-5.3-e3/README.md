# Standard App Service module

One opinionated way for the SRE team to run every product team's containerized
HTTP API on Azure App Service (Linux). Point it at a container image, choose a
capacity tier, and you get a production-shaped service: autoscaling, zone
spreading where the SKU allows it, platform health checks, a warm staging slot,
and full observability wired to your inbox.

The module owns every App Service internal so nobody hand-tunes apps anymore:
SKU selection, always-on, TLS floor, FTP/basic-auth posture, health-check
eviction, logging plumbing, autoscale policy shape, and diagnostic categories
are all decided once, here. SREs set *intent*: which image, how much capacity,
how available, how healthy, how to roll out, and who gets notified.

Each instantiation of this module is one service (one plan : one app), so
capacity and blast radius are always per-service.

## What it creates

| Concern | Resources |
|---|---|
| Placement | `azurerm_resource_group` (unless you pass `resource_group_name`) |
| Capacity | `azurerm_service_plan` (Linux, tier-mapped SKU) + `azurerm_monitor_autoscale_setting` |
| The service | `azurerm_linux_web_app` running your container (system-assigned identity) |
| Rollouts | `azurerm_linux_web_app_slot` "staging" |
| Observability | `azurerm_log_analytics_workspace`, `azurerm_application_insights`, diagnostic settings on app + slot, `azurerm_monitor_action_group`, 4 `azurerm_monitor_metric_alert`s |
| Private registry | `azurerm_role_assignment` (AcrPull) on app + slot identities when `container_registry_id` is set |

## Capacity

| tier | SKU | vCPU / RAM | zone spreading | instance ceiling |
|---|---|---|---|---|
| `small` (default) | S1 | 1 / 1.75 GB | no | 10 |
| `medium` | P1v3 | 2 / 8 GB | yes | 30 |
| `large` | P2v3 | 4 / 16 GB | yes | 30 |
| `xlarge` | P3v3 | 8 / 32 GB | yes | 30 |

`min_instances` / `max_instances` are the autoscale floor and ceiling
(defaults: 2 and 5 — no single point of failure, room to breathe). The plan
starts at the floor. Scale-out triggers at CPU **or** memory > 70% over 10
minutes (+1 instance, 5-minute cooldown); scale-in requires CPU **and** memory
< 25% over 20 minutes (-1 instance, 10-minute cooldown), so the service doesn't
flap. The module refuses `max_instances` below the floor or above the tier's
ceiling.

## Availability

- Premium v3 tiers (`medium`+) are zone-redundant by platform default in
  zone-capable regions; the module additionally enables even zone balancing
  across the zones and enforces an instance floor of at least 3, because that
  is what it takes to actually occupy all three zones.
- `zone_redundant` controls that behaviour: `null` (default) is automatic — on
  for Premium v3 tiers, off for `small`. Setting it `true` on `small` fails
  fast with a clear precondition error; setting `false` on a Premium tier
  opts out of forced balancing.
- Always-on is enforced, the app is HTTPS-only with TLS 1.2 minimum (SCM
  included), HTTP/2 and WebSockets are on, FTP is disabled, FTP/WebDeploy
  basic auth is disabled, and session affinity is off (stateless APIs).

## Health

`health_probe_path` (default `/`) is probed by the platform itself. An instance
failing the probe for 5 consecutive minutes (`health_check_eviction_time_in_min`)
is evicted from the load balancer without a redeploy, and a `HealthCheckStatus`
alert fires while that is happening. The same probe config applies to the
staging slot.

## Rollouts

A `staging` slot (same image, same settings, same health checks, its own
diagnostics) is created by default. Standard flow: push the new image tag to
staging, verify on the staging hostname, then promote:

```sh
az webapp deployment slot swap \
  --resource-group $(tofu output -raw resource_group_name) \
  --name $(tofu output -raw app_name) \
  --slot staging --target-slot production
```

Set `staging_auto_swap = true` if you want promotion to happen automatically on
every deployment to staging; it is deliberately off by default so promotion is
an explicit act. To skip slots entirely (e.g. throwaway environments), set
`create_staging_slot = false`.

## Observability

- A per-service Log Analytics workspace (`log_retention_days`, default 30) is
  the single sink. Both the app and the slot ship
  `AppServiceHTTPLogs`, `AppServiceConsoleLogs` (your container's stdout/stderr),
  `AppServiceAppLogs`, `AppServiceAuditLogs`, `AppServiceIPSecAuditLogs`,
  `AppServicePlatformLogs` and all metrics, into dedicated category tables.
  Bounded filesystem logging is enabled on the apps so those categories have
  content from day one.
- Workspace-based App Insights comes with the service;
  `APPLICATIONINSIGHTS_CONNECTION_STRING` / `APPINSIGHTS_INSTRUMENTATIONKEY`
  are already in the container's environment — if the image ships an
  OpenTelemetry/App Insights SDK, telemetry starts flowing with zero wiring.
- Alerts (via `alert_emails`): health check failing (sev 1), >25 HTTP 5xx per
  5 min (sev 2), plan CPU > 85% for 15 min (sev 3), plan memory > 90% for
  15 min (sev 3). Autoscale events email the same list. With `alert_emails`
  empty the alerts still exist and evaluate — they just notify nobody yet.

## Private registries

`container_registry_id` (ACR resource ID): the module turns on
managed-identity registry auth and grants AcrPull to the app's and the staging
slot's system-assigned identities. Nothing to hand out, nothing in
tfvars/state. Non-ACR private registries that need credentials are
intentionally out of scope (no secrets in state).

## Example

```hcl
module "orders_api" {
  source = "."

  name            = "orders-api"
  environment     = "prod"
  location        = "northeurope"
  container_image = "myacr.azurecr.io/team/orders-api:1.4.2"
  container_port  = 8080

  tier          = "medium"
  min_instances = 3
  max_instances = 12

  health_probe_path = "/healthz"
  alert_emails      = ["sre-oncall@example.com"]

  container_registry_id = "/subscriptions/.../resourceGroups/shared/providers/Microsoft.ContainerRegistry/registries/myacr"
}
```

`minimal.tfvars` is the smallest valid instantiation (two required variables).

## Inputs

| Name | Type | Default | Notes |
|---|---|---|---|
| `name` | string | *required* | 3–30 chars, `[a-z0-9-]`, DNS-safe |
| `container_image` | string | *required* | `"[registry/]repo[:tag]"` |
| `environment` | string | `"dev"` | 2–12 chars, used in names + tags |
| `location` | string | `"eastus"` | ignored when reusing a resource group |
| `resource_group_name` | string | `null` | reuse an existing RG; `null` = module creates `rg-<name>-<env>` |
| `subscription_id` | string | `null` | provider override, else environment default |
| `tags` | map(string) | `{}` | merged over module tags |
| `container_port` | number | `80` | container's listening port |
| `container_registry_id` | string | `null` | ACR ID → managed-identity pulls + AcrPull grants |
| `tier` | string | `"small"` | `small`/`medium`/`large`/`xlarge` |
| `min_instances` | number | `2` | autoscale floor (≥3 when zone-spread) |
| `max_instances` | number | `5` | autoscale ceiling |
| `zone_redundant` | bool | `null` | `null` = auto (on for Premium v3 tiers) |
| `health_probe_path` | string | `"/"` | platform health probe |
| `create_staging_slot` | bool | `true` | blue/green staging slot |
| `staging_auto_swap` | bool | `false` | auto-promote staging on deploy |
| `alert_emails` | list(string) | `[]` | action group recipients |
| `log_retention_days` | number | `30` | Log Analytics retention |
| `app_settings` | map(string) | `{}` | extra app settings, app + slot |

## Outputs

`resource_group_name`, `service_plan_id`, `app_service_id`, `app_name`,
`default_hostname`, `url`, `staging_hostname`, `log_analytics_workspace_id`,
`application_insights_connection_string` (sensitive),
`managed_identity_principal_id`.

## Non-goals

VNet integration / private endpoints, custom domains and certificates, IP
allow-listing, credential-based (non-ACR) private registries, Windows apps,
multiple apps per plan, and frontend WAF/CDN — bring your own Front Door / APIM
in front of the hostname this module outputs.
