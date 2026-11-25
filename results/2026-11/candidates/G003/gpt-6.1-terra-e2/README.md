# Linux container App Service

This root configuration creates a **new, dedicated resource group**, Linux App Service plan and web app, Log Analytics workspace, workspace-based Application Insights, diagnostics, CPU autoscaling and a production 5xx alert. Destruction removes the resource group and its contents. Select a globally unique app name and a resource group name not already in use. It is not intended to adopt an existing resource group. Azure credentials and subscription selection are supplied through the AzureRM provider environment (for example `ARM_SUBSCRIPTION_ID` and Azure CLI or service principal credentials). The subscription must support the selected region, SKU, capacity and resource providers.

```sh
tofu init
tofu plan -var-file=minimal.tfvars
tofu apply -var-file=minimal.tfvars
```

Replace the example name and image for an actual service. The container must listen on `0.0.0.0` at `container_port` (default 8080) and return a successful, unauthenticated response at `health_check_path` (default `/health`). Health checks remove unhealthy instances, not a substitute for external availability monitoring. Avoid checks that fail for brief transient dependency errors. HTTPS is required, TLS 1.2 is the minimum, FTP and basic publishing authentication are disabled. App and optional staging endpoints are publicly reachable; this configuration does not provide authentication, network isolation, a custom domain or WAF. Protect the application and staging endpoint appropriately before serving sensitive traffic.

## Capacity and operations

The default plan is P1v3, initially two instances, autoscaling between two and five. CPU above 70% over five minutes adds one instance; below 30% over ten minutes removes one, with cooldowns. Autoscale manages the live count; change minimum/maximum through the variables, not the plan's worker count. The staging slot shares this capacity and incurs load on production instances. Zone balancing is opt-in, requires at least three instances, a supported SKU and region, and suitable quota; the default two instances do not imply zone redundancy. The chosen SKU must support Linux, always-on, autoscaling and, if enabled, slots.

The production app and staging slot have separate system-assigned identities. For a private Azure Container Registry set `registry_url` to its HTTPS login server and `registry_use_managed_identity = true`. Grant each applicable principal `AcrPull` (or the equivalent repository permission for an ABAC-enabled registry) externally. The first image pull may fail until the identities exist and permissions propagate; restart the app/slot after granting access. The module does not grant permissions or configure network access to the registry or Key Vault. `image` and `staging_image` are repository names with tag or digest, without the registry hostname; use immutable image versions.

Additional settings are supplied via `app_settings`; the module reserves `WEBSITES_PORT` and `APPLICATIONINSIGHTS_CONNECTION_STRING`. Prefer Key Vault references over literal secrets, and grant each identity access separately. Sensitive inputs are still stored in OpenTofu state; secure and restrict access to the state and plans. Both slots receive the same settings; there is no separate staging environment or slot-sticky secret configuration.

## Rollouts

Set `enable_staging_slot = true` and optionally `staging_image` to a candidate in the same registry; otherwise it starts with the production image. Apply, validate the staging URL and manually swap with Azure CLI or the Azure portal. Swaps are not performed by OpenTofu. After a successful swap, update `image` to the promoted image and `staging_image` to the former production image before the next plan/apply, so configuration matches the swapped resources. A swap back can roll back while the previous image remains in the slot; reconcile variables again. Database changes and any application-specific warm-up or readiness checks remain the operator's responsibility.

## Observability

HTTP, container console and application platform logs and metrics are sent to the workspace; `log_retention_days` controls workspace retention (default 30 days). The application must use an Application Insights/OpenTelemetry SDK configured to read `APPLICATIONINSIGHTS_CONNECTION_STRING` to emit application traces and telemetry; injecting the setting does not instrument a container automatically. The Insights resource has its own retention settings. The production alert fires when more than 10 HTTP 5xx responses occur over five minutes. Provide `alert_action_group_ids` to receive notifications; without them the alert exists but does not notify anyone. Adjust monitoring to workload traffic and add external availability/SLO monitoring. Workspace ingestion, monitoring, slots and plan capacity incur Azure charges.
