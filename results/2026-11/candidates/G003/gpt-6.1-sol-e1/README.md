# SRE App Service root

A directly deployable OpenTofu root for **one stateless Linux HTTP container service**. Resources are authored here; no external modules. Creates and owns a dedicated resource group, Premium v3 plan, production app, optional staging slot, workspace-based Application Insights, Log Analytics, autoscale, diagnostic exports and metric alerts.

## Run

Use OpenTofu >= 1.6 and AzureRM 4.x. Authenticate using environment credentials (including `ARM_SUBSCRIPTION_ID`), workload identity or Azure CLI. The deployment principal needs resource creation permissions and, when ACR is configured, role-assignment permissions on that registry. Azure resource providers Microsoft.Web, Microsoft.Insights and Microsoft.OperationalInsights must be available/registrable.

```sh
tofu init
tofu fmt -check
tofu validate
tofu plan -var-file=minimal.tfvars
tofu apply -var-file=minimal.tfvars
```

`minimal.tfvars` supplies all four required inputs: `name`, `resource_group_name`, `location`, `image`. Its demo image listens on port 80 and answers `/`; it deliberately overrides the production health/port defaults. Change its globally unique app name before deploying if necessary. It is a smoke-test fixture, not an application release or a low-cost sandbox: default Premium capacity and monitoring incur charges. Image accessibility, region capacity, quotas and name availability are ultimately checked by Azure during apply.

Configure a secure, locking remote state backend appropriate to your organization before production. This root deliberately does not create its own backend or store credentials in configuration. Commit the generated provider lock file. Destroying this root deletes its dedicated resource group and telemetry; do not place unrelated resources in that group.

## Operational contract and decisions

| Concern | Standard |
| --- | --- |
| Compute | Linux, single custom container, dedicated P1v3 (P2v3/P3v3 available); no shared-plan noisy neighbors between services. |
| Availability | Two workers minimum. Regional, not disaster recovery. Optional `zone_balancing_enabled` requires minimum/default capacity >= 3 and a region supporting zonal Premium v3. |
| Autoscale | 2/2/6 min/default/max workers. CPU >70% over 10 minutes adds one (5-minute cooldown); <35% over 15 minutes removes one (10-minute cooldown). Bounds 2–30. Both slots consume this same plan. |
| Scale ownership | Autoscale owns live worker count (`ignore_changes` on that field only). `capacity.default` sets initial/fallback capacity, not an immediate resize on every apply. Change min/max for ongoing capacity policy. No competing App Service automatic scaling. |
| Health | Default `/health`, three failed probes before unhealthy handling, five-minute unhealthy-worker replacement setting. Platform limits still apply; health checks do not guarantee zero downtime. |
| Warmup | Startup and slot swap warmup use the health path and require **HTTP 200**. Health endpoint must be fast, unauthenticated and nonredirecting, reflecting readiness without exposing secrets. |
| Container | Listen on `0.0.0.0:container_port` (default 8080), serve HTTP internally. Azure terminates TLS. Use immutable image tags or preferably digests; the demo's `latest` is not a production recommendation. |
| State | Stateless API: App Service persistent storage disabled, no ARR affinity. Store durable data externally; no app filesystem backup. Use backward-compatible database migrations. |
| Security | HTTPS only, TLS >=1.2 including SCM, HTTP/2, no FTP or basic-auth publishing. System-assigned identity per slot. Application authentication/authorization remains the application's responsibility. |
| Network | Public ingress on Azure hostnames for **both** slots, including staging; no private endpoint, WAF, custom domain, certificate, or inbound allowlist is provisioned. Don't expose sensitive staging functions without application authorization. |
| Egress | Optional existing delegated `integration_subnet_id`; routes all outbound traffic into that VNet. This is not private ingress. You own subnet sizing, NSGs, DNS, NAT and outbound connectivity. Allow for scaling and both slots (a /26 or larger subnet is recommended). |
| Registry | Public HTTPS registry by default. Private ACR supports managed identity + scoped AcrPull for each slot; supply `acr_resource_id` and matching `registry_url`. No stored registry passwords. |

ACR must use the conventional RBAC permissions model (not ABAC repository permissions) and be reachable by the App Service image-pull path. Private-endpoint-only registries are not supported by this root. Initial role-assignment propagation can delay image pulls; check platform logs and restart the app/slot after permissions propagate if needed. System identities are slot-specific and do not swap: grant downstream permissions to **both** identities as appropriate. Key Vault references (`@Microsoft.KeyVault(...)`) may be passed as setting values; vaults and secret-read role assignments are external responsibilities.

