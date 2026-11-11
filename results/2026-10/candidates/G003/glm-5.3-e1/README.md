# Standard App Service module (SRE)

One module = one containerized HTTP API, running on Linux App Service the way
the SRE team wants services run: right-sized, zone-redundant, health-gated,
rollable through a staging slot, and wired into logging, APM and alerting by
default.

SREs express **capacity, availability, health, rollout and observability**
decisions. The module owns every App Service internal: TLS policy, FTPS,
health-check eviction behavior, auto-heal rules, diagnostic log categories,
managed-identity registry wiring, warmup-before-swap semantics, and so on.
There is deliberately no `site_config` passthrough.

`minimal.tfvars` is the smallest valid instantiation (4 required variables).

## What it creates

| Resource | Name | Purpose |
|---|---|---|
| Resource group | `rg-<name>` | Only when `resource_group_name` is not supplied |
| App Service plan (Linux) | `plan-<name>` | Capacity unit; zone-redundant by default |
| Linux web app | `<name>` | The service: container, system-assigned identity, HTTPS-only |
| Deployment slot | `staging` | Blue/green rollouts (same plan, no extra instances) |
| Autoscale setting | `as-<name>` | CPU / memory / HTTP-queue driven scaling with e-mail notifications |
| Log Analytics workspace | `log-<name>` | Only when `log_analytics_workspace_id` is not supplied |
| Application Insights | `appi-<name>` | Workspace-based APM; connection string injected into the container |
| Diagnostic settings | `logs-to-workspace` | HTTP/console/app/audit/IPSec/platform logs + AllMetrics, for app **and** slot |
| Action group | `ag-<name>` | On-call e-mail (+ optional webhook) receivers |
| Metric alerts | `alert-<name>-*` | HTTP 5xx, response time, CPU saturation, memory |
| Standard web test | `avail-<name>` | Synthetic GET of the health endpoint from 3 geos every 5 min |
| Role assignments | — | `AcrPull` for app and slot when pulling from a private ACR |

## Design decisions

### Capacity
- `instance_size` (default `P1v3`), `min_instances` (default 3), `max_instances` (default 10).
- Autoscale scales **out** on CPU > `scale_out_cpu_percent` (70%), memory > `scale_out_memory_percent` (85%), or HTTP queue > `scale_out_http_queue_length` (100, request backpressure). It scales **in** on CPU only, with a 10-minute cooldown, so the plan does not flap under bursty traffic.
- Fixed capacity: set `max_instances = min_instances`. The autoscale setting stays (it pins the count) so there is no drift between Terraform and Azure.
- Worker count is never written into the plan resource itself; the autoscale setting owns it.

### Availability
- `zone_redundant = true` by default: instances spread across availability zones. Enforced by preconditions to require a Pv3/Pmv3/PC SKU and `min_instances >= 3`.
- `always_on`, `https_only`, minimum TLS 1.2, HTTP/2, FTPS disabled.
- Health-check-gated load balancing (below) means a bad instance never receives traffic.

### Health
- App Service built-in **Health check** polls `health_check_path` (default `/healthz`, `""` disables) on every instance. Instances that fail are removed from the load balancer and restarted after the eviction window.
- **Auto-heal**: a worker that returns 20+ responses in the 500-599 range within 2 minutes is recycled before instance-level eviction is needed.
- **Synthetic availability test**: an Application Insights standard web test GETs the health endpoint from 3 geographies every 5 minutes and expects HTTP 200. It is disabled automatically when the app is not publicly reachable (IP allow-list set or public network access disabled), because the probes come from the internet.

### Rollouts
- A `staging` slot is created by default, mirroring production (same image pin, health check, TLS policy, identity, network config), so a swap cannot surprise you.
- Recommended release flow:
  1. CI builds and pushes the image.
  2. CI deploys the new tag to the staging slot (`az webapp config container set --slot staging` or the REST API).
  3. CI waits for the slot's health check to pass (App Service removes unhealthy instances from rotation automatically).
  4. CI swaps: `az webapp deployment slot swap` — App Service warms the target before cutover, so the swap is zero-downtime.
  5. Open a PR bumping `container_tag` so Terraform state matches what is running. Applying with a stale pin would redeploy the old version — keep the pin in sync as part of the release.
- `enable_auto_swap = true` lets step 4 happen automatically as soon as staging is warm.
- `sticky_app_settings` lists settings that must not travel with a swap (e.g. staging pointing at non-production dependencies).

### Observability
- All App Service log categories (`AppServiceHTTPLogs`, `AppServiceConsoleLogs`, `AppServiceAppLogs`, `AppServiceAuditLogs`, `AppServiceIPSecAuditLogs`, `AppServicePlatformLogs`) plus `AllMetrics` are shipped to a Log Analytics workspace — one created by the module, or your central one via `log_analytics_workspace_id`.
- Application Insights is always created (workspace-based). `APPLICATIONINSIGHTS_CONNECTION_STRING` and `APPINSIGHTS_INSTRUMENTATIONKEY` are injected as app settings; sampling is tunable via `app_insights_sampling_percent`.
- Standard alerts page the on-call channel (`alert_emails`, required — the module will not deploy an unmonitored service; optional `alert_webhook_url` for PagerDuty/Opsgenie):
  - HTTP 5xx count over threshold in 5 min (severity 1)
  - average response time over threshold in 5 min (severity 2)
  - worker CPU above threshold for 10 min — i.e. autoscaling is not keeping up (severity 3)
  - worker memory above threshold for 10 min (severity 3)
- Autoscale scale-out/scale-in events notify the same addresses.

### Security & networking
- System-assigned managed identity on the app **and** the slot. Key Vault references in `app_settings` (`@Microsoft.KeyVault(...)`) work out of the box.
- Registry access: `container_registry_id` (Azure Container Registry) pulls with the managed identity and grants `AcrPull` automatically — on first deploy the app may retry the image pull for a few minutes until RBAC propagates. For other registries, use `container_registry_url` + `container_registry_username`/`container_registry_password`.
- Optional IP allow-list (`allowed_ip_address_ranges`, applies to app and slot) and VNet integration with route-all (`vnet_integration_subnet_id`).
- `public_network_access_enabled = false` for private-only deployments.

### Application configuration
- `app_settings` is the single config surface, injected as environment variables into the container. Module-managed settings (`WEBSITES_PORT`, `WEBSITES_ENABLE_APP_SERVICE_STORAGE`, Application Insights wiring, registry credentials) always win, so the platform guarantees stay intact.
- `cors_allowed_origins` configures CORS when the API is called from browsers.

## Non-goals (v1)

- Custom domains and managed certificates — DNS-dependent, add when a service needs a vanity host.
- Private endpoints — VNet integration is supported, Private Link is not.
- App Service backups — containerized APIs are stateless; persist state elsewhere.
- Databases, queues and other dependencies — this module runs your container, nothing else.

## Notes

- The web app name is a global DNS label (`<name>.azurewebsites.net`); pick unique `name` values.
- Use the module once per service. Decommissioning a service is `tofu destroy` of its instantiation.
