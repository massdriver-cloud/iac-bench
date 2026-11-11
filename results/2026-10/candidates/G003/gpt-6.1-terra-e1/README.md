# App Service for a containerized HTTP service

This root configuration creates a dedicated resource group, Linux App Service plan, web app, workspace-backed Application Insights, diagnostic settings, CPU autoscaling, and a 5xx metric alert. The default P1v3 plan starts with two workers and scales between two and four. It incurs Azure charges, including workspace ingestion and retention. It is regional, not a disaster-recovery or zone-redundancy solution.

## Deploy

Use an Azure identity with permission to create resources in the subscription. Set `ARM_SUBSCRIPTION_ID` and authenticate using the normal AzureRM environment credentials. Choose a globally unique `name` (the sample name may already be taken), an available region, and a plan SKU/instance count supported by your subscription and regional quota. Set `container_image`, `container_registry_url`, `container_port`, and `health_check_path` for the service. The default image is a public example, not a production service. Prefer immutable image tags or digests.

```
tofu init
tofu plan -var-file=minimal.tfvars
tofu apply -var-file=minimal.tfvars
```

`minimal.tfvars` is a starting point, not a reusable globally unique name. The RG is owned by this configuration; destroying it deletes all its resources. Outputs include the production and optional staging URLs, application identities, and observability resource IDs. State contains sensitive settings and credentials: secure the state backend and access to it. `app_settings` and `staging_app_settings` are sensitive but are still stored in state; use Key Vault references rather than literal secrets. Grant each slot's system-assigned identity access to any referenced secrets separately.

## Runtime and scaling

The image must listen on `container_port` and respond to the unauthenticated `health_check_path` with HTTP 200–299. App Service probes the path and can remove unhealthy workers; the default `/` is appropriate only if it represents service health. HTTPS is required, TLS 1.2 is the minimum, FTP and basic publishing authentication are disabled, and Always On is enabled. Both production and staging endpoints are publicly reachable; this module does not configure access restrictions, private endpoints, VNet integration, custom domains, or authentication.

Autoscaling adds a worker when average plan CPU exceeds 70% over five minutes and removes one when below 30% over 15 minutes, within the configured bounds. Workers are shared by both slots. Select a SKU supporting autoscaling and the desired instance count; if using staging, select one supporting slots. Scale limits are not validated against the chosen SKU. `worker_count` is ignored after creation to avoid fighting autoscale. If autoscaling is disabled, subsequent changes to `minimum_instances` will not change the plan's instance count: manage its capacity separately, or enable autoscaling and adjust the bounds. Multiple workers improve resilience but do not by themselves guarantee zone or region availability.

For an Azure Container Registry using registry-level RBAC, set `acr_resource_id` and its matching HTTPS `container_registry_url`. The module creates a user-assigned pull identity and grants `AcrPull` at the registry. The deploying identity must be authorized to create that role assignment; ACR and image pull must be network reachable. Role assignment propagation can delay initial pulls. ABAC-enabled registries, network-restricted registries, and authenticated non-ACR registries require additional configuration outside this module.

## Rollouts

Set `enable_staging_slot` to create a second endpoint and use `staging_container_image` for a candidate. Verify the slot and perform the swap separately through Azure tooling; this configuration does not trigger swaps or automatically shift traffic. Use `staging_app_settings` for overrides and list environment-specific keys in `slot_sticky_setting_names` so they stay with their slot. Both slots use the same port, health path, registry and Application Insights resource. Slot identities do not swap. After a swap, update both desired image values and any non-sticky settings to match the intended production and staging state before the next apply, or OpenTofu will reconcile the swap back to the declared configuration. See `examples/slots.tfvars` for a non-deployable placeholder example.

## Observability

Platform, HTTP, application and console logs and metrics go to the workspace; workspace retention defaults to 30 days. Application Insights receives its connection string as an app setting, but custom containers must include an appropriate SDK or agent to send application telemetry. Production and staging share telemetry, so distinguish them in application instrumentation if needed. The alert fires when the app returns more than 10 HTTP 5xx responses in five minutes; customize the threshold and supply existing `alert_action_group_ids` for notifications. With the default empty list the alert is visible in Azure Monitor but does not notify anyone. It is not a complete availability or latency monitoring strategy.
