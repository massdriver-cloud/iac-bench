# Standard Azure App Service Module (SRE)

A standalone OpenTofu root module for deploying and operating containerized HTTP APIs on Azure App Service (Linux).

The module exposes operational levers SREs work with directly — **capacity, availability, health, rollouts, observability, networking, and security** — while encapsulating App Service internals (`WEBSITES_*` settings, stateless ARR affinity, TLS/FTP hardening, autoscale drift protection, slot warmup, and telemetry wiring).

## Architecture & Opinionated Defaults

- **Compute & Capacity (`main.tf`, `scaling.tf`)**
  - Dedicated Linux App Service Plan (`P1v3`, 2 baseline instances for HA; optionally attach to an existing plan via `capacity.existing_service_plan_id`).
  - Optional Availability Zone balancing (`capacity.zone_redundant = true`) with input validation enforcing compatible SKUs and multiples of 3 instances, automatically scaling in steps of 3.
  - Azure Monitor Autoscale scaling out on CPU (>70%), Memory (>80%), or HTTP Queue Length (>100) over 5m, and scaling in conservatively over 10m only when both CPU (<30%) and Memory (<50%) are low.
  - `lifecycle { ignore_changes = [worker_count] }` prevents Terraform drift from fighting active autoscaling events.
- **Containerized HTTP API Hardening (`main.tf`)**
  - HTTPS-only, TLS 1.2+ (configurable to 1.3), HTTP/2 enabled, 64-bit worker, `LeastRequests` load balancing, `always_on = true`.
  - `client_affinity_enabled = false` (disables ARR sticky cookies for stateless APIs).
  - FTP/FTPS and WebDeploy basic authentication disabled; `/home` SMB storage mount disabled by default (`WEBSITES_ENABLE_APP_SERVICE_STORAGE = false`).
  - System-Assigned Managed Identity (with optional User-Assigned identities), automatic `AcrPull` RBAC assignment when `container.acr_id` is supplied, and automatic `Key Vault Secrets User` RBAC + `@Microsoft.KeyVault(SecretUri=...)` formatting when Key Vault inputs are supplied.
- **Health (`main.tf`, `observability.tf`)**
  - Native App Service Health Check on `/healthz` with 2-minute unhealthy instance eviction and configurable `WEBSITE_HEALTHCHECK_MAXPINGFAILURES`.
  - Optional App Service Auto-Heal recycle rule on sustained 5xx bursts (`health.auto_heal_enabled = true`).
  - Multi-region Application Insights Standard Web Test probing `health.path` with TLS certificate expiration monitoring (automatically disabled for private-only apps).
- **Rollouts (`rollout.tf`)**
  - Production-like `staging` deployment slot provisioned by default, sharing security, VNet, health probe, identity, and diagnostic configurations.
  - Automatic swap warmup (`WEBSITE_SWAP_WARMUP_PING_PATH` and `WEBSITE_SWAP_WARMUP_PING_STATUSES`) wired to the health endpoint.
  - Sticky slot settings (`DEPLOYMENT_SLOT`, `OTEL_RESOURCE_ATTRIBUTES`, plus custom `rollout.sticky_app_setting_names`) so slot identity survives swaps.
  - Independent `rollout.staging_image` and `rollout.staging_app_settings` for testing candidate releases before swapping.
- **Observability & SRE Alerting (`observability.tf`)**
  - Log Analytics Workspace (created or shared via `observability.existing_log_analytics_workspace_id`) and Workspace-based Application Insights auto-wired via `APPLICATIONINSIGHTS_CONNECTION_STRING` and `OTEL_SERVICE_NAME`.
  - Diagnostic settings forwarding container console stdout/stderr, HTTP logs, app/platform/audit logs, and metrics from production, staging slot, and service plan.
  - Golden-signal Azure Monitor Metric Alerts for HTTP 5xx errors, response latency, health check failures, plan CPU/memory saturation, and synthetic availability.

## Quick Start

```bash
tofu init
tofu plan -var-file=minimal.tfvars
tofu apply -var-file=minimal.tfvars
```

See `minimal.tfvars` for the smallest valid instantiation.
