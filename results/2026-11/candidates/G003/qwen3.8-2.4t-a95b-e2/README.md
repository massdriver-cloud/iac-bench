# Standard App Service module

One standard, batteries-included Azure App Service footprint for the
containerized HTTP APIs our product teams build and the SRE team operates.
Instead of every service hand-rolling its own App Service setup, teams supply
two things — a service name and a container image — and get a production-grade
deployment that already handles capacity, availability, health, rollouts, and
observability the same way everywhere.

## What you get

| Concern       | What the module stands up                                                                                       |
|---------------|-----------------------------------------------------------------------------------------------------------------|
| Platform      | Dedicated resource group, Linux App Service Plan, Linux Web App running your container                          |
| Capacity      | CPU autoscaling (2–10 workers by default), optional availability-zone balancing                                  |
| Availability  | `always_on`, HTTPS-only, TLS 1.2+, multi-instance floor, multi-region availability ping test                     |
| Health        | Platform health checks (`/healthz` by default): unhealthy instances are drained, restarted, then replaced        |
| Rollouts      | Staging deployment slot; deploy there, verify, swap into production                                              |
| Observability | Log Analytics workspace, Application Insights, App Service diagnostic settings, availability test                |

## Design decisions (and why)

### Capacity
- **P1v3 App Service Plan** is the standard: Premium v3 supports autoscaling
  and zone balancing and runs containers well. Teams can opt down to B/S SKUs
  via `sku_name` for cheaper non-critical services.
- **Autoscaling is on by default** (CPU-based, scale out >75% / scale in <30%,
  asymmetric cooldowns: 5 min out, 10 min in) to avoid flapping. The floor is
  **2 instances** so a single bad deploy or node failure never fully takes the
  service down; the ceiling caps cost/blast radius. `worker_count` is the
  baseline; the autoscale profile runs day-to-day capacity.
- **Zone balancing** is available (`zone_balancing_enabled`) but off by
  default because it needs ≥3 instances and a zone-capable region; turn it on
  for production in zoned regions.

### Availability & traffic
- `https_only`, `minimum_tls_version = 1.2`, `ftps_state = FtpsOnly`, and no
  session-affinity cookie (stateless HTTP APIs) are the hardened defaults.
- Optional inbound **IP allow-list** (`allowed_inbound_ip_cidrs`, which becomes
  default-deny when set), optional **VNet integration** for private egress, and
  a `public_network_access_enabled` switch for private-endpoint-only setups.
- A **system-assigned managed identity** is always on, so services can talk to
  Key Vault / databases / ACR without shipped secrets.

### Health
- The platform pings `health_check_path` on every instance. After
  `health_check_max_ping_failures` consecutive failures an instance is drained
  from rotation; if it stays unhealthy for
  `health_check_eviction_time_in_min` minutes the platform replaces it. This
  contains bad deploys and failing nodes without any operator action.
- Services must implement the health endpoint (return 2xx). `/healthz` is the
  standard contract; set `health_check_path = "/"` if a service has nothing
  better.

### Rollouts
- A **staging slot** is created by default. The standard path: deploy the new
  image to the slot, verify it against production dependencies via the slot
  hostname, then swap into production. Swaps are near-instant and reversible.
- Auto-swap is deliberately *not* wired up: App Service on Linux does not
  expose auto-swap through this provider, and a deliberate swap-after-verify is
  the safer standard anyway.
- ACR image pulls can use the managed identity instead of stored credentials
  (`pull_with_managed_identity` + `container_registry_resource_id`), with the
  module granting `AcrPull` to both the app and the slot.

### Observability
- **Log Analytics workspace** receives App Service platform/container logs
  (HTTP, console, app, audit) and all metrics via a diagnostic setting.
- **Application Insights** gets request/dependency/failure telemetry through
  the connection string and instrumentation key injected as (sticky) app
  settings.
- A **multi-region URL-ping availability test** hits the health endpoint every
  5 minutes and raises availability alerts on failure.
- Decision worth knowing: this provider version only supports *classic*
  availability tests (`azurerm_application_insights_web_test`), which Azure does
  not support against *workspace-based* Application Insights. The module
  therefore provisions Application Insights as a **classic component** so the
  availability test genuinely works, while platform logs still flow to Log
  Analytics. If/when the provider gains `azurerm_application_insights_standard_test`,
  the module can move to workspace-based AI.

## Usage

```hcl
module "orders_api" {
  source = "." # or wherever this module lives

  service_name    = "orders-api"
  container_image = "myteam/orders-api:1.4.2"
  # optional overrides:
  # container_registry_url       = "https://myregistry.azurecr.io"
  # pull_with_managed_identity   = true
  # container_registry_resource_id = azurerm_container_registry.main.id
  # autoscale_max_instances      = 20
  # zone_balancing_enabled       = true
}
```

`minimal.tfvars` shows the smallest valid instantiation and plans cleanly.

## Outputs
The module exports the pieces SREs reach for operationally: app/slot IDs and
hostnames, the health-check URL, outbound IP addresses (for downstream
allow-listing), the managed-identity principal ID, the App Insights connection
string, and the Log Analytics workspace ID.
