# Standard container App Service

Standalone OpenTofu root module for **one stateless Linux HTTP service**. It owns a resource group, dedicated Premium v3 plan, production app, optional staging slot, workspace-based Application Insights, centralized diagnostics, and actionable Azure Monitor alerts. No remote modules, external scripts, or provisioners are used.

## Start

Requires OpenTofu >= 1.6, AzureRM 4.x, and Azure credentials from the environment (for example `ARM_SUBSCRIPTION_ID`, `ARM_TENANT_ID`, `ARM_CLIENT_ID` and workload identity/OIDC credentials or `ARM_CLIENT_SECRET`). No credentials belong in tfvars. The deploying identity needs resource creation permissions; optional ACR integration additionally requires permission to create role assignments at the registry scope. Required Azure resource providers include Microsoft.Web, Microsoft.Insights and Microsoft.OperationalInsights; permit provider registration or pre-register them.

```sh
tofu init
tofu fmt -check
tofu validate
tofu plan -var-file=minimal.tfvars -out=app.plan
tofu apply app.plan
```

Change `name` to a globally unique App Service name before deployment. `name` and `container_image` are the only required inputs; `minimal.tfvars` provides literal values for both. The example deliberately uses a public demonstration image, one worker, no staging, and `/` as its health endpoint. It is the smallest supported deployment, **not** a production HA configuration. Premium capacity and log ingestion incur charges even in this example. The production-shaped example is `examples/production.tfvars`.

Use a separately configured, encrypted remote backend with locking and limited access for real environments; this root intentionally does not prescribe an organization's backend. Each service/environment needs independent state. State and saved plans contain app settings and telemetry credentials even when outputs are marked sensitive. Do not commit state, plans, or secret tfvars. Commit the generated provider lockfile.

## Operational contract and defaults

| Concern | Decision |
| --- | --- |
| Capacity | Dedicated P1v3 with two workers by default; P2v3/P3v3 supported. No free/shared SKUs. |
| Availability | Two workers protect against individual worker failure, not region failure. Optional zones require at least three workers and regional/SKU support. Zone changes may replace the plan; select at creation. No multi-region DR is implied. |
| Scaling | Fixed capacity by default. Optional CPU autoscale grows one worker above 70%/5m, shrinks one below 30%/10m, with 5m/10m cooldowns. `instance_count` is the minimum/default; `max_instances` caps cost. Staging consumes the same workers. |
| Container | One Linux container, public registry or managed-identity-authenticated ACR. Registry origin and image name are separate inputs. Use immutable image digests for reproducible promotion/rollback; `latest` is demonstration-only. |
| HTTP | Container listens on `0.0.0.0:container_port` (default 8080). TLS terminates at App Service. HTTPS-only, minimum TLS 1.2, HTTP/2, always-on, no FTP or basic publishing authentication. Session affinity is off. |
| Health | Anonymous `/health` by default, fast and side-effect-free, **HTTP 200** with no login/HTTPS redirect. Checks should cover critical readiness dependencies without making transient optional-dependency failures take down the service. Three missed probes mark unhealthy; eviction/replacement threshold is five minutes. Azure limits unhealthy-instance exclusion and health checks are not a zero-downtime guarantee, especially with one worker. |
| Rollouts | Staging enabled by default. Warmup uses the health path and accepts only HTTP 200. No automatic swap, production traffic split, or automatic rollback. |
| Storage | App Service persistent container storage disabled. Keep databases, queues and durable files outside the app; containers must tolerate restarts and SIGTERM. No database provisioning, migrations or backups are performed here. |
| Secrets | Separate system-assigned production/staging identities. Pass Key Vault references through settings; grant dependency permissions separately using identity outputs. No registry passwords. |
| Network | Public production **and staging** endpoints on Azure-managed domains/certificates. App-level authentication/authorization remains mandatory for sensitive APIs. No WAF, inbound private endpoint, custom domain or access restrictions are configured. Optional VNet integration is outbound only and does not make the app private. |

Optional `integration_subnet_id` must be an existing delegated subnet with sufficient capacity for the plan, slot and scale operations (allow upgrade/scale headroom). With route-all enabled, configure DNS, routing, NAT/firewall and required egress first. Network-restricted/private-endpoint ACR image pulls are **not** configured by this module; use a registry reachable through the default image-pull path. This module is not an internal-only API perimeter.

For private ACR set both `registry_url = "https://yourregistry.azurecr.io"` and `acr_resource_id` to the matching registry. This creates AcrPull assignments for both slot identities, with no administrative registry credential. ACR must use registry RBAC permissions, not repository ABAC. Identity role propagation may cause initial pull failures; allow propagation and restart if necessary. An infrastructure apply is not evidence that the image is healthy. Both identities need appropriate Key Vault/database permissions; identities do not swap.