## Release and rollback

`staging_enabled = true` by default. No automatic swaps or traffic shifting: SRE approval is required. Always-on staging shares the plan, so reserve headroom for warmup and performance tests.

1. Keep `image` at the currently released digest. Set `staging_image` to the candidate digest and apply.
2. Check `staging_url`, its health path, smoke tests, console logs and dependencies. Azure's swap warmup is an additional gate, not a replacement for these tests.
3. Swap explicitly:

   ```sh
   az webapp deployment slot swap --resource-group <resource-group> \
     --name <app-name> --slot staging --target-slot production
   ```

4. Verify production health, latency and 5xx. **Before another apply**, record the post-swap image state in configuration: `image = candidate_digest`, `staging_image = previous_production_digest`. Run a refreshed plan and inspect all differences, especially slot configuration. This root intentionally manages images rather than ignoring release drift; a stale apply can roll a swap back. Also reconcile any other swapped nonsticky configuration.
5. To roll back promptly, run the same swap again while the previous release is still in staging, verify, then reconcile the two image inputs again. Database changes must remain compatible with both releases. No infrastructure module can automatically roll back external schema changes.

For a direct rolling update without staging, set `staging_enabled = false` and change `image`; expect platform restarts and do not assume an atomic release.

`app_settings` apply to both slots. `slot_settings.production` and `slot_settings.staging` must have identical keys and can have different values; those keys are marked sticky and stay with the named environment through a swap. Shared and slot-specific keys cannot overlap. Module-owned port, health, warmup, storage and telemetry keys cannot be overridden. Key names are visible in configuration; values are sensitive in CLI output but **still stored in state**. Prefer identity and Key Vault references over literal secrets.

Example additional inputs (merge with your own required values):

```hcl
capacity               = { minimum = 3, default = 3, maximum = 9 }
zone_balancing_enabled = true
registry_url           = "https://example.azurecr.io"
acr_resource_id        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/registry/providers/Microsoft.ContainerRegistry/registries/example"
image                  = "orders:release-42"
staging_image          = "orders:release-43"
app_settings           = { LOG_LEVEL = "info" }
slot_settings = {
  production = { SERVICE_ENVIRONMENT = "production" }
  staging    = { SERVICE_ENVIRONMENT = "staging" }
}
tags = { owner = "sre", service = "orders" }
```

## Observe and respond

* Both slots export HTTP, application, console and platform logs and metrics to a dedicated Log Analytics workspace (30-day retention). Local HTTP logs retain up to 7 days / 35 MB as a short troubleshooting buffer. Write container logs to stdout/stderr; avoid logging credentials or personal data.
* Application Insights is workspace based, with its connection string injected into both slots. **Your container must include and configure an Application Insights/OpenTelemetry SDK** for request, dependency and trace telemetry; merely injecting the connection string does not instrument arbitrary containers. Include the environment/slot in telemetry to distinguish staging from production.
* Alerts: production HTTP 5xx >10 over 5 minutes (severity 1); production average `HealthCheckStatus` <1 over 5 minutes (severity 1); plan CPU >85% over 15 minutes (severity 2). Evaluated every minute. These are baseline symptom/capacity alerts, not an SLO or external availability guarantee.
* Supply `alert_action_group_ids` for paging/notifications. Empty (the minimal example) means alert records **without notifications**; do not launch a production service without wiring a responder. External synthetic probes and service-specific latency/error-budget alerts are recommended and intentionally outside this single-service baseline.
* On CPU alarms, check autoscale history, maximum bound, memory and staging load; resize SKU for memory pressure. On health/5xx alarms, check platform/container logs, image pulls, readiness and dependency telemetry, then consider rollback. No metric alert reliably detects a complete loss of telemetry; monitor the public endpoint externally.
* Workspace ingestion and Insights use Azure's consumption billing defaults; this root sets no data cap that could silently drop incident telemetry. Review volume/cost and sampling in the application's SDK.

Outputs expose app/plan/workspace IDs, both URLs, system identity principal IDs, possible production egress addresses and a sensitive Insights connection string. Possible egress addresses are not fixed; use managed network egress/NAT when allowlists require stability.
