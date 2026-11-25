# SRE App Service module

The standard way to run one of the product teams' containerized HTTP APIs on
Azure App Service. An SRE describes the service in the terms they think in —
capacity, availability, health, rollouts, observability — and this module
translates that into a complete, hardened, alerting, autoscaling App Service
deployment. Nobody tunes App Service internals per app: the platform shape is
decided once, here.

## What you get per service

| Resource | Name | Purpose |
|---|---|---|
| Resource group | `<name>-<env>-rg` | Everything for this service lives in one group |
| App Service plan (Linux, Premium v3) | `<name>-<env>-plan` | Capacity: SKU by size, autoscaling, zone redundancy |
| Web app for containers | `<name>-<env>` | The API itself, HTTPS-only, health-checked |
| `staging` deployment slot | on the web app | Zero-downtime rollouts (blue/green swap) |
| Autoscale setting | `<name>-<env>-autoscale` | Keeps instance count between min and max on CPU load |
| Log Analytics workspace | `<name>-<env>-logs` | HTTP, console, audit, platform logs |
| Application Insights | `<name>-<env>-insights` | Request/dependency/exception telemetry (connection string injected into the container) |
| Diagnostic settings | on app + slot | Piping all log categories and metrics into the workspace |
| Action group + 3 alert rules | `<name>-<env>-alerts`, `-http-5xx`, `-memory-saturated`, `-cpu-saturated` | Pages `alert_emails` |

## The SRE interface

### Identity
- `name` (required) — the service's stable name; becomes its DNS label
  (`<name>-<env>.azurewebsites.net`) and the prefix of every resource.
- `environment` (default `prod`) — dev / stage / prod, in names and tags.
- `location` (required) — use a region with availability zones for the
  standard posture.
- `tags` (optional) — merged with the module's `application`, `environment`,
  `managed_by`, `module` tags.

### Capacity
- `instance_size` — `small` / `medium` / `large` maps to P1v3 / P2v3 / P3v3.
  You pick a size, the module picks the SKU.
- `min_instances` (default 3) — instances always warm. 3 keeps capacity in
  every availability zone of a zone-redundant plan.
- `max_instances` (default 10) — the scale-out ceiling. Set it equal to
  `min_instances` to pin capacity.

### Availability
Premium v3 is used for every service, no exceptions: it is the only family
that gives Linux containers, always-on, deployment slots, autoscaling and
zone redundancy in one plan. On current Azure, Premium v3 plans in
zone-capable regions are zone-redundant by platform default — the module does
not (and cannot) configure that per app, it just keeps a 3-instance floor so
each zone is always serving. Everything is HTTPS-only (HTTP/2, TLS >= 1.2,
FTPS and basic-auth publishing disabled), and traffic is balanced across
instances by least-requests.

### Health
- `health_probe_path` (default `/health`) — polled on every instance;
  instances failing it for 10 minutes are pulled from rotation and replaced.
  The same path is probed on the staging slot, so a candidate build must be
  healthy before you swap it in.

### Rollouts
- `enable_staging_slot` (default true) — a warm `staging` slot, identical to
  production (same settings, health check, identity, registry credentials).
- `staging_auto_swap` (default false) — promote automatically on deploy.
  Default off: promotions are deliberate.

A release looks like: deploy the new image to the slot (your pipeline owns
the slot's image — this module deliberately never reverts it), watch the slot
pass its health checks, then run the `staging_promote_command` output to swap
it into production with zero downtime, and finally update `container_image_tag`
in this module so state matches reality.

### Observability
- `alert_emails` (required) — who gets paged. A standard service is never
  deployed without an on-call.
- `log_retention_days` (default 90) — how long logs stay in the workspace.

Alert rules (all page `alert_emails` via the action group):

| Rule | Signal | Pages when |
|---|---|---|
| http-5xx (sev 1) | `Http5xx` total > 10 in 5 min | The service is failing requests |
| memory-saturated (sev 2) | plan `MemoryPercentage` > 80% for 15 min | Instances are about to OOM: raise `max_instances` or `instance_size` |
| cpu-saturated (sev 3) | plan `CpuPercentage` > 80% for 15 min | Autoscaling can't keep up: raise `max_instances` |

For latency, dashboards and per-request traces, use the injected
`APPLICATIONINSIGHTS_CONNECTION_STRING` plus the workspace — the data is
already flowing.

### The application
- `container_image` + `container_image_tag` (image required, tag defaults to
  `latest` — pin it), `container_port` (default 80) — wired in as
  `WEBSITES_PORT`.
- `container_registry` (optional) — server/username/password for a private
  registry, injected as the `DOCKER_REGISTRY_*` app settings. Omit for public
  images.
- `app_settings` (optional) — environment variables for the container.
  Colliding names override the module-managed settings.
- `virtual_network_subnet_id` (optional) — regional VNet integration for
  reaching private backends (delegate the subnet to `Microsoft.Web/serverFarms`).

## What the module decides for you

These are the platform standards; they are deliberately not variables:

- **SKU family**: Premium v3 only (see Availability).
- **Autoscaling**: +1 instance when average CPU > 70% for 10 minutes (5 min
  cooldown), -1 instance below 30% (10 min cooldown). The plan's worker count
  is ignored after creation so Azure Monitor stays the source of truth.
- **Always-on, least-requests load balancing, HTTP/2, TLS 1.2, FTPS off,
  FTP/WebDeploy basic auth off.**
- **Health check eviction**: 10 minutes.
- **Logs**: application (console) and HTTP logs enabled on app and slot,
  shipped to Log Analytics together with audit/IPSec/platform logs and
  AllMetrics.
- **Alert thresholds and severities** as in the table above.
- **A resource group per service** — deployments are independent, blast
  radius is one group, and `terraform destroy` cleans up completely.
- **System-assigned managed identity** on app and slot (principal id is an
  output; grant it access to whatever the service needs).

## Quick start

```hcl
name              = "checkout-api"
location          = "westeurope"
container_image   = "myacr.azurecr.io/team/checkout-api"
container_image_tag = "1.4.2"
alert_emails      = ["sre-oncall@example.com"]
```

`minimal.tfvars` in this repository is the smallest valid instantiation (a
public nginx container). Plan it with:

```
tofu init && tofu plan -var-file=minimal.tfvars
```
