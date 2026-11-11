# Standard container App Service

Standalone OpenTofu root: provisions its own resource group, Linux Premium v3 plan,
production app, optional warm staging slot, shared workload identity, CPU autoscale,
Log Analytics and workspace-backed Application Insights. No remote modules.

## Run

Authenticate with Azure using the normal AzureRM environment variables (including
`ARM_SUBSCRIPTION_ID`) or Azure CLI plus a subscription ID. The deploying principal
needs resource creation permissions and, when using ACR, role-assignment permissions.

```
tofu init
tofu plan -var-file=minimal.tfvars
tofu apply -var-file=minimal.tfvars
```

Change the example globally unique name before deploying. The minimal example uses
a public demo image with `/` as readiness endpoint; it is not a production workload.
The checked-in example is intentionally not pinned; pin production images by digest.
Use encrypted, access-controlled remote state and state locking in your deployment
environment. This module intentionally does not configure a backend.

## Operational contract and defaults

- Dedicated P1v3 plan, two workers minimum, four maximum. Scale out by one after
  five minutes above 70% CPU; scale in by one after fifteen minutes below 30%.
  Autoscale owns worker count after creation; adjust `capacity` to change bounds.
  Staging shares workers: budget capacity for both versions during rollouts.
- Always On, HTTPS only, TLS >=1.2, HTTP/2, no FTP or basic publishing credentials.
  Containers must listen on `0.0.0.0` at `container_port`, be stateless, and write
  logs to stdout/stderr. Persistent App Service container storage is disabled.
- Readiness must return 200-299 without authentication or redirects. App Service
  uses its native health checking and five-minute unhealthy-worker eviction.
  Health checks alone cannot guarantee availability; the application must handle
  graceful shutdown, dependency outages and retries.
- Zone redundancy is opt-in because regional support/capacity varies. Enable with
  at least three baseline workers in a supported region. Multiple workers without
  zones protect against worker failure, not a zone/region outage. No cross-region
  disaster recovery or backup of application data is provided.
- Public ingress by default. `allowed_ipv4_cidrs` applies a deny-by-default allowlist
  to production, staging and SCM when nonempty. Include operator/CI addresses.
  Staging is otherwise public too; do not expose sensitive candidate functionality
  without application authentication or an allowlist. Private endpoints, custom
  domains, VNet integration, fixed outbound NAT, WAF, and end-user authentication
  belong to a separate networking/edge/application design, not this baseline.
- Public registries require no credentials. For private ACR set both
  `acr_resource_id` and `registry_url`; the shared user-assigned identity receives
  AcrPull and both slots use it. Allow time for RBAC propagation before expecting
  the first image pull. ACR must allow network access from the app and use RBAC
  registry permissions (ABAC repository-scoped registries require different roles).
- Key Vault references can be supplied in `app_settings`; grant the output identity
  access to the relevant vault secrets separately. The same identity is deliberately
  shared across slots, so slots are not a security boundary. Never put raw secrets
  in tfvars: settings and sensitive inputs still persist in state. Platform settings
  (`WEBSITES_PORT`, storage, Insights connection) override caller settings.
- All available platform log categories and metrics flow to Log Analytics (30 days
  by default). HTTP logs are also retained locally for three days with a small size
  cap. Instrument the container with an Application Insights/OpenTelemetry SDK using
  the supplied `APPLICATIONINSIGHTS_CONNECTION_STRING`; setting it alone does not
  automatically instrument arbitrary containers. Container log collection depends
  on the runtime emitting supported logs. Collection and retention incur costs.
- Set `alert_email_addresses` to activate production health and 5xx alerts. Without
  recipients, no action group or alert rules are created. Alerts use fixed baseline
  thresholds; tune for service traffic and supplement with external availability
  probes/SLO monitoring. Lack of metric data is not itself an outage alert.

## Release and rollback

1. Keep `container_image` at the current production digest; set `staging_image` to
   the candidate digest and apply. Both images must use the configured registry.
2. Verify the staging URL, health endpoint, dependencies, telemetry and load behavior.
   Schema changes must remain backward-compatible across both versions.
3. Explicitly swap via Azure CLI (never implicitly on `tofu apply`):
   `az webapp deployment slot swap -g <resource_group_name> -n <name> --slot staging --target-slot production`.
4. Immediately reconcile configuration: set `container_image` to the new production
   digest and `staging_image` to the old production digest. Review a fresh plan;
   otherwise a later apply will undo the swap. Do not run concurrent applies/swaps.
5. To roll back, swap back and reconcile the image inputs again. Rollback does not
   undo database migrations. Deleting/disabling staging discards that rollback copy.

Both slots have the same settings and no auto-swap. Container image configuration
is intentionally managed (not ignored) so drift is visible. Use independent root
instances and state for environments needing separate security or capacity.
