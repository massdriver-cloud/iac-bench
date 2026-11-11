# Standard App Service Module

The SRE team's one supported way to run a containerized HTTP API on Azure App
Service. One module instantiation = one service, with a dedicated resource
group, capacity, availability, health checking, staged rollouts, and
observability already wired up the same way for every service.

## What gets created

| Resource | Purpose |
|---|---|
| Resource group | One per service: clean blast radius, trivial `destroy`. |
| `azurerm_service_plan` (Linux) | Capacity for this service only. Zone-balanced instances. |
| `azurerm_linux_web_app` | The production app running your container image. |
| `azurerm_linux_web_app_slot` (`staging`) | Rollout target; swap into production when verified. |
| `azurerm_monitor_autoscale_setting` | CPU-based scale-out/in on the plan. |
| `azurerm_log_analytics_workspace` | Home for logs & metrics (or bring your own). |
| `azurerm_application_insights` | Workspace-based App Insights; connection string is injected for you. |
| `azurerm_monitor_diagnostic_setting` × 2 | App logs (HTTP/app/console/audit) + app & plan metrics into the workspace. |
| `azurerm_management_lock` | `CanNotDelete` guardrail on the web app. |

## Design decisions

**Capacity.** Each service owns its App Service Plan (Premium v3 by default),
so noisy neighbours can't starve another team. `minimum_instance_count` is the
floor and autoscale rides on top of it: scale out at 70 % average CPU (5 m
window, 5 m cooldown), scale in at 20 % with a longer 10 m cooldown — fast
out, slow in, because availability beats saving one instance-hour.

**Availability.** Zone balancing spreads instances across availability zones
and the module enforces the 3-instance floor that mode requires. `always_on`
keeps containers warm; `https_only`, TLS 1.2 minimum, HTTP/2 on, and all
password-based publishing surfaces (FTP(S), WebDeploy basic auth) are closed
off.

**Health.** The platform probes every instance on `health_check_path`
(default `/healthz`) and evicts/replaces instances that fail
(`health_check_eviction_time_in_min`). Probe-failure thresholds are set via
`WEBSITE_HEALTHCHECK_MAX*` app settings. The health endpoint should return 2xx
only when the service can genuinely serve traffic.

**Rollouts.** The image tag is the deployment artifact: bump
`container_image`, apply to deploy it into the staging slot, smoke-test it,
then swap it into production. The slot inherits the exact same hardened
configuration and app settings as production.

**Observability.** Workspace-based Application Insights is created and its
connection string is injected as `APPLICATIONINSIGHTS_CONNECTION_STRING`.
Diagnostic settings ship HTTP logs, application logs, console logs, audit
logs, and all app/plan metrics to Log Analytics — enough to debug, audit, and
do capacity reviews without any extra wiring.

**Security & ops.** A system-assigned managed identity is attached so the app
can pull from private ACRs (grant it `AcrPull`) and read Key Vault without
stored credentials. A `CanNotDelete` lock keeps the app alive against stray
portal deletions while still allowing updates and swaps.

## Usage

```hcl
module "orders_api" {
  source = "<this module's location>"

  service_name    = "orders-api"
  environment     = "prod"
  container_image = "myregistry.azurecr.io/orders-api:1.4.2"

  container_registry_url = "https://myregistry.azurecr.io"
}
```

Minimal instantiation (see `minimal.tfvars` — only the three variables
without defaults):

```hcl
service_name    = "example-api"
environment     = "dev"
container_image = "nginx:stable"
```

```bash
tofu init
tofu plan  -var-file=minimal.tfvars
tofu apply -var-file=minimal.tfvars
```

## Notes and constraints

- Credentials come from the environment (`ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`,
  `ARM_TENANT_ID`, `ARM_SUBSCRIPTION_ID`, or an az CLI / managed-identity
  context).
- Deployment slots require a Standard-or-higher SKU; zone balancing requires
  a zone-capable region and a Premium SKU — both hold for the defaults
  (`P1v3`).
- To integrate outbound traffic with your network, pass
  `virtual_network_subnet_id`; the module turns on `vnet_route_all_enabled`
  automatically.
- To send logs to a shared workspace, pass `log_analytics_workspace_id` and
  the module skips creating its own.
- The lock blocks deletion of the app (not updates). Set
  `management_lock_enabled = false` first when intentionally tearing down.

## Key outputs

`app_url`, `staging_slot_url`, `default_hostname`, `service_plan_id`,
`log_analytics_workspace_id`, `managed_identity_principal_id`, and the
sensitive `application_insights_connection_string`.
