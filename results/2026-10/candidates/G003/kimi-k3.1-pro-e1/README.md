# SRE standard Azure App Service module

A standalone OpenTofu root module for stateless, containerized HTTP APIs on **Linux Azure App Service**. It creates the app, its capacity and rollout primitives, and the telemetry needed to operate it; it does not call external modules.

Only four inputs are required. `minimal.tfvars` is a deployable example using a public Microsoft Container Registry sample image.

## Opinionated service baseline

| Concern | Default decision |
| --- | --- |
| Compute | Dedicated Linux `P1v3` plan, initially 2 instances |
| Capacity | Autoscale from 2 to 5 instances: +1 above 70% CPU for 10 minutes, -1 below 30% for 15 minutes |
| Availability | Always On, App Service health checks, unhealthy-instance replacement after 5 minutes, least-request load balancing |
| Rollouts | A warm `staging` slot with the same health and telemetry configuration; swaps are an explicit deployment action |
| Container runtime | `WEBSITES_PORT`, a 600-second startup allowance, no App Service persistent storage, image entrypoint retained unless overridden |
| Security | HTTPS only, HTTP/2, TLS 1.2+, FTP disabled, FTP/WebDeploy basic authentication disabled, ARR affinity disabled, remote debugging disabled |
| Identity | One user-assigned managed identity shared by production and staging, also used for Key Vault references and optional ACR pull |
| Logs | Workspace-based Application Insights plus App Service HTTP, console, application, and platform logs and all metrics in Log Analytics |
| Alerts | HTTP 5xx, health-check failures, response time, plan CPU, plan memory, and external availability |
| External availability | Application Insights standard test every 5 minutes from two regions, with retry and certificate validation |
| Resource group | Created by default so this root module can apply on its own; set `create_resource_group = false` to use an existing group |

Free and Shared SKUs are deliberately rejected. Basic is permitted only with slots and autoscaling disabled. Zone balancing is opt-in because it depends on regional/SKU support; enabling it enforces at least three initial and minimum instances.

## Quick start

```bash
tofu init
tofu plan -var-file=minimal.tfvars
tofu apply -var-file=minimal.tfvars
```

For a real API, start with:

```hcl
name                = "payments-api-prod-<unique-suffix>"
resource_group_name = "rg-payments-api-prod"
location            = "eastus2"
container_image     = "payments-api@sha256:<immutable-image-digest>"

container_registry_url                 = "https://<registry>.azurecr.io"
container_registry_use_managed_identity = true
container_registry_id                  = "/subscriptions/<id>/resourceGroups/<rg>/providers/Microsoft.ContainerRegistry/registries/<name>"

container_port         = 8080
health_check_path      = "/health"
alert_email_receivers  = ["sre@example.com"]
```

The managed-identity path assigns **AcrPull** on the supplied registry and avoids registry passwords. The caller needs permission to create that role assignment. Username/password registry authentication is also supported, but passwords remain in OpenTofu state even though output is redacted.

Use `tofu output health_url` for the production endpoint and `tofu output staging_slot` for the slot hostname. `tofu output application_insights_connection_string` is sensitive.

## Container and health contract

* `container_image` is the repository and immutable tag/digest, without `DOCKER|` or a URL scheme. Set `container_registry_url` separately.
* The container must listen on `container_port` (default `8080`). The module sets `WEBSITES_PORT`; it does not rewrite the image command unless `container_start_command` is set.
* `health_check_path` must be unauthenticated and return HTTP 200 quickly. App Service uses it to remove unhealthy instances, and the public availability test uses the same URL. It should verify the work required to serve requests, not launch expensive dependencies on every probe.
* Persistent App Service file storage is disabled. Container images should be immutable and application state should live outside the instance.
* Application Insights connection settings are injected into both slots. Console/HTTP/platform telemetry is automatic, but traces, metrics, and dependency correlation from an arbitrary container still require an Application Insights-compatible SDK or agent in that application.

## Slot-based rollout

The module creates and configures the rollout primitive but intentionally does **not** auto-swap on a Terraform apply. Validation and approval belong to deployment automation.

1. Leave `container_image` at the currently running production image. Set `staging_container_image` to the candidate and apply.
2. Verify the staging hostname, health endpoint, logs, and synthetic tests.
3. Promote with an explicit Azure CLI/CI step:

   ```bash
   az webapp deployment slot swap \
     --resource-group <resource-group> \
     --name <app-name> \
     --slot staging \
     --target-slot production
   ```

