# SRE standard Azure App Service root module

This is a standalone OpenTofu root module for containerized HTTP APIs. It deliberately creates a complete, opinionated service stack rather than exposing every App Service option:

- a Linux App Service plan and Web App;
- two baseline instances and CPU/memory autoscaling (2-6 instances by default);
- a `staging` slot for controlled swaps;
- HTTPS-only ingress, TLS 1.2+, HTTP/2, disabled FTP and publishing basic authentication, and disabled client affinity for stateless APIs;
- readiness-based load balancing and replacement through App Service health checks;
- a user-assigned workload identity, optional automatic `AcrPull` assignment, and Key Vault reference support;
- a Log Analytics workspace, workspace-based Application Insights, production and staging diagnostic settings, and standard 5xx/latency/health alerts;
- optional VNet integration, private image pulls, inbound IP restrictions, CORS, and slot-sticky settings.

No remote modules are used. `minimal.tfvars` is a runnable public-image example; it uses a paid `P1v3` plan and creates two instances plus the standard observability resources.

## Required application contract

The container must:

1. Listen on `container_port` (default `8080`). The module sets `WEBSITES_PORT` accordingly.
2. Serve an unauthenticated HTTP readiness endpoint at `health_check_path` (default `/health`). Return a 2xx/3xx response only when that instance is ready to receive traffic. Do not make the check depend on unrelated downstream services if that could remove every instance simultaneously.
3. Be stateless with respect to the local filesystem. App Service persistent shared storage is disabled. Put durable data in external storage.
4. Produce useful console/structured logs. Console, HTTP, application, audit, and platform logs are exported to Log Analytics by default.
5. Prefer an immutable image tag or digest. Do not use `latest` for real production rollouts.

The default 10-minute container start limit accommodates slow-starting images. Application settings supplied by the module cannot be overridden accidentally through `app_settings`; staging-only overrides remain possible through `staging_app_settings`.

## Minimal use

Authenticate the AzureRM provider through the environment and run:

```sh
tofu init
tofu plan -var-file=minimal.tfvars
tofu apply -var-file=minimal.tfvars
```

The three inputs without defaults are `name`, `location`, and `container_image`. `name` must be globally unique as an Azure Web App name and is also the naming prefix for the stack. The sample tfvars changes the port and health path to match Microsoft's public sample container and disables registry identity authentication because that registry is anonymous.

For a real ACR-hosted API, the essential inputs look like:

```hcl
name              = "orders-api-prod"
location          = "westeurope"
container_image   = "ordersregistry.azurecr.io/orders-api:1.4.2"
container_port    = 8080
health_check_path = "/health"

container_registry_url = "https://ordersregistry.azurecr.io"
container_registry_id  = "/subscriptions/.../resourceGroups/.../providers/Microsoft.ContainerRegistry/registries/ordersregistry"

alert_email_receivers = [{
  name          = "sre-oncall"
  email_address = "sre-oncall@example.com"
}]

tags = {
  environment = "production"
  owner       = "orders-team"
}
```

Supplying `container_registry_id` creates an `AcrPull` role assignment, so the identity running OpenTofu needs permission to create role assignments at that registry scope. Leave it null if registry authorization is managed by another platform component and grant the output workload identity `AcrPull` there. Username/password authentication is supported but managed identity is preferred.

By default a resource group named `<name>-rg` is created. To use a pre-existing group, set `resource_group_name` and `create_resource_group = false`; its region then takes precedence over `location`.

## Safe rollout workflow

The slot is intentionally **manual-swap**, not auto-swap. A successful Terraform apply is not evidence that a new application version is healthy.

1. Keep `container_image` on the current production version and set `staging_container_image` to the candidate version. Apply. Only staging changes.
2. Wait for the staging container and health check, then test the URL in the `staging_slot` output.
3. Swap `staging` to `production` with the normal Azure deployment-slot operation (portal, CLI, or pipeline).
4. Immediately promote the candidate in configuration: set `container_image` to that same image and either unset `staging_container_image` or set it to the same image. Apply to make Terraform's desired configuration agree with the post-swapped slots.

Do not apply the old pre-swap configuration after step 3, because it describes the old image assignments. Slot-sticky app settings listed in `sticky_app_setting_names` do not move during a swap; all other settings and the container image move with the application.

When a slot is not wanted, set `deployment_slot_enabled = false`. Slots require a Standard or Premium SKU; the module rejects Free/Shared/Basic SKUs in that configuration.

## Capacity and availability

With `autoscale_enabled = true` (the default), the plan starts at `autoscale_default_capacity`. Azure Monitor adds one instance when either five-minute average CPU or memory exceeds its scale-out threshold. Scale-in is deliberately conservative: both CPU and memory must be below their thresholds, and the cooldown is 15 minutes. Terraform ignores subsequent `worker_count` drift only on this autoscaled plan because Azure Monitor owns that value. Tune the min/default/max capacity and thresholds as inputs.

With autoscaling disabled, `plan_worker_count` manages a fixed instance count and remains fully under Terraform control.

The default two-instance baseline avoids a single-instance outage but is not zone redundant. For zone balancing, set `zone_balancing_enabled = true`, use a supported SKU/region, and keep both fixed capacity or autoscale minimum/default capacity at three or more. Also verify that the region/SKU combination supports zone redundancy before applying.

## Networking and secrets

`virtual_network_subnet_id` enables regional VNet integration on both slots; this is **outbound** connectivity. `vnet_route_all_enabled` controls full outbound routing and `vnet_image_pull_enabled` supports pulling through the VNet. Inbound access remains public by default. Use `ip_restrictions` with `ip_restriction_default_action = "Deny"` for allow-listing, or disable public access and create private inbound endpoints in a network stack. The same IP rules also protect SCM.

Use the output `workload_identity.principal_id` to authorize application dependencies. For secrets, grant that identity access to Key Vault and put a Key Vault reference in `app_settings`, for example `@Microsoft.KeyVault(SecretUri=https://.../secrets/.../)`. Variables and app settings are state values; marking inputs sensitive hides UI output but does not encrypt them outside the configured state backend.

## Operations

The standard alerts cover production HTTP 5xx count, average response time, and health-check status. Add `alert_email_receivers` to notify the SRE team; without receivers, alerts and autoscale events are still available in Azure Monitor. Thresholds and retention are inputs. Diagnostic categories can be reduced with `diagnostic_log_categories` when ingestion cost is a concern.

Outputs include production/staging URLs, the service plan, workload identity, observability resource IDs, and a sensitive Application Insights connection string. Run `tofu output` after apply to retrieve them.
