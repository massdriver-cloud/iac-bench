# Standard Azure App Service for containerized APIs

This is a standalone OpenTofu root module. It creates its own resource group, a Linux App Service plan, a production web app, and (by default) a `staging` deployment slot. It also provisions a Log Analytics workspace and workspace-based Application Insights, and routes App Service logs and metrics to the workspace.

## Operating defaults

- A dedicated `P1v3` Linux plan with two workers provides an always-on, multi-worker baseline. Set `service_plan_sku` and `instance_count` to change capacity; this module does not configure autoscale.
- The app and staging slot run the same configurable container image, use HTTPS-only ingress, TLS 1.2 minimum, HTTP/2, disabled FTP, and App Service health checks.
- The module gives each app a system-assigned managed identity. Grant it only the Azure permissions the service requires.
- Public access is enabled by default. Set `public_network_access_enabled = false` and provide suitable private ingress separately if the service must not be public. `integration_subnet_id` configures outbound VNet integration only; it does not create a private endpoint or subnet.
- Extra application settings are accepted through `app_settings`. Module-owned settings (container port/storage and Application Insights connection string) take precedence.
- For a private registry, set both `container_registry_username` and `container_registry_password`; credentials are held in sensitive app settings. The default public Docker Hub image needs no credentials.

## Required inputs

`resource_group_name`, `location`, and `service_name` have no defaults. `minimal.tfvars` is the smallest example instantiation. Azure credentials and subscription context are supplied through the environment/provider configuration.

A staging hostname is exposed as an output when `create_staging_slot` is enabled. Use your deployment pipeline to deploy and validate a release on that slot, then perform an App Service slot swap as the release step.