### Fixed vs autoscaled capacity ownership

Fixed mode reconciles `instance_count` on every apply. Elastic mode ignores the plan's live worker count and updates autoscale minimum/default/maximum instead, so a routine apply cannot undo a scaling event. SKU and other plan settings remain managed in both modes. Scaling responds to CPU, not queue depth or memory: watch memory/latency and size appropriately.

The two modes use separate resource addresses with the **same Azure plan name**. Choose a mode before first apply. To switch an existing deployment, stop concurrent applies, back up state, change `autoscale.enabled`, and **move state before planning**, rather than destroy/recreate the plan:

```sh
# Fixed -> elastic (after changing inputs):
tofu state mv 'azurerm_service_plan.fixed[0]' 'azurerm_service_plan.autoscaled[0]'
# Elastic -> fixed: use the reverse source and destination.
```

Then plan and verify the plan itself is not replaced; only the autoscale policy should be created/deleted and any intended capacity changes made. Switching to fixed capacity may reduce running workers. Do not apply a mode toggle without this migration. Region or zone-mode changes require separate replacement planning.

## Release and rollback runbook

OpenTofu owns the image and settings, while SRE owns the explicit swap. Do not use a second deployment tool to continuously overwrite these settings.

1. Set `staging_image` to candidate B, leaving production `container_image` at known-good A. Set environment-specific `staging_app_settings`; list **all environment-specific keys** (including dependency references) in `slot_sticky_settings`. Unlisted settings swap. Module-owned settings override user values.
2. Apply the reviewed plan. Wait for healthy startup, inspect console/platform logs, and smoke-test the staging HTTPS endpoint and critical dependencies. Do not run destructive schema migrations in startup. Use expand/contract database changes compatible with both releases.
3. Promote using Azure's explicit swap operation (Azure CLI is an operator tool, not a module dependency):

   ```sh
   az webapp deployment slot swap --resource-group <resource_group_name> \
     --name <app_name> --slot staging --target-slot production
   ```

   Swapping warms the candidate with production settings. Ensure identity/network access supports this warmup; identities and some networking configuration do not swap. Validate this behavior with your application's Key Vault references before the first real release.
4. Verify production health, latency, 5xx, synthetic/user traffic and application telemetry. Keep A in staging for a rollback window. If unhealthy, issue the same swap command to swap A back, then verify recovery. A slot swap cannot undo incompatible database changes.
5. Immediately reconcile versioned inputs with the result: after successful promotion, production image B and staging image A; after rollback, production A and staging B. Reconcile any intentionally swapped non-sticky settings too. **Do not apply stale inputs after an out-of-band swap**: they would undo the release. Review a fresh plan before the next apply.

Disabling the staging slot destroys it and removes the instant swap-back target. Deployments without staging update production directly and may interrupt service.

## Observability and incident response

- HTTP access, container console and platform logs plus app metrics are exported for production and staging to a 30-day Log Analytics workspace. Short local HTTP-log retention is for immediate troubleshooting, not durable archival. Emit structured stdout/stderr logs without secrets or sensitive request bodies.
- The Application Insights connection string is injected into both slots. **Custom containers must include and configure an Application Insights/OpenTelemetry SDK**; a connection string alone does not instrument code. Set distinguishable service/role attributes for production and staging. They share an Insights resource/workspace; resource IDs distinguish platform logs.
- Five one-minute-evaluation metric alerts use five-minute windows: production 5xx total >10, average response time >2 seconds (configurable), average health status <1, plan CPU >85%, and plan memory >85%. They auto-resolve. These are initial operational thresholds, not a service-specific SLO/error-budget policy. Low traffic and missing telemetry are not equivalent to health; arrange an external synthetic availability check for end-to-end outage detection.
- Set `alert_email_addresses` to actual on-call receivers and test notification delivery. The empty default creates alerts but **does not notify anyone**. Wire the action group into your incident-management practice before production use.
- On incidents: check health and image-pull/platform logs first; correlate 5xx and latency with CPU/memory and dependencies. Scale out for CPU/load, scale up for memory pressure, and roll back recent regressions. Alerts include staging's effect on shared plan capacity.
- Log ingestion is usage-billed and uncapped to avoid silently dropping incident evidence. Set budgets and review volume/retention for your organization's compliance and cost needs. Deleting this root also deletes its telemetry resources; export evidence before teardown if retention beyond service lifetime is required.

`outputs.tf` exposes URLs, resource IDs, identities, telemetry connection string and action-group ID. All inputs and validations are in `variables.tf`. Plan success validates configuration, not Azure name availability, regional capacity/quota, private-registry reachability or application behavior; those require deployment and health testing.
