# Standard App Service module

The SRE team's one standard way to run the product teams' containerized HTTP
APIs on Azure App Service. Instantiate this module once per service; it
creates everything the service needs to run, so nobody hand-tunes App Service
internals per app.

## What it creates

| Resource | Name | Purpose |
| --- | --- | --- |
| Resource group | `rg-<name>` | per-service access and billing boundary |
| App Service plan (Linux, Premium v3) | `plan-<name>` | capacity |
| Autoscale setting | `autoscale-<name>` | capacity management |
| Linux web app (custom container) | `app-<name>` | the service |
| Deployment slots | `<slot>` on the app | rollouts |
| Log Analytics workspace | `log-<name>` | central logs and metrics |
| Application Insights (workspace-based) | `appi-<name>` | service telemetry |
| Diagnostic settings | `diag-<name>-*` | pipeline: app, plan and slots -> workspace |
| AcrPull role assignments | - | image pulls, when `container_registry_id` is set |

## The SRE contract

### Capacity

- `instance_size` picks from the standard Premium v3 ladder:
  `small` = P1v3 (2 vCPU / 3.5 GiB), `medium` = P2v3 (4 vCPU / 7 GiB),
  `large` = P3v3 (8 vCPU / 14 GiB). `instance_sku` is the escape hatch for
  unusual shapes (e.g. `P1mv3` for memory-heavy services).
- Autoscale keeps instances between `min_instances` (default 3) and
  `max_instances` (default 10): scale out when average CPU exceeds
  `cpu_scale_out_threshold` (default 70%) for 10 minutes, scale in below
  `cpu_scale_in_threshold` (default 30%) for 15 minutes. Scale-in is
  deliberately slower than scale-out so short spikes do not thrash the plan.
- To pin capacity, set `min_instances = max_instances`.
- Terraform only seeds the initial instance count; the autoscale engine owns
  it afterwards (`worker_count` changes are ignored after creation).

### Availability

- Premium v3 is the floor of the standard: those plans spread across
  availability zones in zone-capable regions, and the default of 3 instances
  keeps one instance per zone.
- Always-on workers, HTTPS-only, HTTP/2, TLS 1.2 floor on both the app and the
  SCM endpoints, FTPS and FTP/WebDeploy basic auth disabled.
- Self-healing: unhealthy instances are taken out of rotation and replaced
  automatically (see Health).

### Health

- `health_check_path` is required - the module assumes every service exposes
  a liveness endpoint. App Service probes it continuously; instances that
  fail for `health_check_eviction_minutes` (default 10) are evicted from the
  load balancer and replaced. The same probe gates slot promotion.

### Rollouts

- Warm slots (default: `staging`) mirror production: same configuration, same
  identity rights, same logging, same health checks.
- Standard release flow: CI pushes the image, points the slot at the new tag,
  waits for the slot health check to go green, then promotes. With
  `auto_swap_to_production = true` (the default) promotion is automatic once
  the slot is warm and healthy; set it to false to promote by hand.
- After a release, bump `container_image` in the tfvars so the repository
  reflects what production runs.

### Observability

- A workspace-based Application Insights resource is created per service and
  its connection string is injected as `APPLICATIONINSIGHTS_CONNECTION_STRING`
  (your `app_settings` merge on top of the module defaults, so you can
  override anything).
- All log categories - HTTP logs, container stdout (`AppServiceConsoleLogs`),
  audit, IPsec and platform logs - plus metrics for the app, every slot and
  the plan flow into the Log Analytics workspace as resource-specific tables,
  retained for `log_retention_in_days` (default 30).
- Scale-out/scale-in decisions are visible as autoscale events on the plan.

### Identity and registry

- Every app and slot gets a system-assigned managed identity; no secrets live
  in this module. When `container_registry_id` is set, each identity is
  granted AcrPull and the apps pull with managed identity - no registry
  credentials are stored anywhere.
- `managed_identity_principal_id` is exported for granting extra access (Key
  Vault, storage, databases) outside this module.
- Prefer Key Vault references in `app_settings` for application secrets.

### Networking

- Optional VNet integration: set `vnet_integration_subnet_id` (subnet must be
  delegated to `Microsoft.Web`) and all container egress is routed through
  your VNet (route-all enabled).

## Required variables

| Variable | Meaning |
| --- | --- |
| `name` | service name; the naming stem for every resource |
| `location` | Azure region - use a zone-capable one for full availability |
| `container_image` | image the service runs, `repo:tag` |
| `health_check_path` | liveness endpoint - health is not optional |

Everything else has a default that matches the standard; see `variables.tf`
for the annotated list and `outputs.tf` for what you get back.

## Rollout runbook

```sh
# 1. CI builds and pushes orders/api:1.5.0 to the registry.

# 2. CI stages it on the slot (pull uses the app's managed identity):
az webapp config container set \
  --resource-group rg-orders-api --name app-orders-api --slot staging \
  --image myregistry.azurecr.io/orders/api:1.5.0

# 3. Promote once the slot is warm and its health check passes
#    (automatic when auto_swap_to_production is true):
az webapp deployment slot swap \
  --resource-group rg-orders-api --name app-orders-api \
  --slot staging --target-slot production

# 4. Open a PR bumping container_image to "orders/api:1.5.0".
```

## Minimal instantiation

`minimal.tfvars` is the smallest valid instantiation of the module - the
standard tier running a public sample image, no ACR, no VNet - and it plans
cleanly:

```sh
tofu init
tofu plan -var-file=minimal.tfvars
```

A realistic service only adds a few lines:

```hcl
name               = "orders-api-prod"
location           = "westeurope"
container_image    = "orders/api:1.5.0"
container_registry_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-shared/providers/Microsoft.ContainerRegistry/registries/myregistry"
health_check_path  = "/health"
container_port     = 8080
app_settings       = { "ORDERS_DB" = "@Microsoft.KeyVault(SecretUri=https://...)" }
```
