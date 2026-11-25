# One HTTP service per root deployment

Use a separate state and a globally unique `name` for each service/environment. This root owns the resource group, Linux Premium v3 plan, public HTTPS app and monitoring resources. Do not put unrelated workloads in its resource group. Configure a protected remote state backend appropriate to your team before deploying.

Authenticate AzureRM through the environment (including `ARM_SUBSCRIPTION_ID`). The deployer needs resource creation rights and, for private ACR pulls, permission to assign roles on the registry. Copy `minimal.tfvars`, change the sample name and image, then run:

```sh
tofu init
tofu plan -var-file=minimal.tfvars -out=release.plan
tofu apply release.plan
tofu output -raw url
```

**Application contract.** Run a stateless Linux HTTP container listening on `0.0.0.0` at `port`. Set `health_path` to a cheap, unauthenticated readiness endpoint returning 200 only when the instance can serve traffic. Use unique release tags and prevent tag overwrites in the registry. For private ACR set both `registry_url` and `acr_id`; network-restricted registries need connectivity not provided by this root. Registry role assignments can take time to propagate. Use Key Vault references in `app_settings` and grant each slot's system identity the required secret access separately. The app and any staging slot are internet-facing: implement application authentication where needed.

**Capacity and availability.** The baseline is two always-on P1v3 workers. Azure Monitor adds one worker above 70% average plan CPU for five minutes and removes one below 30% for fifteen minutes, within `capacity.min` and `capacity.max`. Autoscale owns the live count so a plan won't reset it. For fixed capacity use equal bounds. Multiple workers let health checks remove an unhealthy instance; this alone doesn't guarantee zone isolation. Opt into `capacity.zone_redundant` at creation after checking regional support and quota. Changing zone settings can replace the plan. This is a single-region deployment, not regional disaster recovery.

**Release and rollback.** Changing `image` deploys directly. For a rehearsed rollout, leave `image` at the current release, set `staging_image` to the candidate and apply. Smoke-test `staging_url` including the health endpoint and an actual API request. Staging shares plan resources, app settings and telemetry with production; don't load-test it or run duplicate background jobs without isolation. When ready, swap `staging` into production using App Service's slot swap operation. Verify production health, errors and latency; swap back immediately if needed. Before the next apply, set `image` and `staging_image` to the actual post-swap releases, or OpenTofu will restore the previous desired images. Keeping the previous release warm enables a quick reverse swap. A swap cannot roll back database/schema changes.

**Monitoring and cost.** Diagnostic settings export platform logs and metrics to the service workspace (30-day workspace retention). For application traces and dependencies, instrument the container with an Application Insights-compatible SDK/exporter; a connection string alone does not instrument it. A production alert fires on five or more HTTP 5xx responses in five minutes. Supply `action_group_ids` to page the on-call team; otherwise alerts appear in Monitor without notifications. Budget for the provisioned Premium workers even when idle, plus log ingestion, alerts and retention. `tofu destroy` removes the service and its dedicated monitoring resources, not external action groups or registries.
