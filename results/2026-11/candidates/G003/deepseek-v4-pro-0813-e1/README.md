# SRE Standard App Service Module

A single, opinionated module for deploying containerized HTTP APIs onto Azure
App Service. It replaces the pile of hand-built apps with one standard that
encodes SRE policy for capacity, availability, health, rollouts, and
observability — so SREs think in those terms, not in App Service internals.

## What it provisions

| Concern        | What the module does                                                                  |
| -------------- | ------------------------------------------------------------------------------------- |
| Capacity       | Premium/Isolated v3 plan, worker count, and optional CPU/memory autoscale rules.      |
| Availability   | Always-on, HTTPS-only, minimum TLS 1.2, HTTP/2, multi-worker plan.                    |
| Health         | Health-check path with tuned eviction; unhealthy instances are pulled from rotation.  |
| Rollouts       | Staging deployment slot (swap-ready), image tag drift ignored so CI/CD owns releases. |
| Observability  | Diagnostic settings to Log Analytics + optional Application Insights connection.      |
| Networking     | Optional VNet integration and IP allowlisting (access restrictions).                  |
| Security       | System-assigned managed identity, registry credentials kept as sensitive app settings.|

## Minimal usage

```hcl
provider "azurerm" { features {} }

module "api" {
  source              = "./"
  name                = "orders-api"
  environment         = "prod"
  resource_group_name = "sre-orders-api-rg"
  location            = "eastus2"

  docker_image        = "acrsreprod.azurecr.io/orders-api:1.0.0"
  docker_registry_url = "https://acrsreprod.azurecr.io"
}
```

See `minimal.tfvars` for the smallest literal instantiation. Every variable
without a default is required; everything else has a team-policy default.

## Design decisions owned by this module

- **Capacity via plan + autoscale, not per-app tuning.** SREs set an SKU, a
  worker count, and (optionally) CPU/memory targets. The module renders the
  scale rules.
- **Availability posture is on by default.** Always-on, HTTPS enforced, TLS
  1.2 minimum, HTTP/2, least-requests load balancing, and a minimum of two
  workers. Zone redundancy is achieved by setting `worker_count >= 3` on a
  zone-redundant-capable SKU.
- **Health is first-class.** A single `health_check_path` (default `/healthz`)
  drives both Azure's instance-health eviction and the rollout signal.
- **Rollouts are slot-based.** A "staging" slot is created by default so the
  team can warm, verify, then swap. The container image *tag* is intentionally
  ignored by Terraform so the deploy pipeline stays the single writer of
  release identity.
- **Observability is wired, not hand-tuned.** Diagnostic categories and
  all-metrics are sent to Log Analytics; App Insights is a drop-in connection
  string.