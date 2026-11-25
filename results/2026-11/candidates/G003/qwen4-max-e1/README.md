# Standard App Service module (SRE)

One opinionated root module that takes a containerized HTTP API from image to
a production-ready Azure App Service. SREs supply the service name, region and
image; the module owns the App Service internals.

## What you get

| Concern       | What the module does                                                                                                     |
| ------------- | ------------------------------------------------------------------------------------------------------------------------ |
| Runtime       | Linux Web App for Containers, system-assigned managed identity, `WEBSITES_PORT` wired from `container_port`               |
| Capacity      | Dedicated Linux plan (default `P1v3`, 2 workers) + CPU autoscale (out >70%, in <30%, min 1 / max 5, fast-out slow-in)     |
| Availability  | Always-on, health-check path with instance eviction (5 min), optional zone redundancy (`zone_redundant`, forces ≥3 workers) |
| Health        | `health_check_path` (default `/healthz`) probed per instance; unhealthy instances leave the load balancer                  |
| Rollouts      | `staging` slot on the same plan (default on), optional auto-swap; sticky settings supported; swap explicitly via CLI/portal |
| Observability | Workspace-based App Insights (connection string injected), HTTP/console/app/audit/platform logs + AllMetrics to Log Analytics for app **and** slot |
| Security      | HTTPS-only, TLS ≥1.2, HTTP/2, FTPS disabled, publishing basic-auth disabled, 64-bit workers, ACR pulls via managed identity (AcrPull) |
| Networking    | Optional VNet integration (`subnet_id`) with route-all outbound                                                            |

## Minimal usage

```hcl
name            = "orders-api"
location        = "westeurope"
container_image = "nginx:alpine"
container_port  = 80
health_check_path = "/"
```

See `minimal.tfvars` for a working minimal instantiation.

## Typical production service

```hcl
name                   = "orders-api"
location               = "westeurope"
container_image        = "myacr.azurecr.io/orders-api:1.4.2"
container_registry_url = "https://myacr.azurecr.io"
acr_id                 = "/subscriptions/.../resourceGroups/platform/providers/Microsoft.ContainerRegistry/registries/myacr"
container_port         = 8080
health_check_path      = "/healthz"

sku_name       = "P2v3"
zone_redundant = true
autoscale_max  = 10

subnet_id                  = "/subscriptions/.../subnet-apps"
log_analytics_workspace_id = "/subscriptions/.../workspaces/sre-central"

app_settings = {
  ASPNETCORE_ENVIRONMENT = "Production"
}
slot_app_settings = {
  ASPNETCORE_ENVIRONMENT = "Staging"
}
sticky_app_setting_names = ["ASPNETCORE_ENVIRONMENT"]

tags = { team = "sre", service = "orders-api" }
```

## Design decisions

- **One plan per service**: blast-radius isolation and per-service autoscale;
  slots share the plan so staging costs nothing extra.
- **Autoscale owns the worker count** after creation (`ignore_changes` on the
  plan's `worker_count`), so applies never fight the scale engine.
- **Manual swap by default**: deploy image to staging, verify, then swap.
  `auto_swap_enabled = true` opts into Azure auto-swap.
- **Managed identity everywhere**: ACR pull via `AcrPull` role assignment for
  app and slot identities; the principal IDs are exported so SREs can grant
  downstream data-plane access. Basic-auth registry credentials remain
  available for non-ACR registries.
- **Observability is on by default**: a per-service workspace is created
  unless the team passes its central `log_analytics_workspace_id`.
- **No hand-tuned internals**: platform settings (TLS, HTTP/2, always-on,
  storage mount off, publish auth off) are fixed opinions, not variables.

## Files

- `versions.tf` – provider constraints (azurerm ~> 4.0)
- `variables.tf` – the SRE-facing API surface
- `main.tf` – resource group, plan, app, staging slot, ACR role assignments
- `monitoring.tf` – workspace, App Insights, diagnostic settings, autoscale
- `outputs.tf` – hostnames, IDs, identity principal IDs, insights connection
- `minimal.tfvars` – smallest valid instantiation
