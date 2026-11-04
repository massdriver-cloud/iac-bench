# Standard App Service module (SRE)

One opinionated root module that runs a containerized HTTP service on Azure App
Service (Linux) with the capacity, availability, health, rollout and
observability plumbing already wired up.

## What you get per service

| Concern        | What the module does                                                                                   |
|----------------|--------------------------------------------------------------------------------------------------------|
| Capacity       | Linux plan (default `P1v3`), `min_instances` baseline, CPU-based autoscale up to `max_instances`.       |
| Availability   | Optional zone redundancy (`zone_redundant`, needs Premium v3 + >= 3 instances), `always_on`, HTTPS-only, TLS 1.2, HTTP/2, no client affinity. |
| Health         | Health-check probe on `health_check_path` with instance eviction, plus alerts on health-check status, 5xx count and latency. |
| Rollouts       | A `staging` deployment slot sharing the same config. Deploy there, verify, swap. Tofu sets the *initial* image and then ignores image changes so pipeline-driven rollouts never fight state. |
| Observability  | Log Analytics workspace, workspace-based Application Insights (auto-attached), diagnostic settings for app + slot, file-system HTTP/app logs. |
| Identity       | System-assigned + user-assigned identity. Pass `container_registry_id` to get `AcrPull` and credential-less image pulls. |
| Network        | Optional VNet integration (`virtual_network_subnet_id`), optional IP / service-tag allow-lists.         |

## Minimal usage

```hcl
name            = "orders-api"
location        = "eastus"
container_image = "myacr.azurecr.io/orders-api:1.4.2"
```

```sh
tofu plan -var-file=minimal.tfvars
```

## Rollout flow

```sh
az webapp config container set -g rg-orders-api -n orders-api --slot staging \
  --container-image-name myacr.azurecr.io/orders-api:1.5.0
# verify https://orders-api-staging.azurewebsites.net
az webapp deployment slot swap -g rg-orders-api -n orders-api --slot staging
```

## Notes

- The module creates its own resource group `rg-<name>` so a service can be torn down cleanly.
- Module-managed app settings (`WEBSITES_PORT`, App Insights, …) override keys passed via `app_settings`.
- `container_image` must carry an explicit immutable tag; `:latest` is rejected.
- Set `max_instances == min_instances` to run a fixed instance count with no autoscale.
