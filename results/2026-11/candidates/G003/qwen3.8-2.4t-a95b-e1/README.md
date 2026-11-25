# Standard App Service Module (containerized HTTP APIs)

The SRE team's one standard way to run a containerized HTTP API on Azure App
Service. Instead of hand-tuning App Service per app, you declare **what** the
service is (name, region, container image) and the module makes every
operational decision: capacity, availability, health, rollouts and
observability.

## What gets created

```
resource group (<name>-rg)
├── App Service Plan  <name>-plan   Linux, P1v3, zone-balanced, 3 instances
│   └── autoscale policy            CPU 70%↑ / 30%↓, grows to 10
├── Web App           <name>        container runtime, HTTPS-only, health checks
│   ├── staging slot                deploy → verify → swap
│   ├── system-assigned identity    (+ AcrPull if container_registry_id set)
│   └── diagnostic setting ─────────────┐
├── Application Insights <name>-ai ─────┤
└── Log Analytics ws     <name>-law ◄───┘  (or an existing workspace you supply)
```

## Design decisions (defaults; all overridable)

### Capacity
- **Linux Premium v3 plan** (`sku_name = "P1v3"`): production-grade,
  zone-capable, scales.
- **3 baseline instances** (`instance_count`) — enough to survive a zone or
  instance loss during replacement.
- **CPU autoscale on by default**: scale out +1 above 70% CPU (5 min window),
  scale in −1 below 30%, ceiling `autoscale_max_instances = 10`. Set
  `autoscale_enabled = false` for fixed capacity.

### Availability
- **Zone balancing on** (`zone_balancing_enabled`): instances spread across
  availability zones.
- **Always on**, so cold starts never eat first requests.
- **HTTPS-only**, **TLS ≥ 1.2**, **FTP(S) disabled** — no plaintext paths in.

### Health
- **Health probes** on `health_check_path` (default `/health`); instances
  failing probes for `health_check_eviction_minutes` are evicted and the
  platform replaces them — wedged or broken containers don't linger in
  rotation.

### Rollouts
- A **`staging` slot** mirrors the production config. Roll out by pointing the
  module at a new `image_tag` (lands in staging via your pipeline or a targeted
  update), verify against the slot hostname, then swap.
- `auto_swap_enabled = true` makes staging auto-swap into production after
  each deployment for hands-free promotion.

### Observability
- **Application Insights** (workspace-based) created and injected into the
  container via `APPLICATIONINSIGHTS_CONNECTION_STRING` — APM with zero code
  changes.
- **Log Analytics**: one workspace per service by default; pass
  `log_analytics_workspace_id` to centralize into a shared workspace.
- **Diagnostic settings** stream HTTP, app, console, audit and platform logs
  plus all metrics into Log Analytics, with `log_retention_days` (default 30)
  retention everywhere.

### Sensible knobs, not a config dump
- Private registry? Set `container_registry_id` for **AcrPull via managed
  identity** (no secrets), or `container_registry_username/password`.
- Need VNet egress? Set `virtual_network_subnet_id` (route-all enabled).
- Extra env vars? `additional_app_settings` — merged after module defaults,
  so you can override anything the module sets.

## Usage

```hcl
module "orders_api" {
  source = "."

  name     = "orders-api"
  location = "westeurope"

  image_name = "product-team/orders-api"
  image_tag  = "1.4.2"

  # e.g. private ACR, pulled with managed identity (no secrets):
  # container_registry_id = module.acr.id
}
```

A complete minimal example lives in [`minimal.tfvars`](minimal.tfvars):

```
tofu plan -var-file=minimal.tfvars
```

Required inputs: `name`, `location`, `image_name`, `image_tag`. Everything
else has an SRE-approved default.

## Notes for operators

- The module **creates its own resource group**; it owns the whole lifecycle.
- Azure credentials come from the environment (`ARM_SUBSCRIPTION_ID`, etc.) —
  nothing is hardcoded.
- Pick a region with availability zones (e.g. `westeurope`) or set
  `zone_balancing_enabled = false`.
- `WEBSITES_ENABLE_APP_SERVICE_STORAGE` is `false` (recommended for custom
  containers); if you need shared storage, override it in
  `additional_app_settings`.
- Rollback = point `image_tag` back at the previous tag and re-apply, or swap
  the slots back.
