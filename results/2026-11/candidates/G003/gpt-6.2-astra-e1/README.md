# One service per root deployment

Run this directory directly with a separate state per service/environment. It owns the resource group and everything in it; keep unrelated resources out. This standard is for stateless **public HTTPS** services, not internal endpoints. The service must handle client authentication. Use protected remote state in production; do not put secret literals in tfvars or app settings. For secrets, use Key Vault references and authorize the system identity of each slot in the vault.

## First deployment

Set your AzureRM credentials and `ARM_SUBSCRIPTION_ID` in the environment. The caller needs resource creation permissions and, for private ACR, role assignment permissions on the registry. Copy `minimal.tfvars` to `service.tfvars`, choose a globally available `app_name`, and replace the sample nginx image. Use a Linux HTTP container bound to `0.0.0.0` on `container_port`. `health_path` must respond promptly with 200 without authentication or redirects. The sample uses `/` because nginx serves a static index there; use a real readiness check for an API.

```sh
tofu init
tofu plan -var-file=service.tfvars -out=release.plan
tofu apply release.plan
tofu output -raw service_url
```

The default registry is public Docker Hub. For network-reachable private ACR, set `registry_url` to the registry HTTPS origin and `acr_id` to its resource ID (classic RBAC registry permissions mode). The shared user-assigned identity lets both slots pull without passwords. Allow for role propagation at first start.

## Capacity and availability

Two always-on P1v3 workers are billed continuously. Set `capacity.workers` for steady-state load and `capacity.sku` for CPU/memory per worker. Capacity is fixed, not autoscaled. Leave headroom for unhealthy workers and for staging, which shares the plan. Health Check uses the readiness path with a five-minute unhealthy threshold. Enable `capacity.zone_redundant` at initial deployment in a supported region for zone resilience; multiple workers alone do not guarantee separate zones. Check regional plan availability and quota before apply and inspect replacement actions before changing plan topology. There is no cross-region failover or persistent container filesystem contract.

## Roll forward or back

Use distinct, immutable release tags. With no `staging_image`, changing `image` rolls production directly. For a gated release:

1. Keep `image` unchanged, set `staging_image` to the candidate tag and apply. Staging has a public URL, the same settings, and a distinct system identity. Ensure its access and backend changes are safe alongside production.
2. Smoke-test `staging_url` and check readiness and logs. A failed test needs no production change.
3. Swap only after approval: `az webapp deployment slot swap -g <resource-group> -n <app-name> --slot staging --target-slot production`. Verify the production path and monitor errors. The old version is now in staging; swap again to roll back if necessary.
4. Before the next plan/apply, record the **actual** production and staging tags in `image` and `staging_image` respectively. Otherwise reconciliation can undo the swap. Setting `staging_image = null` destroys the slot and its immediate rollback copy.

## Operations

HTTP access logs, container console output, platform logs and platform metrics go to the dedicated 30-day Log Analytics workspace. Emit application logs to stdout/stderr. Use Azure Monitor on `app_id` for Health Check Status, response time and HTTP 5xx, and on `plan_id` for CPU and memory pressure. Set `paging_action_group_id` to route the included five-errors-in-five-minutes production alert to your responders. Without it no paging is configured. Workspace ingestion and retention can incur charges. Destroying this deployment removes its monitoring resources as well as the service.
