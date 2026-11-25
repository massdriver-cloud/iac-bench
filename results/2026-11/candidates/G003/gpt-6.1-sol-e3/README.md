# SRE App Service root module

Standalone OpenTofu root for one stateless Linux HTTP container service. All Azure resources are authored here; no remote modules. The module owns a dedicated resource group, Premium v3 Linux plan, production web app, optional staging slot, system-assigned identities, Log Analytics, workspace-based Application Insights, diagnostics, CPU capacity controller, metric alerts and an action group.

## Run

Authenticate with Azure using the standard AzureRM environment variables (including `ARM_SUBSCRIPTION_ID`), or a supported workload identity. The deploying principal needs resource creation permissions and, for private ACR, role assignment permissions on the registry. Provider resource registration may require subscription-level rights or pre-registration by your platform team.

```sh
tofu init
tofu fmt -check
tofu validate
tofu plan -var-file=minimal.tfvars
tofu apply -var-file=minimal.tfvars
```

`minimal.tfvars` supplies both required inputs (`name`, `container`) with a public Nginx image, one fixed worker, no staging slot and `/` health endpoint. It is a small functional demonstration, **not an HA production deployment**. Change its globally unique name before deployment. `production.tfvars` exercises the default two-worker, autoscaling, staging configuration; replace the placeholder alert email before use. Azure quota, SKU/zone availability and global name availability must be verified in your subscription; a clean plan is not an availability guarantee.

For production supply your own image, preferably pinned by digest, listening port, readiness endpoint, tags and on-call email addresses. Required input schemas, defaults and validation are documented in `variables.tf`. Use remote, encrypted, access-controlled state and CI concurrency locking; no backend is hardcoded. Sensitive settings still exist in state.

## Operating contract

- Default capacity is two P1v3 workers, CPU scale-out above 70% averaged over five minutes and scale-in below 30% over ten minutes, one worker per action, bounded at 2–6. Scale-out cooldown is five minutes, scale-in ten. This is a baseline, not a workload-specific SLO; load-test before choosing limits. Slots share the plan's workers and affect CPU-based scaling.
- Azure Monitor owns worker count after creation; OpenTofu ignores runtime worker-count drift. When `autoscale_enabled=false`, the controller remains enabled with equal minimum/maximum/default values, enforcing `default_instances` as a fixed size. Changes to this input still converge through the controller rather than fighting Azure on every apply.
- Two workers protect against worker failure, **not regional failure**. Zone redundancy is opt-in, requires at least two workers and regional/SKU support. No cross-region disaster recovery, data backup or persistence is provisioned. Containers must be stateless, tolerate termination/restarts, and use external durable stores. The App Service shared content mount is disabled.
- Always On, a five-minute unhealthy-worker eviction window and readiness probes are configured. The default `/health` must be a lightweight, unauthenticated endpoint returning a 2xx without redirects. Swap warm-up accepts **200 only**, so implement that response for rollout readiness. Probes are not an external availability test, and health eviction is not meaningful redundancy on one worker. Single-region synthetic availability testing should be added by the platform according to the actual public/private ingress path.
- HTTPS only, minimum TLS 1.2 for app and SCM, HTTP/2, no FTP/basic publishing credentials, no client affinity, no remote debugging. App Service provides its default hostname certificate. Custom domains, customer-managed certificates, WAF, gateway routing and application authentication/authorization are outside this module. The app is public by default: do not deploy an unauthenticated sensitive API without an appropriate ingress/authentication layer.
- Optional CIDR restrictions apply to production and staging, and SCM inherits them. An empty list allows public sources. Do not lock out your deployment agents. Staging is also public by default; avoid destructive migrations/background jobs there, and restrict ingress where needed.
- Optional outbound VNet integration uses an existing delegated subnet and routes outbound traffic through it. Provide adequate subnet capacity for both slots and scale transitions, NSG/UDR connectivity and DNS. This does **not** create inbound private access. Disabling public access requires separately provisioned private endpoints for both app and slot and correct private DNS. Private registry image pulling may additionally require enabling VNet image pull and configuring private registry DNS; private-endpoint registry plumbing is not created by this module.

