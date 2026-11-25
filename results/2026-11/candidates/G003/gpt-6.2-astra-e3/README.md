# One service, one plan

This root deploys a public, stateless Linux HTTP container. Each service gets its own resource group, Premium v3 plan, workspace and state; a noisy neighbor in another service cannot trigger this plan's scale rules. The default costs at least two P1v3 workers even when idle, plus monitoring charges. This is single-region, not regional disaster recovery.

## Start

Set the AzureRM environment credentials and `ARM_SUBSCRIPTION_ID`. Copy `minimal.tfvars` to `service.tfvars`, choose a globally available app name, region, image and port, then run:

```sh
tofu init
tofu plan -var-file=service.tfvars -out=service.plan
tofu apply service.plan
```

Protect state and plan files; use a separate access-controlled backend per service in production. The provisioning identity needs resource group, App Service and Monitor provisioning permissions. Confirm regional Premium v3 quota. The example image is for smoke testing; pin production releases to immutable tags. Specify the repository relative to `registry_url`. For authenticated ACR use `registry_identity` with a pre-authorized pull identity. The registry must be network reachable. This module does not configure private networking, custom DNS, or API authentication; enforce authorization in the app.

## Runtime and availability

Bind to `0.0.0.0` on `container.port`, keep state outside the container, and implement an inexpensive readiness path returning 200 without authentication or redirects. App Service probes it to remove unhealthy instances; it is also the slot warm-up gate. Logs should go to stdout/stderr. Use Key Vault references in `app_settings` and authorize each slot's system identity separately.

CPU above 70% for 5 minutes adds a worker, and below 30% for 15 minutes removes one. The scale-in cooldown is longer to avoid oscillation. Set `capacity.minimum` for baseline load and `maximum` for cost limits; equal bounds pin capacity. A single worker sacrifices instance redundancy. Set `zone_redundant` in a zone-capable region for zone spread; inspect the plan for replacement before changing this on an existing service.

## Release and recover

Set `candidate_image` and apply to start a staging slot. It shares plan capacity and application settings, so budget for both versions and avoid background jobs with duplicate side effects. Staging has a public URL but receives no production hostname traffic. Test readiness and representative requests against `staging_url` and inspect staging logs. Promote explicitly with an App Service slot swap (source `staging`, target production); the old production version remains in staging for swap-back. Use backward-compatible data migrations. **After a swap, reconcile `container.image` and `candidate_image` with the live slots before the next apply** or OpenTofu will restore the declared versions. Removing `candidate_image` deletes the slot and that quick rollback path.

## On call

The workspace receives HTTP, platform and console logs plus exported metrics from each deployed site/slot with 30-day workspace retention. On elevated server errors, filter by resource ID and time, compare HTTP failures with container output and platform restarts, then check plan CPU and instance count against the scale ceiling. Five HTTP 5xx responses in five minutes raises a production alert; set `alert_action_group_ids` to route it to on-call. Without an action group it is visible in Azure Monitor but does not page anyone.
