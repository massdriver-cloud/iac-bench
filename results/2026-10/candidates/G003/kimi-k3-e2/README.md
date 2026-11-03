# app-service-standard

The SRE team's standard module for running a containerized HTTP API on Azure
App Service (Linux). One opinionated module replaces hand-built apps: call it
per service, get the same capacity, availability, health, rollout and
observability posture everywhere.

## What you get per service

| Concern | Standard behaviour |
| --- | --- |
| Capacity | Dedicated Linux plan, `sku_name`/`instance_count`. CPU autoscale (out >70%, in <30%) on tiers that support it. |
| Availability | Optional zone redundancy (Premium v2/v3, >=3 instances, prevalidated). HTTPS-only, TLS 1.2, HTTP/2, no ARR affinity. |
| Health | Platform health check (`/healthz` default) replaces failing instances; auto-heal recycles workers on a sustained 500-599 burst. |
| Rollouts | Staging slot mirrors production config. CI deploys to the slot, smoke-tests, swaps. Terraform ignores image drift so pipelines own releases. |
| Observability | Workspace-based App Insights (connection string injected), all App Service log categories + metrics streamed to Log Analytics, metric alerts for 5xx spikes and slow responses. |
| Identity | System-assigned managed identity on app and slot; optional AcrPull grants for private ACR, no registry passwords in state. |

## Usage

```hcl
module "orders_api" {
  source = "./app-service-standard"

  name                = "orders-api"
  resource_group_name = "rg-orders-api"
  location            = "eastus"

  container_image       = "myregistry.azurecr.io/orders-api:1.4.2"
  container_registry_url = "https://myregistry.azurecr.io"
  container_registry_id  = azurerm_container_registry.shared.id # AcrPull via managed identity
  container_port         = 8080

  alert_email_addresses = ["sre-oncall@example.com"]
}
```

## Design decisions you should know about

- **Feature downgrade by tier.** Slots and autoscale are created only when the
  SKU supports them (Standard+), so the same module can run a cheap Basic
  sandbox without failing at apply time. `always_on` is dropped on
  Free/Shared for the same reason.
- **The pipeline owns the image.** `docker_image_name` is in `ignore_changes`;
  day-2 releases bump the container image (and swap slots) from CI. Terraform
  owns infrastructure, CI owns releases.
- **Zone redundancy is opt-in and prevalidated.** It needs Premium v2/v3 and
  at least three workers; a plan-time precondition fails fast with a clear
  message rather than an Azure API error mid-apply.
- **Global naming is handled.** Web app names get a random 6-char suffix so
  `azurewebsites.net` never collides; set `web_app_name` to pin an exact name.
- **Publishing hardening.** FTP and WebDeploy basic auth are disabled;
  container services deploy by setting a new image, not via publish profiles.

See `minimal.tfvars` for the smallest valid instantiation.
