# Standard App Service module

Deploys one containerised HTTP service on Azure App Service (Linux, Premium v3)
with the SRE team's standards built in. Authored as a root module:

```sh
tofu init
tofu plan  -var-file=minimal.tfvars
tofu apply -var-file=minimal.tfvars
```

`minimal.tfvars` is the smallest valid input (name, environment, region, image).
`examples/production.tfvars` shows a fuller, production-shaped input (its
resource IDs are placeholders).

## What you get

| Concern | What the module does | Knob |
|---|---|---|
| Capacity | Premium v3 plan; autoscale on plan CPU and memory between `min_instances` and `max_instances`. The autoscale setting owns the instance count (also when fixed, min == max), so applies never undo a scale-out. | `capacity` |
| Availability | Zone-redundant plan with at least 2 instances by default; always-on. | `capacity.zone_redundant` |
| Health | Platform health check on `/healthz`; failing instances leave rotation after 5 minutes and are replaced. The same path gates slot swaps. | `health_check_path`, `health_check_eviction_minutes` |
| Rollouts | A `staging` slot. New images land in staging; a slot swap promotes them with warm-up and no downtime; swapping back is the rollback. | `image`, output `rollout` |
| Observability | Log Analytics workspace (or bring your own), HTTP/console/app/platform/audit logs from both slots, workspace-based Application Insights with the connection string injected, and five metric alerts (5xx, health, latency, plan CPU, plan memory). | `log_analytics_workspace_id`, `application_insights_enabled`, `alerts` |
| Network | **Private by default**: the public endpoint is off. Choose `restricted` (default-deny + allow-lists / Front Door) or `public` explicitly. Optional private endpoints (app + staging) and outbound VNet integration. | `ingress`, `vnet_integration_subnet_id` |
| Identity & secrets | One user-assigned identity for both slots. ACR pulls use it (no admin credentials). Secrets are Key Vault references resolved at runtime; values never enter state. | `container_registry_id`, `key_vault_secrets`, `key_vault_ids` |
| Hardening (fixed) | HTTPS only, TLS 1.2+, FTP/FTPS off, basic-auth publishing off, remote debugging off, Kudu follows the app's access rules, session affinity off. | none |

## Rolling out a new version

1. Change `image.tag` and apply. **Only the staging slot is updated**;
   production keeps serving the current release.
2. Verify the release on the `staging_url` output.
3. Promote with the command in the `rollout` output
   (`az webapp deployment slot swap ...`). App Service warms every instance up
   against the health check path before switching traffic.
4. To roll back, run the same swap again: staging holds the previous release
   until the next apply.

Consequences worth knowing:

- Production's image is deliberately ignored after the first apply, so a plan
  never shows a production image change. After a swap, the next plan shows the
  staging slot drifting back to `image` - that is expected and harmless.
- App settings and secrets are **not** staged: changing `app_settings` or
  `key_vault_secrets` applies to production directly and restarts it.

## Things to decide per service

- `ingress.mode` - with the default (`private`) and no
  `private_endpoint_subnet_id`, the app is unreachable until a private endpoint
  is attached. That is the intended safe starting point, not an oversight.
- `alerts.action_group_ids` - empty by default: alerts fire in Azure Monitor
  but notify nobody until you pass your on-call action group.
- `health_check_path` - the service must answer 2xx on `/healthz` or you must
  point this at its real health endpoint.
- `capacity` - the default (2-6 x P1v3, zone redundant) is sized for a
  production API. For dev, e.g.
  `capacity = { sku = "P0v3", min_instances = 1, max_instances = 1, zone_redundant = false }`.

## Not included

Custom domains and certificates, a WAF / Front Door / API gateway in front of
the app, private registries other than ACR that need credentials, and the
virtual network, private DNS zones, Key Vaults and action groups the module can
plug into - those are expected to exist already.
