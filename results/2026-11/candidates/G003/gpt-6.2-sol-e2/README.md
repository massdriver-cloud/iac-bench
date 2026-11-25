# Standard Azure App Service for containerized HTTP APIs

Use one copy and one OpenTofu state per service. The root creates a resource group, a dedicated Linux App Service plan, the production web app, and (by default) a `staging` slot on the same plan. It does not push images or promote releases. Production uses the Azure-provided HTTPS hostname and is publicly reachable; the application or an upstream gateway is responsible for API authentication. Private ingress, VNet integration, and custom DNS/TLS are outside this root's scope.

## Deploy

1. Supply AzureRM credentials and `ARM_SUBSCRIPTION_ID` via the environment. The deployment identity needs permission to provision the resource group and its resources, and, if using ACR, to create a role assignment on the registry. Ensure the relevant Azure resource providers are registered or that the deployment identity can register them.
2. Copy `minimal.tfvars` for the service. Set a globally unique `name`, a region with available Premium v3 quota, and the registry/repository for the bootstrap image. The included public demo uses port 80 and `/`; the module defaults are `8080` and `/healthz`.
3. Use a separate, access-controlled remote backend for each production state (the standalone example uses local state unless you configure a backend).

```sh
tofu init
tofu validate
tofu plan -var-file=minimal.tfvars -out=service.tfplan
tofu apply service.tfplan
curl --fail "$(tofu output -raw production_url)/"  # demo image readiness path
```

The service must listen on `0.0.0.0` on `container_port`. Use a small unauthenticated `health_check_path` that returns HTTP 200, without redirects, only when the worker can serve traffic. Azure uses it for worker health and for startup and swap warmup. Otherwise-healthy workers remain in rotation when individual workers fail health checks. App Service storage is disabled: do not rely on the container filesystem for durable state. HTTPS is enforced, TLS versions below 1.2 are disabled, SCM ingress is denied, and FTP and publishing basic authentication are disabled.

For a private image in a **network-reachable ACR**, set `acr_id` and set `image.registry_url` to the matching ACR login server. The module grants registry-scoped `AcrPull` to a dedicated pull identity shared by the slots; the registry must support registry-wide RBAC. Role assignments can take time to propagate, so check container startup and retry/restart after propagation if the first pull is denied. Each slot has its own system-assigned runtime identity; use `runtime_principal_ids` to grant downstream access. Do not put secret values in tfvars; grant those identities access and pass Key Vault reference strings in `app_settings` or `environment_settings`.

## Capacity and availability

- Default capacity is two P1v3 workers, scaling from two to five. Azure Monitor adds a worker above 70% average plan CPU over five minutes and removes one below 35% over fifteen minutes, with five- and ten-minute cooldowns respectively. Set `capacity.minimum`, `.default`, and `.maximum` to the same count for fixed capacity. Adjust the bounds in OpenTofu, not the live plan count.
- Enable `zone_redundant` for production where the chosen region, SKU, and App Service stamp support it. It is opt-in for portability and requires at least two workers. This is a single-region deployment, not regional failover.
- Staging and production share the workers and therefore the CPU metric and resource budget. Leave headroom for both containers and for startup and swap; choose `sku_name` for per-worker sizing and set the minimum for load that cannot wait for scale-out. Even the demo creates billable Premium workers and monitoring resources.

## Release and rollback

OpenTofu owns the plan, the slot topology, the registry location and auth settings, and shared/platform configuration. `image.repository` seeds the image when an app or slot is created; normal OpenTofu applies intentionally do **not** overwrite the running image after a release or swap. Keep the bootstrap image usable for rebuilds, and have the pipeline track/redeploy the intended digest after a replacement. Treat registry migrations as coordinated infrastructure and release changes, not as routine releases.

1. Give the release runner Azure management-plane permission to update the image and swap slots. Put its fixed public egress IPv4 ranges in `staging_allowed_cidrs` for HTTPS smoke tests. By default all external staging traffic is denied. SCM is not needed for these operations.
2. Push an immutable image version to the configured registry. Deploy the fully qualified image to the `staging` slot. For example, with `IMAGE` set to the full image reference including its digest:

   ```sh
   RG=$(tofu output -raw resource_group_name)
   APP=$(tofu output -raw app_name)
   az webapp config set -g "$RG" -n "$APP" --slot staging --linux-fx-version "DOCKER|$IMAGE"
   ```

3. Check readiness and run smoke tests on `staging_url`. Swap staging into production, then check `production_url`, health, and errors:

   ```sh
   az webapp deployment slot swap -g "$RG" -n "$APP" --slot staging --target-slot production
   ```

4. If necessary, swap again before updating staging; it holds the former production image. After another staging deployment, redeploy the recorded stable digest to staging and repeat validation and swap. Schema/data changes must be backward-compatible independently of this process. Serialize releases and infrastructure applies for the same service.

Use `environment_settings` for settings that must stay with their environment, e.g. `API_BASE_URL = { production = "https://api.example.com", staging = "https://api-stage.example.com" }`. The runtime identities stay with their slots, but Azure can temporarily apply target settings to staging for swap warmup. Ensure the readiness path and permissions work in that phase without granting unnecessary access or causing side effects. If `enable_staging_slot = false`, deploy the image directly to production via the management plane and roll back by redeploying the previous digest; there is no staged warmup or swap rollback in this mode.

## Observe

- App/slot HTTP, container console, and platform logs are sent to Log Analytics, alongside exported App Service and plan metrics. Log to stdout/stderr and avoid putting credentials or sensitive request data in logs. Workspace default retention is 30 days; individual tables may have different retention policies.
- Each environment gets a separate workspace-backed Application Insights component and a slot-sticky connection string. Instrument the container with a compatible SDK or Azure Monitor OpenTelemetry exporter to send requests, dependency traces, and exceptions. A connection string alone does not instrument the application.
- Production alerts fire on at least ten HTTP 5xx responses in five minutes and on average worker health falling below 100% in five minutes when samples are present. Set `alert_action_group_ids` to wire these alerts to on-call; otherwise they appear in Azure Monitor without notifications. Worker health is not an end-to-end uptime check; use an external synthetic monitor when needed.
