# Standard App Service module for containerized HTTP APIs

A standalone OpenTofu root module that gives each service a secure, observable Azure App Service deployment without requiring product teams to tune App Service internals. It uses only native `azurerm` resources and has no remote module dependencies.

## Production baseline

| Area | Default decision |
| --- | --- |
| Runtime | Linux Web App running a custom OCI container; HTTP/2, HTTPS-only, TLS 1.2+, no client affinity |
| Capacity | Premium `P1v3`, three initial workers, availability-zone balancing |
| Autoscaling | Add one worker above 70% average CPU for 10 minutes; remove one below 30%; 3-10 workers by default |
| Health | App Service health checks on `/health`; unhealthy instances are replaced after the configured eviction interval |
| Rollouts | A `staging` slot with the same configuration, ready for candidate deployment, smoke tests and slot swap |
| Identity | System-assigned identity on each slot; optional additional user-assigned identities; optional managed-identity ACR pull and `AcrPull` assignments |
| Network | Optional regional VNet integration and a production private endpoint; choosing a private endpoint disables public ingress unless explicitly overridden |
| Security | FTP and Web Deploy basic authentication disabled, FTPS disabled, remote debugging disabled, SCM inherits app access restrictions |
| Logs and traces | Workspace-backed Application Insights plus App Service HTTP, console, application, audit and platform logs in Log Analytics |
| Alerts | HTTP 5xx, failed App Service health checks, sustained plan CPU, and external availability for publicly reachable apps |

The defaults favor a highly available production service. All capacity, rollout, registry, network and monitoring decisions are exposed as variables where an SRE needs to override them.

## Minimal use

The module expects an **existing resource group**. The app name must be globally unique within App Service, and the selected region/SKU must support availability zones when `zone_redundant = true`.

```console
tofu init
tofu plan -var-file=minimal.tfvars
tofu apply -var-file=minimal.tfvars
```

Only four inputs have no default:

- `name`
- `resource_group_name`
- `location`
- `container_image`

`minimal.tfvars` supplies those inputs and overrides the sample image's port and health path. It uses the public `mcr.microsoft.com/dotnet/samples:aspnetapp` image, so registry credentials are not required.

## Container contract

Every service must:

1. Listen on `container_port` (default `8080`). The module sets `WEBSITES_PORT` accordingly.
2. Serve an unauthenticated `GET health_check_path` endpoint that returns **HTTP 200**. The default is `/health`.
3. Keep the health check fast and local to the process. Do not make it depend on a database or another API; downstream failures should not cause every healthy web worker to be replaced.
4. Write application logs to stdout/stderr so they appear in `AppServiceConsoleLogs`.
5. Use an immutable tag or digest in production. The application is expected to start within `container_start_time_limit` (default 600 seconds).

Additional environment variables go in `app_settings`. Use Key Vault references rather than plaintext secrets and grant the selected identity access to those secrets. Although `app_settings` and the Application Insights outputs are marked sensitive, all normal OpenTofu state-protection requirements still apply.

The module provides `APPLICATIONINSIGHTS_CONNECTION_STRING` and `APPINSIGHTS_INSTRUMENTATIONKEY`. An arbitrary custom container is **not automatically instrumented**: install and configure the Application Insights SDK or an OpenTelemetry exporter in the application to emit traces, requests and dependencies.

## Safe rollout workflow

With the default staging slot, OpenTofu manages the production image while the deployment pipeline manages the candidate image on staging. The staging image is ignored by OpenTofu after slot creation so a later infrastructure apply does not roll back a candidate.

A typical pipeline, using Microsoft Entra authentication rather than publishing profiles, is:

```console
# 1. Deploy the immutable candidate image to staging.
az webapp config container set \
  --name "$APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --slot staging \
  --image "$CANDIDATE_IMAGE"

# 2. Run smoke tests against the slot hostname from the module output.
curl --fail "https://$SLOT_HOSTNAME/health"

# 3. Promote after smoke tests and any required approval.
az webapp deployment slot swap \
  --name "$APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --slot staging \
  --target-slot production
```

After promotion, set `container_image` to the promoted tag/digest and apply OpenTofu so its production desired state matches the running release. Keep slot-specific environment values in `sticky_app_setting_names`; otherwise app settings travel with the image during a swap. Changes to shared module configuration still affect both slots.