4. Record the promoted digest in `container_image` and normally set `staging_container_image` to the same digest, then reconcile configuration. Because an external swap changes Azure state, do this before the next routine OpenTofu apply to avoid reverting production to the old image.

Use `staging_app_settings` for candidate-specific configuration and list true slot-specific values in `sticky_app_setting_names` (for example, `ENVIRONMENT`). Module-managed telemetry and container settings deliberately cannot be overridden.

Teams whose CI system owns image deployment can instead keep the OpenTofu image at a known bootstrap version and use the same explicit staging validation/swap process.

## Capacity behavior

The plan's `worker_count` is ignored after creation so OpenTofu does not fight Azure Monitor when autoscaling changes the live instance count. `capacity` is therefore the **creation-time and autoscale-default** count, not a promise to manually reset a live plan on every apply. Its value must be within the configured minimum and maximum. Scale rules add/remove one instance at a time and use different observation windows and cooldowns to reduce flapping.

For a fixed-size Basic deployment, use settings such as:

```hcl
service_plan_sku_name   = "B1"
capacity                = 1
deployment_slot_enabled = false
autoscale_enabled       = false
```

For zone balancing, use a supported region and SKU with `capacity >= 3` and, when autoscaling, `autoscale_minimum_capacity >= 3`.

## Observability and notifications

A Log Analytics workspace is created unless `log_analytics_workspace_id` points to an existing one. Retention defaults to 30 days; ingestion caps and Application Insights sampling can be set explicitly. Diagnostic settings cover both production and staging.

The standard alert rules are:

| Alert | Default condition |
| --- | --- |
| `http_5xx` | More than 10 production 5xx responses in 5 minutes |
| `health_check` | Average production `HealthCheckStatus` below 1 for 5 minutes |
| `response_time` | Average production response time above 10 seconds for 15 minutes |
| `cpu` | Average plan CPU above 85% for 15 minutes |
| `memory` | Average plan memory above 90% for 15 minutes |
| `availability` | External availability below 95% for 15 minutes |

Set `alert_email_receivers` to create an email action group, and/or provide `alert_action_group_ids` for an existing PagerDuty/webhook/ITSM action group. With neither, rules still evaluate and appear in Azure Monitor but have no notification destination. `alerts_enabled = false` mutes the rules without deleting them.

The external health test is created only when the app has unrestricted public inbound access. It is automatically skipped for private-endpoint-only apps and CIDR-restricted apps because Microsoft's public test agents would not be valid probes; use an internal synthetic monitor for those deployments.

## Networking

* `virtual_network_subnet_id` enables regional VNet integration on both slots and routes all outbound application traffic through the subnet. Supply the delegated subnet and any required DNS/NAT/network security rules separately.
* `private_endpoint_subnet_id` creates a production private endpoint for the `sites` subresource. `private_dns_zone_ids` optionally attaches the relevant private DNS zones. Set `public_network_access_enabled = false` for private-only ingress.
* `allowed_source_cidrs` changes the default inbound action to Deny and applies the same allow list to app and SCM endpoints. Leave it empty to allow all sources when public access is enabled.
* Outbound IP outputs are provided for downstream firewalls, but VNet integration plus controlled egress is preferable for a stable network design.

The module does not create VNets, DNS zones, NAT gateways, custom domains, certificates, databases, or application RBAC beyond AcrPull. Those belong to the landing zone or service dependencies. Grant the output identity access to Key Vault or other dependencies separately.

## Required inputs

| Input | Meaning |
| --- | --- |
| `name` | Globally unique app name, 3-45 lowercase alphanumeric/hyphen characters |
| `resource_group_name` | Group to create or reuse |
| `location` | Azure region |
| `container_image` | Production image repository and tag/digest |

All other inputs have defaults; see `variables.tf` for validation and the complete tuning surface. Key outputs include app/plan/workspace IDs, hostnames, the shared identity, staging slot details, outbound IPs, and monitoring resource IDs.

## Destroy and state notes

With the default `create_resource_group = true`, destroying the root module also destroys its resource group. Set it to false for a shared group. Registry credentials, app settings, and Application Insights values can be present in state; use an encrypted remote backend and restricted state access for production.
