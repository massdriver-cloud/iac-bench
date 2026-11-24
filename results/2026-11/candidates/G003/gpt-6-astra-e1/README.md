# SRE App Service standard

Standalone OpenTofu root for **one stateless Linux HTTP container service**. All resources are authored here; there are no remote modules. Each deployment owns a resource group, dedicated Premium v3 plan, production app, managed identity, monitoring, and (by default) a warm staging slot.

## Deploy

Requires OpenTofu >= 1.6 and AzureRM >= 4.81, < 5. The provider lock file is included. Authenticate through AzureRM environment variables, including `ARM_SUBSCRIPTION_ID`; prefer workload identity/OIDC in CI.

```sh
tofu init
tofu validate
tofu plan -var-file=minimal.tfvars -out=deployment.plan
tofu apply deployment.plan
```

The three required inputs are `name`, `location`, and `container_image`. `minimal.tfvars` supplies literal values for all three and selects **one worker, no staging, no CPU scaling**. This is a smoke-test configuration, not an HA production example. It still incurs Premium plan and monitoring costs. Change its globally unique name before deploying another copy.

For production, start with `examples/production.tfvars` instead. Replace the sample image, set a dependency-aware readiness path and alert recipients, and check regional capacity/zone support. The two tfvars files are alternative configurations, not files to combine.

The deploying principal needs resource creation permissions and, when using ACR, role-assignment write permission on that registry. Register required resource providers or allow AzureRM to register them. No cloud credentials are embedded here.

## Operating decisions

| Concern | Standard |
|---|---|
| Capacity | Dedicated P1v3 plan, selectable P2v3/P3v3. Defaults to 2–4 workers. Staging shares this capacity. |
| Autoscale | Plan-average CPU >70% for 5 minutes adds one worker; <30% for 15 minutes removes one. Cooldowns are 5/10 minutes. Bounds and thresholds are configurable. |
| Fixed capacity | `capacity.autoscale_enabled = false` uses a controller profile with equal minimum/maximum and no CPU rules. Set `capacity.minimum` to resize. Azure Monitor remains enabled to enforce the fixed bound. |
| Ownership | Azure Monitor owns live worker count. OpenTofu ignores only this field after creation, avoiding resets on unrelated applies. No competing App Service automatic-scaling controller. |
| Availability | Two workers and Always On by default. Optional `zone_redundant` requires region support and at least two workers. Off by default for regional portability. Single-region only, not regional DR. |
| Container | Linux/amd64, explicit non-latest tag or digest. Prefer a digest; tag immutability cannot be verified here. Bind HTTP to `0.0.0.0` on `container_port` (default 80). |
| Health | `health_check_path` defaults to `/` for the example. Real services should use a fast, unauthenticated, dependency-aware endpoint returning 200 without redirects. The same path gates startup/swap warm-up. Health-check eviction is configured to five minutes; replacement behavior remains subject to Azure limits. |
| Rollout | Warm staging slot by default. No automatic swap, traffic split or pipeline execution. Slots share plan, identity, runtime configuration and ingress policy. |
| Transport | HTTPS only, TLS >=1.2 on app/SCM, HTTP/2, FTP disabled, FTP/SCM publishing basic auth disabled. Use Azure RBAC-authenticated deployment tooling. Session affinity off. |
| Data | Stateless containers. Persistent App Service `/home` storage disabled. Externalize sessions, files and databases. No application-data backups created. |

CPU is a general-purpose scaling signal, not an SLO. Load-test and account for I/O-bound workloads, dependency limits, startup latency and the scale ceiling. Staging contributes to plan CPU and consumes production headroom; do not perform heavy staging load tests on a production plan. One-worker configurations cannot route around a failed worker.

## Registry and secrets

Public Docker Hub is the default. Private ACR example:

```hcl
registry = {
  server_url  = "https://myregistry.azurecr.io"
  resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/registry-rg/providers/Microsoft.ContainerRegistry/registries/myregistry"
}
container_image = "team/api:2026.01.15"
```

A shared user-assigned identity receives `AcrPull` on the registry and is configured for both slots. Use an ACR permission mode supporting `AcrPull`; ABAC repository permissions and password-authenticated third-party private registries are outside scope. Resource ordering is enforced, but RBAC propagation can briefly delay the first pull. Verify startup before promotion.

`app_settings` supplies production environment variables. Staging inherits them with `staging_app_settings` overrides. **Override production dependency endpoints and credentials for staging**; inheritance is not isolation. User setting names and module-owned runtime settings are slot-sticky. The module's port, warm-up, storage and telemetry settings take precedence. Do not set provider-managed registry credentials or `WEBSITE_HEALTHCHECK_MAXPINGFAILURES` yourself; health timing is owned by `site_config`.

