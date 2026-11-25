# Standard App Service module (SRE)

One standard way to run a containerized HTTP API on Azure App Service.
Product teams ship an image; SREs set capacity and guardrails; the module
owns the App Service internals.

## What you get per service

| Concern | Decision the module makes |
| --- | --- |
| Capacity | Dedicated Linux plan (default `P1v3`), floor/ceiling via `min_capacity`/`max_capacity`, CPU autoscale (out >75%, in <40%, 10-min windows) |
| Availability | Zone-balanced plan (Premium/Isolated SKUs), platform health check on `health_check_path` with eviction, auto-heal recycle on sustained 5xx |
| Rollouts | Optional `staging` slot mirroring production — deploy, warm, swap |
| Observability | Per-service Log Analytics workspace + Application Insights (connection string injected as an app setting), diagnostic settings for HTTP/console/app/platform logs and all metrics |
| Identity | System-assigned managed identity; if `container_registry_id` is set, the identity gets `AcrPull` and registry auth is credential-less |
| Security | HTTPS-only, TLS 1.2, FTPS off, basic-auth publishing (FTP/WebDeploy) off — deploy with RBAC/OIDC, no sticky sessions, no home-storage mount |

## Usage

```hcl
module "payments_api" {
  source = "./" # or your git source

  name                = "payments-api"
  resource_group_name = "rg-payments-prod"
  location            = "westeurope"

  image                 = "payments-api:1.4.2"
  registry_url          = "https://contoso.azurecr.io"
  container_registry_id = azurerm_container_registry.main.id
  container_port        = 8080

  min_capacity = 2
  max_capacity = 12

  app_settings = {
    OTEL_SERVICE_NAME = "payments-api"
  }

  tags = {
    team = "payments"
    env  = "prod"
  }
}
```

`minimal.tfvars` is the smallest valid instantiation (four required inputs
plus a port matching the sample image).

## Notes for operators

- Slot **swapping** is an operational action (pipeline step), not something
  the module performs — the module provides the slot, your release process
  swaps it.
- The plan's live instance count is owned by autoscale after creation;
  `worker_count` drift is intentionally ignored.
- `name` must be globally unique in Azure (it becomes
  `https://<name>.azurewebsites.net`).
- Zone redundancy requires a Premium/Isolated SKU and `min_capacity >= 2`;
  both are enforced by plan-time preconditions.
- Publish-profile (basic auth) deployment is disabled on purpose; grant your
  CI identity `Website Contributor` and deploy with `az webapp deploy`,
  GitHub Actions OIDC, etc.
