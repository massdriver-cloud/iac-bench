# app-service-web (standard SRE module)

One standard OpenTofu module for running containerized HTTP APIs on Azure App
Service (Linux). SREs declare *operational* intent — capacity, availability,
health, rollout behaviour, observability — and the module owns the App Service
internals.

## What it creates

| Concern | Resources / behaviour |
|---|---|
| **Capacity** | Dedicated `azurerm_service_plan` per service (no noisy neighbours). `sku_name` + `capacity`, or CPU/memory driven `azurerm_monitor_autoscale_setting` with scale-out *and* scale-in rules. |
| **Availability** | Optional zone redundancy (`zone_redundant`), with the instance count automatically raised to the required minimum of 3. |
| **Health** | Load-balancer health check (`health_check_path`) that evicts sick instances, plus auto-heal triggers (5xx rate, slow requests, optional request count) that recycle bad workers. |
| **Rollouts** | Blue/green: a `staging` deployment slot with full config parity. Deploy the candidate to the slot, then set `deployment_slot.promote_to_production = true` and apply to swap; flip back to roll back. `sticky_app_setting_names` keeps environment-specific settings pinned to their slot. |
| **Observability** | Workspace-based Application Insights wired into the app settings, diagnostic settings (HTTP/console/app/audit/platform logs + metrics) for app, slot and plan into Log Analytics (module-created or BYO), external availability web test, and metric alerts (5xx, latency, health-check status, external availability, plan CPU/memory saturation). Alerts fan out to a module-created e-mail action group and/or existing action groups. |

## Usage

```hcl
module "orders_api" {
  source = "./app-service-web"

  name                = "orders-api"
  resource_group_name = "rg-orders-api-prod"
  location            = "westeurope"

  container = {
    image                = "shop/orders-api:1.4.2"
    registry_url         = "https://acrsre.azurecr.io"
    use_managed_identity = true
    registry_id          = "/subscriptions/.../resourceGroups/rg-shared/providers/Microsoft.ContainerRegistry/registries/acrsre"
  }

  sku_name       = "P1v3"
  zone_redundant = true

  autoscale = {
    enabled = true
    minimum = 3
    maximum = 12
  }

  health_check_path = "/healthz"

  alerts = {
    email_receivers = ["sre-oncall@example.com"]
  }

  app_settings = {
    OTEL_SERVICE_NAME = "orders-api"
  }

  tags = { environment = "prod", team = "checkout" }
}
```

A minimal, plans-clean instantiation lives in `minimal.tfvars`:

```sh
tofu plan -var-file=minimal.tfvars
```

## Design decisions (owned by this module)

- **Dedicated plan per service.** Capacity, autoscale history and plan-level
  metrics stay per-service; a runaway app never starves another team's API.
- **Resource group per service**, created by the module. Clean blast radius,
  RBAC boundary and cost attribution.
- **Container-first.** Linux plan + container only. Registry auth prefers
  managed identity (AcrPull role is granted automatically when
  `container.registry_id` is set); basic-auth registry credentials are
  supported for registries that need them.
- **HTTPS only, TLS 1.2+, HTTP/2, no ARR affinity cookie, no ftp/webdeploy
  basic auth.** Stateless APIs behind a load balancer do not want affinity
  cookies, and CI should deploy with RBAC.
- **Health is not optional.** `/health` is the default probe; App Service pulls
  failing instances out of rotation and replaces them, auto-heal recycles
  workers that start 500ing or stalling.
- **Slot-based rollouts instead of in-place redeploys.** Production traffic is
  only ever served by a warmed, health-checked slot. Swaps are an explicit
  Terraform action (`promote_to_production`), so rollouts and rollbacks are
  code-reviewed like everything else.
- **Alerts are shipped with thresholds, not wiring.** Every threshold is a
  plain variable default — tune per service without restructuring anything.
- **Azure Monitor only** (App Insights + Log Analytics + metric alerts). No
  third-party agents; teams layer dashboards/workbooks on top of the emitted
  data if they want them.

## Notes

- `name` must be unique enough that `app-<name>.azurewebsites.net` is globally
  unique in Azure.
- Zone redundancy needs a Premium v2/v3 (or Isolated v2) SKU and ≥3 workers —
  the module enforces the worker count automatically.
- When `autoscale.enabled = true`, keep `capacity` aligned with
  `autoscale.default_capacity`; the autoscaler owns instance count afterwards.
- Pulling from ACR over a VNet additionally requires
  `container.use_managed_identity = true` + `vnet_integration_subnet_id`; the
  module then sets `WEBSITE_PULL_IMAGE_OVER_VNET` automatically.
