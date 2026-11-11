# Standard App Service module

One OpenTofu root module that deploys one containerized HTTP service on Azure
App Service (Linux), with the SRE team's standards built in. One instantiation
(one state) per service and environment.

```sh
tofu init
tofu plan  -var-file=minimal.tfvars
tofu apply -var-file=minimal.tfvars
```

`minimal.tfvars` is the smallest valid input (5 values). `examples/full.tfvars`
shows a production service using most options (its IDs are placeholders).

## What you get

| Concern | What the module does | What you can set |
|---|---|---|
| **Capacity** | Dedicated Linux Premium v3 plan. An autoscale setting owns the instance count: it keeps the plan between min and max and adds/removes one instance on plan CPU (out: >70 % for 5 min, in: <35 % for 10 min). | `sku_name` (P1v3), `min_instances` (2), `max_instances` (4), `scale_out_cpu_percent`, `scale_in_cpu_percent` |
| **Availability** | Instances are spread across availability zones; at least 2 instances are enforced when zone-redundant. | `zone_redundant` (true) |
| **Health** | Platform health check probes every instance each minute; failing instances leave the load balancer and are replaced. Always On is enabled. | `health_check_path` (required), `health_check_eviction_minutes` (5) |
| **Rollouts** | A `staging` slot with the same hardening as production. Deploy a release candidate there, verify, swap with zero downtime; the swap warms up on the health path first. `latest` tags are rejected. | `image`, `staging_image`, `staging_app_settings`, `staging_slot_enabled` (true) |
| **Observability** | HTTP, container console, platform and audit logs to Log Analytics; workspace-based Application Insights with the connection string injected into the container; alerts for 5xx, latency, failed health checks, plan CPU and memory. | `log_analytics_workspace_id`, `log_retention_days`, `alerts_enabled`, `alert_action_group_ids`, `alert_email_addresses`, `alert_thresholds` |
| **Security** | HTTPS only, TLS 1.2+, FTP and basic-auth publishing disabled, no registry passwords. One user-assigned identity per service pulls from ACR and resolves Key Vault references. | `container_registry_id`, `key_vault_secrets`, `key_vault_ids` |
| **Networking** | Public endpoint by default; becomes deny-by-default as soon as an allow-list is given. Optional Front Door pinning, VNet integration and private endpoints (production and staging). | `allowed_ip_ranges`, `allowed_service_tags`, `front_door_id`, `public_network_access_enabled`, `integration_subnet_id`, `private_endpoint_subnet_id`, `private_dns_zone_ids` |

Not tunable on purpose: TLS version, FTPS, HTTP/2, Always On, basic-auth
publishing, log categories, OS, and plan tier family.

## Rolling out a new version

1. Set `staging_image` to the release candidate and apply. Production is untouched.
2. Verify on the `staging_url` output.
3. Promote with the command in the `swap_command` output
   (`az webapp deployment slot swap ...`). The platform warms the new version
   on `health_check_path` before switching traffic.
4. Record the result: set `image` to the promoted reference and `staging_image`
   back to `null`, then apply. Production shows no change; staging catches up.

Do step 4 right after the swap. Applying with the old values would put the
previous image back on production.

Roll back by swapping again (the previous version is still warm on staging
until step 4), or by setting `image` back to the previous tag.

Changing `image` directly also works, but restarts production in place.

## Things to know

- **Instance count** is owned by autoscale after the first apply; changes to
  `min_instances` / `max_instances` are applied through the autoscale setting.
- **Secrets** never go in `app_settings`. Put the Key Vault secret URI in
  `key_vault_secrets`; the vault must use the RBAC permission model if the
  module is to grant access (`key_vault_ids`).
- **Role assignments** (`container_registry_id`, `key_vault_ids`) need the
  deploying principal to hold Owner or User Access Administrator on those
  scopes. Otherwise leave them unset and grant `identity_principal_id` access
  out of band.
- **Private registries other than ACR** are not supported; public images are
  pulled anonymously.
- **Alerts without a receiver** still evaluate and show in Azure Monitor, but
  notify nobody. Set `alert_action_group_ids` or `alert_email_addresses`.
- **Regions**: the default `zone_redundant = true` needs a region with
  availability zones for App Service.
- **Destroy**: the provider is configured to delete the service's resource
  group even if Azure has placed unmanaged helper resources in it. When
  deploying into a shared group (`resource_group_name`), the group itself is
  never managed or deleted.
- **Custom domains and certificates** are out of scope; front the service with
  Front Door or Application Gateway and use `front_door_id` / allow-lists.
