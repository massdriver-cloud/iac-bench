# Standard App Service Module

Consolidated Azure App Service module for the SRE team to deploy and run
containerized HTTP APIs.

## What it does

- **Linux containers** — the module deploys `azurerm_linux_web_app` backed by
  a container image (Docker Hub or Azure Container Registry).
- **Capacity/availability** — an App Service Plan with a chosen SKU, fixed
  worker count (or CPU autoscaling), optional zone redundancy.
- **Health** — wires the platform health probe to a liveness path
  (default `/healthz`) and evicts unhealthy instances after 10 minutes.
- **Rollouts** — an optional staging slot with percent-based traffic routing
  for canary releases.
- **Observability** — provisions Application Insights and injects the
  connection string and agent into both slots.
- **Identity/security** — system-assigned managed identity (for ACR pull and
  downstream auth), HTTPS enforced, basic-auth publishing disabled.

## Minimal usage

```hcl
module "api" {
  source              = "."
  name                = "orders-api"
  resource_group_name = "rg-sre-platform"
  location            = "eastus"
  docker_image        = "myorg/orders-api:1.0.0"
}
```

See `variables.tf` for every knob. Slots, autoscaling, zone redundancy,
private registry credentials, and App Insights are all opt-in/out with
sensible defaults.

## Rollouts

Set `slot_enabled = true` to create a `staging` slot. Route traffic to it
with `staging_traffic` (0–100). The percentage itself is adjusted during a
release via `az webapp traffic-routing set`; Terraform establishes the slot
and the intended split is surfaced as the `traffic_routing` output.