## Images, identity and settings

Public registries work without credentials. For private ACR use `container.registry_url = "https://<registry>.azurecr.io"`, an image name relative to that registry, and its full resource ID in `container.registry_resource_id`. AcrPull is granted independently to the production and staging system identities. The registry must support classic AcrPull authorization; ABAC repository-scoped authorization is not configured. Registry firewall/private networking remains your responsibility. System identity is created with the app, so the first image pull can fail until the role assignment propagates; wait for propagation and restart the app/slot before investigating application failures. Other private registries with username/password are deliberately not supported.

Use `app_settings` for application settings, preferably Key Vault references, not literal secrets. Grant Key Vault Secrets User (or equivalent access policy) to **both** output principal IDs outside this module, and ensure network access to the vault. Platform settings take precedence over supplied values. The production and staging settings are identical initially; both identities are separate and do not swap. `slot_sticky_setting_names` marks additional names as slot-bound. This module does not define separate staging connection settings, so add a local extension before connecting staging to different data stores. Application Insights connection string is sticky automatically.

## Rollouts and rollback

OpenTofu owns container image configuration: do not have CI continually overwrite the image behind its back.

1. Keep `container.image` at the current production digest. Set `staging_image` to the candidate digest and apply. Staging uses the same port, registry, health endpoint and application settings as production.
2. Wait for the staging health endpoint to return 200, exercise smoke/integration tests through `staging_url`, inspect logs and telemetry, and confirm migrations are backward compatible. Provisioning success alone does not certify application health.
3. Perform an explicit swap after approval:
   ```sh
   az webapp deployment slot swap --resource-group <resource_group_name> \
     --name <app_name> --slot staging --target-slot production
   ```
4. Monitor production alerts and real traffic. Immediately reconcile source configuration to `container.image = <candidate>` and `staging_image = <previous production digest>` **before the next apply**. Otherwise OpenTofu will revert the swapped images. Review the full post-swap plan for settings drift as well.
5. To roll back, swap the old image back from staging while still compatible with persisted data, then reconcile the two image inputs again. Alternatively redeploy a known-good digest explicitly. Keep old digests available in the registry. No automated swap, canary routing or rollback is performed by this module.

The slot is optional; turning it off destroys staging. Rollouts without it update production directly and may interrupt service. No infrastructure setting guarantees zero downtime for an unhealthy or incompatible container.

## Observability and on-call

All App Service diagnostic log categories plus platform metrics are sent to a dedicated workspace from production and staging, with 30-day retention by default. Local HTTP logs retain up to 35 MB for three days; centralized storage is the long-term destination. Emit structured logs to stdout/stderr and avoid credentials/PII in requests and logs. The Insights connection string is injected, but **the application must ship an appropriate SDK or OpenTelemetry Azure Monitor exporter**: setting a connection string does not auto-instrument arbitrary containers. Use distinct cloud role/slot attributes in application telemetry to distinguish staging from production.

Production alerts evaluate every minute across five minutes: at least 10 HTTP 5xx responses (severity 1), health-check average below 100% (severity 1), and mean HTTP response time over two seconds (severity 2). Tune these baseline signals to service SLOs in this root's alert definitions; they are not traffic-normalized error budgets or percentile latency alerts. No-data is not treated as downtime, so use an external synthetic probe for end-to-end coverage. Empty email recipients means alerts exist **without notification actions**; wire real recipients and test notification delivery before production. The action group ID is exposed for integration with platform incident tooling. Review deployment events, dependency telemetry, saturation and readiness failures before scaling or rolling back.

Diagnostics and 100% default Insights sampling can incur significant ingestion costs. Retention is configurable, but no daily quota intentionally drops incident telemetry. Establish budgets and sampling policies appropriate to each service. Infrastructure destroy removes the app, monitoring resources and retained logs along with the dedicated group; apply normal change controls and export records that require independent retention.

## Verification

Validated with `tofu validate` and clean plans using both `minimal.tfvars` and `production.tfvars`. No cloud apply or live health/rollout test was performed. Run post-apply health, registry access, scaling, alert-delivery and swap/rollback tests before accepting a service into production.
