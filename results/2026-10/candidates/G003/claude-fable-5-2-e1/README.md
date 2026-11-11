# Standard App Service module

One containerized HTTP service on Azure App Service (Linux), with the SRE standards built in.
Root module: plan/apply it directly, one state per service.

```hcl
# orders-api-prod.tfvars
name              = "orders-api-prod"
location          = "eastus2"
image             = "myacr.azurecr.io/payments/orders-api:1.4.2"
health_check_path = "/healthz"

registry = { acr_id = "/subscriptions/.../registries/myacr" }
alerts   = { action_group_ids = ["/subscriptions/.../actionGroups/sre-oncall"] }
```

## What you get

| Concern       | What the module does |
|---------------|----------------------|
| Capacity      | Dedicated Premium v3 plan per service. Autoscale on plan CPU and memory between `capacity.min_instances` and `max_instances` (default 3-10). Instance count is owned by autoscale, never reset by an apply. |
| Availability  | Zone-redundant by default (3 instances over 3 zones). Always on. |
| Health        | `health_check_path` drives instance eviction/replacement, the readiness gate for new containers and releases, and the unhealthy-instance alert. |
| Rollouts      | Changing `image` (or any app setting / secret reference / port) is a release: it starts in a fresh staging slot, must pass the health endpoint on every instance, and is then swapped into production without cold start. A release that never becomes healthy fails the apply and leaves production on the previous version. The previous release stays warm in the staging slot; `rollback_command` output swaps it back in seconds. |
| Observability | HTTP access, container console, platform and audit logs plus metrics for app, staging slot and plan go to Log Analytics. Workspace-based Application Insights with the connection string injected. Alerts on 5xx, latency, unhealthy instances and plan CPU/memory saturation. |
| Security      | HTTPS only, TLS 1.2+, FTP and basic-auth publishing disabled, user-assigned managed identity for ACR pulls (no registry passwords) and Key Vault references (no secrets in state). Optional IP / service-tag allow-list, VNet integration and private endpoint. |

## Things to know

- **Alerts page nobody until you set `alerts.action_group_ids`.**
- **Defaults are production-sized** (3 x P1v3, zone redundant). For dev:
  `capacity = { sku = "P0v3", min_instances = 1, max_instances = 2, zone_redundant = false }`.
  `zone_redundant` cannot be flipped later without replacing the plan.
- **Public by default** (HTTPS only). Restrict with `network.allowed_cidrs` / `allowed_service_tags`,
  or go private with `network.private_endpoint` + `public_access_enabled = false`.
- **Without `registry.acr_id` images are pulled anonymously** - fine for public registries only.
  Private registries other than ACR are not supported (it would mean storing a registry password).
- **The health gate is the only release gate.** There is no manual approval or percentage canary; a
  release that answers healthy is promoted. Make the health endpoint mean "ready to serve".
- **Production's image and app settings are only reconciled at release time.** Manual edits in the
  portal are not shown as drift; `tofu apply -replace=terraform_data.release` re-releases the declared
  configuration. After an emergency `rollback_command`, set `image` back to the previous version.
- Platform settings that are not part of a release (access rules, VNet, health-check timing) are
  applied in place to both slots.
- The module assigns roles (AcrPull, Key Vault Secrets User) when `registry.acr_id` / `key_vault` are
  set, which needs role-assignment rights; switch that off with `grant_pull` / `grant_access = false`.
- Not included: custom domains / certificates, built-in authentication (Easy Auth), outside-in
  availability tests. Put Front Door or Application Gateway in front for custom domains and WAF.
