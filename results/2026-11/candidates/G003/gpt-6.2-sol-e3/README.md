# Azure App Service for containerized HTTP APIs

Deploy one root module instance (one state) per service/environment. It owns a resource group, a Linux App Service plan, the production app, a staging slot by default, and Azure Monitor resources. Do not put unrelated resources in the owned resource group. In an SRE deployment, use a remote state backend with locking and restricted access; this module does not provision its own backend.

## First deployment

Authenticate AzureRM from the environment (for example, use workload identity federation and set `ARM_SUBSCRIPTION_ID` for the target subscription). The runner needs permissions for the resources it provisions, and role assignment write permission at the registry scope if using ACR. This module does not register providers: ensure `Microsoft.Web`, `Microsoft.Insights`, and `Microsoft.OperationalInsights` are registered, plus `Microsoft.ManagedIdentity` if using ACR. Check region/SKU capacity, zone support, and subscription quota before applying.

```sh
tofu init
tofu plan -var-file=minimal.tfvars
tofu apply -var-file=minimal.tfvars
```

The sample uses a public nginx image on port 80. Change the globally unique name if it is already taken, and use your own image for a real service. The runner does not need to fetch the image, but App Service must be able to reach the registry and is subject to any registry pull limits. Use pinned, immutable image references for service releases.

## Operating defaults

- **Capacity:** Small, medium, and large map to Premium v3 P1v3, P2v3, and P3v3. The default is two to five workers with zone balancing enabled. Azure Monitor adds one worker above 70% average plan CPU for five minutes, and removes one below 30% for 15 minutes, with five- and ten-minute cooldowns respectively. OpenTofu manages the bounds, not the live worker count. Review sizing against load tests; CPU alone won't detect every bottleneck. Staging shares workers and quota with production, so don't run load tests on it. Zone redundancy is regional, not cross-region disaster recovery.
- **Runtime and health:** Use a single Linux HTTP container listening on all interfaces at `container_port`. Store persistent data outside the app; local container files are disposable. Set `health_check_path` to an unauthenticated readiness endpoint which returns 200 or 204 without redirect once the app can serve. App Service uses it for health checks and startup/swap warmup. Always On is enabled and a worker becomes eligible for removal from load balancing after five consecutive failed health probes, subject to Azure's eviction limits. This is not an external uptime check.
- **Access:** Production exposes the Azure HTTPS hostname publicly. The module does not supply API authentication, a private endpoint, DNS, or an edge gateway. Staging only accepts requests from `staging_allowed_cidrs`; by default it denies external HTTP requests. SCM ingress, FTP, and basic publishing credentials are disabled on both. Deploy by changing the container reference, not by publishing code to SCM.
- **Registry and runtime identity:** Set `acr = { id = "…", login_server = "…" }` for an existing reachable ACR in **RBAC Registry Permissions** mode. The module grants a dedicated user-assigned identity `AcrPull` and uses it on both slots. Azure RBAC propagation can lag creation; verify pulls in platform logs before rollout. This configuration does not configure private registry networking or ABAC repository permissions. Separate system-assigned identities are exposed for runtime dependencies. Use Key Vault references and grant each relevant slot identity access; don't put secrets directly in tfvars or app settings managed by OpenTofu.
- **Observability:** HTTP access logs, container stdout/stderr and App Service platform logs go to Log Analytics for each slot. A dedicated workspace defaults to 30-day retention; set `log_analytics_workspace_id` to use a central workspace. Alerts cover production HTTP 5xx volume (10 in five minutes), sustained failed health checks by instance, and shared plan saturation (>85% average CPU for 15 minutes). Set `alert_action_group_ids` to route these alerts; otherwise they do not notify responders. Logs and alerts can incur charges in addition to Premium v3 workers. Instrument the image separately if you need distributed traces, application-level metrics, or SLO monitoring.

## Rollout and rollback

1. Keep `container_image` on the current production version. Set `staging_image` to the candidate and apply. Leave staging disabled only for services that do not need slot swaps.
2. From an allowed address, check readiness and smoke-test `staging_url`; use Log Analytics to inspect startup errors. Use `staging_app_settings` for environment-specific overrides that should stay with staging. During swap warmup Azure can apply production's slot-specific settings to the staging workers. Verify the source slot can warm up with those settings, including any required dependency access; managed identities do not swap.
3. Swap staging into production using the Azure portal or Azure CLI; this is a deliberate operator action, not a side effect of `tofu apply`. Verify production readiness, smoke tests, and alerts. To roll back before replacing staging, swap back and verify again.
4. Before another OpenTofu apply, record the actual production and staging images in `container_image` and `staging_image` and review the plan. After a successful promotion, production should reference the candidate and staging the previous production image. Serialize swaps and applies: both images are declaratively managed, so an apply against stale inputs can undo a swap.
