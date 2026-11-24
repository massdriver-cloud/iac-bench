# Standard App Service module (SRE)

One opinionated module for running containerized HTTP APIs on Azure App
Service. SREs declare what the service needs (image, capacity, health
endpoint); the module owns every App Service internal.

## What every service gets

- **Capacity**: dedicated Linux App Service plan per service with
  metric-based autoscaling (CPU, memory, HTTP queue length) between
  `min_capacity` and `max_capacity`.
- **Availability**: optional zone redundancy (Premium v2/v3 + 3 instances),
  always-on, HTTPS-only, TLS 1.2+, FTP disabled, stateless containers.
- **Health**: instance health checks on `health_check_path` (failing instances
  are evicted), auto-heal recycles workers serving 5xx storms, standard
  alerts on 5xx volume and health-check failures.
- **Rollouts**: a `staging` deployment slot. Deploy the new image to staging,
  wait for the health check, then swap from your CD pipeline
  (`az webapp deployment slot swap`).
- **Observability**: Log Analytics workspace (or bring your own), Application
  Insights wired into the app's settings, diagnostic settings streaming app,
  slot and plan logs/metrics to the workspace.

## Usage

```hcl
module "payments_api" {
  source = "./" # path to this module

  name                = "payments-api-prod"
  resource_group_name = "rg-payments-api-prod"
  location            = "westeurope"

  container_image        = "payments-api:1.4.2"
  container_registry_url = "https://contoso.azurecr.io"
  acr_id                 = data.azurerm_container_registry.shared.id

  plan_sku         = "P1v3"
  zone_redundant   = true
  min_capacity     = 3
  default_capacity = 3
  max_capacity     = 12

  health_check_path = "/healthz"

  alert_action_group_ids = [data.azurerm_monitor_action_group.sre_oncall.id]

  app_settings = {
    FEATURE_FLAG_X = "on"
  }

  tags = {
    team    = "payments"
    service = "payments-api"
  }
}
```

See `minimal.tfvars` for the smallest valid instantiation.

## Design decisions (not negotiable per service)

- One plan per service — no shared capacity between services.
- Containers are immutable: no app service storage mount, no FTP.
- Slot swaps happen in CD pipelines, not in this module; the module only
  guarantees a healthy staging slot exists.
- Alerts always exist; notifications are wired via `alert_action_group_ids`.
