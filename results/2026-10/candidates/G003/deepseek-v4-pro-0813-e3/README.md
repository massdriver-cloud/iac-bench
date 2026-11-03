# Standard App Service module (SRE)

A single, opinionated module for deploying containerized HTTP APIs onto Azure
App Service (Linux). SREs express intent in terms of capacity, availability,
health, rollouts and observability; the module decides the App Service
internals.

## Minimal usage

```hcl
module "api" {
  source = "./"

  name  = "payment-api"
  image = "acrsreteam.azurecr.io/payment-api:1.0.0"
  registry = {
    server_url           = "acrsreteam.azurecr.io"
    use_managed_identity = true
  }
}
```

## What the module decides for you

Everything below is applied by default; per-app overrides are rare by design.

| Concern        | Decision                                                                                                                                     |
| -------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| Platform       | Linux App Service, container-based, HTTPS-only, HTTP/2, TLS 1.2 min, websockets on.                                                          |
| Capacity       | `sku` (size/tier/capacity) + optional zone redundancy on Premium v2/v3.                                                                      |
| Availability   | Zone balancing when the tier supports it; `always_on` recommended (default true).                                                            |
| Health         | Health-check path defaults to `/healthz`; eviction after 10 failed pings on 100% of workers. Set `health_check_path = ""` to disable.        |
| Rollouts       | Staging deployment slot for blue/green swaps; slot warmup pings `/healthz` (or `/`) before a swap completes.                                 |
| Identity       | System-assigned managed identity on app and slot; used for ACR pull when `registry.use_managed_identity` is true.                            |
| Observability  | Application Insights wired via connection string (opt-out); optional Log Analytics diagnostics for platform/app logs.                        |
| Security       | FTPS disabled in production, FtpsOnly in staging, AllAllowed in dev.                                                                         |
| Naming         | `app-<name>-<env>`, `plan-<name>-<env>`, `rg-<name>-<env>-<suffix>` (random suffix prevents collision on re-create).                          |

## Environment-driven defaults

`environment` selects a baseline (`dev` / `stg` / `prd`) for FTPS policy.
SKU, zone redundancy, health path and slot behaviour are always explicit via
their own variables.

## Known constraints

- Zone redundancy requires a Premium v2/v3 SKU; on other tiers it is ignored.
- Managed-identity ACR pull requires the registry role assignment
  (`AcrPull`) for the app's system identity to exist out-of-band; the module
  passes the App Service-managed `__token__` convention but cannot create the
  role binding without the ACR's resource group. Prefer this over static
  credentials; pass `registry.username`/`registry.password` if you must use
  static auth.
- `DOCKER_REGISTRY_SERVER_PASSWORD` is kept out of the module's diff tracking
  so rotating credentials does not churn the app.
- Auto-swap (deploy-to-staging then automatic swap into production) is not
  available as a first-class attribute on `azurerm_linux_web_app_slot`; the
  module standardises on the staging slot plus warmup ping path so the swap
  step itself stays an explicit, reviewable operation.