Prefer `@Microsoft.KeyVault(SecretUri=https://...)` references over literal secrets. The shared identity is selected for Key Vault references; grant it minimal access externally. Staging is **not a security boundary** from production: untrusted test code needs a separate deployment and identity. Sensitive input marking hides values in output but does not remove them from state.

## Network boundary

Ingress, including staging, is public by default. Application authentication/authorization remains the product team's responsibility. `allowed_ip_cidrs` switches both apps and SCM to an allowlist with default deny; include deployment-agent addresses.

There are no private endpoints, custom domains, WAF, custom certificate management or built-in application authentication settings. Azure's hostname has platform-managed TLS. Establish your edge/auth requirements before exposing a real API.

`integration_subnet_id` enables **outbound** regional VNet integration of both slots, not private ingress. Supply an existing delegated `Microsoft.Web/serverFarms` subnet in a compatible region, with sufficient scale/upgrade/slot capacity (a /26 or larger is a good starting point). Image pulls use this VNet too. Application egress is all-routed by default; `vnet_route_all_enabled = false` opts out of all-traffic routing. The caller owns DNS, NAT, NSGs and routes, including registry, Key Vault, telemetry and dependency connectivity. For stable egress, use an externally managed NAT Gateway instead of treating the output IP list as fixed.

## Release and rollback runbook

1. Build, scan and push an immutable candidate. Save the current production reference.
2. Leave `container_image` unchanged; set `staging.container_image` to the candidate and apply. Check staging uses safe dependencies.
3. Wait for startup and repeated successful readiness checks. Smoke-test real requests and inspect telemetry. A successful infrastructure apply does not certify image pull or application health.
4. Serialize deployment/apply jobs and promote explicitly:

   ```sh
   az webapp deployment slot swap \
     --resource-group "$(tofu output -raw resource_group_name)" \
     --name "$(tofu output -raw app_name)" \
     --slot staging --target-slot production
   ```

5. Verify production errors, latency, health and dependencies. Keep the old image in staging during the rollback window. Swap back with the same command if necessary. Database migrations must be backward-compatible; swapping does not roll back data.
6. **Before another apply**, record the actual post-swap mapping in tfvars: production becomes the promoted image and staging becomes the old production image. Record the reverse mapping after rollback. Run a fresh plan. Images are intentionally not ignored, so stale configuration will revert a release. Never apply a saved pre-swap plan afterward.

Staging initially defaults to the production image. Set it explicitly during releases, otherwise production image changes update staging too. Swaps reduce interruption but do not guarantee zero downtime. Test graceful shutdown, long-lived connections and warm-up. Direct production image/environment changes can restart production.

## Observability

- Dedicated Log Analytics workspace, default 30-day retention (`log_retention_days`, 30–730). Both slots export all supported platform log categories and metrics. Local HTTP logs have a short 3-day/35 MB buffer.
- Workspace-based Application Insights connection string is injected into both containers. **The image must configure an Application Insights or OpenTelemetry SDK/exporter** to emit traces, dependencies, exceptions and application metrics. A connection string alone does not instrument an arbitrary container. Label telemetry by service, version and environment/slot to separate staging. Emit structured stdout/stderr without secrets.
- Baseline production alerts: >5 HTTP 5xx in five minutes; sustained near-zero health-check status per instance over five minutes; plan CPU >90% for fifteen minutes. These are not a complete SLO or external reachability test. Add SRE-platform synthetic probes, dashboards and paging integrations using the exported resource IDs.
- `alert_email_addresses` supplies action-group recipients. Empty by default means alerts exist but **nobody is notified**. Configure real recipients and test delivery before launch.
- During incidents: inspect activity/release history, health, HTTP errors and container startup logs, then CPU, instance count, registry access, DNS/egress and dependencies. Distinguish saturation from app failures before scaling or rolling back.

Workers, log ingestion, Insights and metric-alert time series are billable. Workspace ingestion has no hard cap here to avoid silently dropping incident evidence; manage budgets, SDK sampling and log volume externally. Workspace-based Insights retention follows workspace/table policies; externally configured per-table policies can override workspace defaults.

## State, lifecycle and verification

Use one state per service/environment. Configure an encrypted, access-restricted remote backend with locking before production use; no organization-specific storage account or credentials are embedded. Treat state and saved plans as secrets.

Review replacements when changing names, location or zone topology. Destroy deletes the owned resource group and telemetry resources; export evidence according to retention policy first. Registry, subnet and application dependencies are external and not destroyed here.

Validated with `tofu validate` and clean plans for `minimal.tfvars` and `examples/production.tfvars`. Planning checks schemas and expressions, not global name availability, regional SKU/quota availability, RBAC/network propagation or application health. No apply or runtime health test was performed.
