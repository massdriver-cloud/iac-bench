# app-service — standard containerized HTTP API on Azure App Service

One service per instantiation. The module creates:

| Concern         | What you get                                                                                   |
|-----------------|------------------------------------------------------------------------------------------------|
| Capacity        | Linux App Service Plan (`sku_name`, `instance_count`), optional CPU autoscale (`autoscale`)     |
| Availability    | Optional zone redundancy, always-on, no client affinity, health-check-based instance eviction  |
| Health          | Mandatory HTTP health probe (`health_check_path`, default `/healthz`), eviction window          |
| Rollouts        | `staging` deployment slot mirroring production; deploy → verify → swap                          |
| Observability   | Log Analytics (created or BYO), workspace-based Application Insights, diagnostic settings, baseline alerts (5xx, latency, health-check) |
| Security        | HTTPS-only, TLS 1.2, HTTP/2, FTPS/basic-auth publishing off, user-assigned identity, identity-based ACR pulls, optional VNet integration and IP/service-tag allow-list |

## Minimal use

```hcl
name            = "payments-api"
location        = "westeurope"
container_image = "myacr.azurecr.io/payments-api:1.4.2"
```

Typical production addition:

```hcl
container_registry_url = "https://myacr.azurecr.io"
container_registry_id  = "/subscriptions/.../registries/myacr"
sku_name               = "P1v3"
instance_count         = 3
zone_redundant         = true
autoscale              = { max_instances = 10 }
alert_action_group_ids = ["/subscriptions/.../actionGroups/sre-pager"]
app_settings = {
  DATABASE_URL = "@Microsoft.KeyVault(SecretUri=https://kv.vault.azure.net/secrets/db-url/)"
}
```

## Rollout flow

1. Set `staging_container_image` to the candidate image and apply. Only the staging slot changes.
2. Verify at `staging_url` (health probe must pass on `health_check_path`).
3. Swap: `az webapp deployment slot swap -g <rg> -n <name> --slot staging`.
4. Set `container_image` to the candidate and clear `staging_container_image`; apply. This reconciles state with what is now live (no restart, the app already runs that image).

## Contract for the workload

- Listen on `container_port` (default 8080) over plain HTTP; TLS terminates at the platform.
- Serve a 2xx on `health_check_path` only when the instance is ready to take traffic.
- Read `APPLICATIONINSIGHTS_CONNECTION_STRING` to emit telemetry (OpenTelemetry / App Insights SDKs).
- Use `identity_client_id` (`AZURE_CLIENT_ID`) when authenticating to other Azure services with the managed identity.