Setting `deployment_slot_enabled = false` removes this safety mechanism and makes image changes direct production deployments.

## Azure Container Registry without passwords

For the default system-assigned identities:

```hcl
container_image                       = "myregistry.azurecr.io/orders@sha256:..."
container_registry_url                = "https://myregistry.azurecr.io"
container_registry_use_managed_identity = true
container_registry_id                 = "/subscriptions/.../resourceGroups/.../providers/Microsoft.ContainerRegistry/registries/myregistry"
```

The module grants `AcrPull` separately to the production and staging system identities. The identity running OpenTofu must therefore be allowed to create role assignments at the registry scope; otherwise, leave `container_registry_id` null and manage the grants elsewhere.

To use a shared user-assigned registry identity instead, attach its resource ID through `user_assigned_identity_ids` and set all of:

- `container_registry_managed_identity_client_id`
- `container_registry_managed_identity_principal_id`
- `container_registry_use_managed_identity = true`
- `container_registry_id` when the module should create the role assignment

Username/password authentication is supported for non-ACR registries but managed identity is preferred. Credentials and managed-identity pull are deliberately mutually exclusive.

## Private ingress and outbound networking

Set `private_endpoint_subnet_id` to create a `sites` private endpoint for production. Optionally supply the `privatelink.azurewebsites.net` zone in `private_dns_zone_ids` for automatic DNS registration. Unless `public_network_access_enabled` is explicitly set, this also disables public ingress.

Set `vnet_integration_subnet_id` to a subnet delegated to `Microsoft.Web/serverFarms` for outbound VNet integration. `vnet_route_all_enabled` defaults to true. Set `vnet_image_pull_enabled = true` when the registry is reachable only through that network.

The module does not create resource groups, VNets, subnets or DNS zones; these remain shared network-governance resources. The private endpoint covers production. Secure staging separately with access restrictions or disable slots when candidates must not have a separate network path.

The external availability test is automatically omitted when public access is disabled. Use an internal probe for a private-only service. Also set `availability_test_enabled = false` when IP restrictions intentionally block Microsoft's public test locations.

For an IP allow-list, set `ip_restriction_default_action = "Deny"` and provide `ip_restrictions`. Each rule must use exactly one source: CIDR, service tag or subnet. SCM inherits the same restrictions.

## Monitoring and notifications

The module creates a Log Analytics workspace unless `log_analytics_workspace_id` points to an existing one. Diagnostic settings cover production, staging and plan metrics. Four alert rules are enabled by default:

- total HTTP 5xx responses above `http_5xx_alert_threshold` over five minutes;
- average App Service `HealthCheckStatus` below 1 over five minutes;
- average plan CPU above `cpu_alert_threshold` for fifteen minutes;
- public external availability below `availability_alert_threshold`, using two standard-test locations every five minutes.

Alerts are not pages until an action group is attached. Set either `action_group_id` or `alert_email_receivers`. An existing action group is recommended when the SRE team already has escalation policies. Autoscale notifications have their own optional `autoscale_notification_emails` list.

Tune alert thresholds per service rather than treating the defaults as SLOs. Application Insights sampling defaults to 100%; reduce it for high-volume services only after considering trace completeness.

## Capacity notes

- Zone-redundant plans require at least three workers, including `autoscale_min_capacity`.
- The explicit Azure Monitor autoscale profile owns worker count while autoscaling is enabled. OpenTofu ignores autoscale-driven `worker_count` drift; `autoscale_default_capacity` is the initial/fallback capacity, not a desired fixed count.
- With `autoscale_enabled = false`, `instance_count` controls fixed capacity.
- Select a SKU/region combination that supports every enabled feature. Switching between manual and autoscaled modes replaces the plan resource, so plan that change carefully.
- Health checks and slot swaps complement, but do not replace, application readiness logic, database migration discipline and rollback testing.

## Important outputs

Use `production_url`, `deployment_slot_default_hostname`, `production_identity_principal_id`, `service_plan_id`, `application_insights_connection_string`, `log_analytics_workspace_id` and `private_endpoint_ip_address` to integrate pipelines, IAM, dashboards and network configuration. Current and possible outbound IP lists are also exported for downstream firewalls; VNet integration with a NAT gateway is preferable when a stable egress address is required.
