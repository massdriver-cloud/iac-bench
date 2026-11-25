# Standard Azure App Service Module (SRE)

A standalone OpenTofu root module for deploying and operating containerized HTTP APIs on Azure App Service. Designed around SRE operational primitives — **capacity**, **availability**, **health**, **rollouts**, and **observability** — while encapsulating App Service internals behind hardened defaults.

## Design Decisions

- **Capacity & Availability**: Translates `availability.tier` (`zone_redundant`, `multi_instance`, `single_instance`) and `capacity.size` (`micro`, `small`, `medium`, `large`) into Premium v3 SKUs (`P0v3`–`P3v3`), zone balancing (`worker_count >= 3`), and CPU/memory horizontal autoscaling (scaling in steps of 3 when zone-redundant to preserve AZ balance). `worker_count` is ignored on plan updates so OpenTofu runs never scale down an actively autoscaled service during peak traffic.
- **Hardened HTTP API Internals**: Enforces HTTPS-only, TLS 1.2+, HTTP/2, 64-bit workers, `always_on = true`, disabled ARR session affinity (`client_affinity_enabled = false`), disabled FTP/basic-auth publishing, disabled slow SMB `/home` storage (`WEBSITES_ENABLE_APP_SERVICE_STORAGE = "false"`), and automatic Managed Identity ACR pulls for `*.azurecr.io` registries.
- **Health & Warmup**: Configures App Service health probes (`health.path`, default `/healthz`), unhealthy instance eviction (`health.eviction_time_in_min`), `LeastRequests` load balancing, container startup timeout (`WEBSITES_CONTAINER_START_TIME_LIMIT`), and swap warmup pings (`WEBSITE_SWAP_WARMUP_PING_PATH`) so cold or unhealthy containers never receive production traffic.
- **Zero-Downtime Rollouts**: Provisions a full-parity `staging` deployment slot by default with sticky slot settings (`APP_SLOT_NAME` plus caller-defined keys), independent staging access controls, and optional IaC-staged image overrides (`rollouts.staging_image`).
- **Observability & Golden-Signal Alerts**: Wires platform logs (`AppServiceHTTPLogs`, `AppServiceConsoleLogs`, `AppServiceAppLogs`, `AppServicePlatformLogs`, `AppServiceAuditLogs`) and `AllMetrics` from production, staging, and the App Service Plan to Log Analytics (created by default or attached to an existing workspace), provisions workspace-backed Application Insights (`APPLICATIONINSIGHTS_CONNECTION_STRING` injected automatically), and deploys golden-signal metric alerts for **HTTP 5xx errors**, **response latency**, **health check degradation**, **plan CPU saturation**, and **plan memory saturation**, plus an optional multi-region synthetic availability check.

## Usage

Minimal deployment (`minimal.tfvars`):

```bash
tofu init
tofu plan -var-file=minimal.tfvars
tofu apply -var-file=minimal.tfvars
```

Typical production rollout flow:
1. Deploy candidate image to the staging slot (via CI/CD or `rollouts.staging_image`).
2. Smoke-test `staging_url` (`https://<app>-staging.azurewebsites.net`).
3. Swap `staging` into `production` (App Service automatically verifies `health.path` returns `200` before routing traffic).
