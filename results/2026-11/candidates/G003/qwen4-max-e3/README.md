# Standard App Service module (SRE)

One opinionated root module that deploys a containerized HTTP API onto Azure
App Service (Linux). SREs supply the image, a port, and a health endpoint;
the module owns the platform decisions.

## What you get per service

| Concern       | Decision                                                                                                     |
| ------------- | ------------------------------------------------------------------------------------------------------------ |
| Runtime       | Linux App Service, single custom container (`container_image`, tag required, `:latest` rejected)             |
| Capacity      | `P1v3` plan by default, 2 workers baseline, CPU autoscale 2→6 (out >70% / in <30%, 10-min windows)             |
| Availability  | Health probe on every instance (`health_check_path`), unhealthy instances evicted after 5 min; optional zone balancing (`zone_balancing_enabled`, enforces Premium v2/v3 + ≥3 instances) |
| Rollouts      | `staging` deployment slot with identical config; deploy → warm up → swap from your pipeline. `ENVIRONMENT` is slot-sticky; managed identities never swap |
| Health/security | HTTPS-only, TLS ≥1.2, HTTP/2, FTP and basic-auth publishing disabled, always-on, no ARR affinity (stateless APIs) |
| Identity      | System-assigned managed identity on app and slot (grant it `AcrPull`, Key Vault, DB access). ACR pulls can use the identity directly (`container_registry_use_managed_identity = true`) |
| Observability | Workspace-based App Insights (connection string injected), all platform logs + metrics → per-service Log Analytics workspace with retention and a daily ingestion cap |
| Networking    | Optional VNet integration for outbound traffic (`vnet_integration_subnet_id`, routes all egress via the VNet) |

## Usage

```hcl
# tofu plan -var-file=service.tfvars
name             = "payments-api"
container_image  = "contoso.azurecr.io/payments-api:1.4.2"
container_registry_url                  = "https://contoso.azurecr.io"
container_registry_use_managed_identity = true
container_port   = 8080
health_check_path = "/healthz"
app_settings = {
  LOG_LEVEL = "info"
}
```

`minimal.tfvars` is the smallest valid instantiation (public nginx image).

Credentials/subscription come from the environment (`ARM_*` variables).

## Rollout flow

1. Pipeline pushes a new image tag and deploys it to the `staging` slot
   (slot hostname is in the outputs).
2. Warm up / smoke-test staging (the same health probe runs there).
3. Swap: `az webapp deployment slot swap -g <rg> -n <name> --slot staging`.
   Slot-sticky `ENVIRONMENT` stays with each slot; identities stay put, so
   grant both `principal_id` and `staging_principal_id` access to dependencies.

## Guardrails

- Autoscale requires Standard+ SKU; the plan owns worker count when autoscale
  is on (no `worker_count` tug-of-war on every apply).
- Zone balancing requires Premium v2/v3 and ≥3 minimum instances.
- Platform-managed app settings (port, App Insights, storage) cannot be
  overridden via `app_settings`.
