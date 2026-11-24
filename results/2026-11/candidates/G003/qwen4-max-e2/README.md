# Standard App Service module (containerized HTTP APIs)

One opinionated root module the SRE team applies per service. It provisions:

- `rg-<service>` resource group
- `plan-<service>` Linux App Service Plan (capacity: `sku_name`, `worker_count`, optional zone redundancy)
- `app-<service>` Linux Web App for Containers (production)
- `staging` deployment slot (optional, Standard+ tiers) for warm-up / swap rollouts
- `log-<service>` Log Analytics workspace + full platform diagnostic settings (app and slot)
- `appi-<service>` workspace-based Application Insights (optional)
- AcrPull role assignments for the app/slot identities when pulling from a private ACR

## Defaults / opinions

| Concern       | Decision                                                                 |
|---------------|--------------------------------------------------------------------------|
| Transport     | HTTPS-only, TLS >= 1.2, HTTP/2, FTPS disabled                            |
| Availability  | P1v3 x3 workers, always-on; optional `zone_redundant` (P*v2/v3, >=3 workers, enforced by precondition) |
| Health        | `health_check_path` probed per instance; unhealthy instances evicted after 5 min |
| Rollouts      | Staging slot mirrors prod config; `DOCKER_ENABLE_CI=true` for registry-webhook rollouts; Terraform ignores image-tag drift so CD is authoritative for the running tag; optional auto-swap (off by default, manual gated swaps) |
| Identity      | System-assigned managed identity; private ACR pulls via AcrPull - no registry passwords |
| Observability | App Insights connection string injected as `APPLICATIONINSIGHTS_CONNECTION_STRING`; HTTP/console/app/audit/platform logs + AllMetrics to Log Analytics |
| Config        | `extra_app_settings` for env vars; use Key Vault references for secrets   |

## Minimal instantiation

Only `service_name` and `container_image` are required. `minimal.tfvars` shows
the smallest footprint (B1 x1, no slot, public demo image):

```
tofu plan  -var-file=minimal.tfvars
tofu apply -var-file=minimal.tfvars
```

## Typical production instantiation

```hcl
service_name      = "orders-api"
container_image   = "contoso.azurecr.io/orders-api:1.4.2"
acr_resource_id   = "/subscriptions/.../resourceGroups/rg-platform/providers/Microsoft.ContainerRegistry/registries/contoso"
container_port    = 8080
health_check_path = "/healthz"
zone_redundant    = true          # P1v3 x3 spread across AZs
extra_app_settings = {
  ASPNETCORE_ENVIRONMENT = "Production"
}
```

Deploy new versions to the `staging` slot (CI pushes the image / updates the
slot), validate via the staging hostname, then swap. Set
`auto_swap_enabled = true` only for services that want fully automatic swaps.
