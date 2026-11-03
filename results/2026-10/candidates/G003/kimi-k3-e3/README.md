# Standard App Service module (SRE)

One standard way to run a containerized HTTP API on Azure App Service. You
tell it *what the service is* and *how much capacity/availability it needs*;
the module owns the App Service internals.

## What you get per service

- A dedicated resource group, Linux App Service plan, and Linux web app
  running your container.
- A **staging deployment slot**: deploy the new tag to the slot, warm it up,
  swap. Zero-downtime rollout, instant rollback by swapping back.
- **Health**: every instance is polled on `health_check_path` (default
  `/healthz`); failing instances leave the load balancer and are replaced
  after `health_check_eviction_time_in_min`. Auto-heal recycles any worker
  serving sustained 5xx or slow requests.
- **Capacity**: `plan_sku` + `plan_instances`, optional CPU-based
  **autoscale** (`autoscale_enabled`, min/max).
- **Availability**: `zone_redundant = true` spreads workers across AZs
  (Premium SKU, >= 2 instances).
- **Observability**: Application Insights (workspace-based) wired in via
  `APPLICATIONINSIGHTS_CONNECTION_STRING`; app + plan logs and metrics stream
  to Log Analytics (bring your own workspace or the module creates one).
- **Security defaults**: HTTPS only, TLS 1.2+ (incl. SCM), FTPS disabled,
  HTTP/2, no ARR affinity cookie, no persistent storage. When `acr_id` is
  set, the app pulls from ACR with its system-assigned managed identity
  (AcrPull) - no registry credentials.

## Usage

```hcl
module "payments_api" {
  source = "./app-service" # or wherever this module lives

  name                   = "payments-api-prod"
  resource_group_name    = "rg-payments-api-prod"
  location               = "westeurope"
  container_image        = "payments-api:2.11.0"
  container_registry_url = "https://myregistry.azurecr.io"
  container_port         = 8080

  acr_id          = "/subscriptions/.../resourceGroups/rg-acr/providers/Microsoft.ContainerRegistry/registries/myregistry"
  zone_redundant  = true
  plan_instances  = 3
  autoscale_enabled      = true
  autoscale_min_instances = 3
  autoscale_max_instances = 12

  health_check_path = "/ready"

  tags = { team = "sre", service = "payments-api" }
}
```

See `minimal.tfvars` for the smallest valid instantiation.

## Notes

- `name` must be globally unique (it becomes `https://<name>.azurewebsites.net`).
- Free/Shared SKUs are deliberately unsupported (no Always On, slots or
  health checks). Deployment slots need Standard+; zone redundancy needs
  Premium v2/v3 with >= 2 instances.
- When autoscale is enabled, keep `plan_instances` within
  [autoscale_min_instances, autoscale_max_instances].
