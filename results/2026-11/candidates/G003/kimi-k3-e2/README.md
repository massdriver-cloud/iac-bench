# Standard App Service module

One standard module for deploying the SRE team's containerized HTTP APIs onto
Azure App Service. Deploy once per service; tune capacity, availability,
health, rollouts and observability through variables — not App Service
internals.

## Usage

```hcl
service_name        = "payments-api"
resource_group_name = "rg-payments-api"
location            = "westeurope"
container_image     = "payments-api:1.4.2"

# Optional: pull from ACR with a managed identity (no stored credentials)
container_registry_url = "https://myregistry.azurecr.io"
container_registry_id  = "/subscriptions/.../resourceGroups/.../providers/Microsoft.ContainerRegistry/registries/myregistry"
```

See `minimal.tfvars` for the smallest valid instantiation.

## What you get, and the decisions already made

### Capacity
- Linux App Service plan, Premium v3 (`P1v3`) with 3 baseline workers.
- CPU-based autoscaling enabled by default: scale out one instance when the
  10-minute average CPU exceeds 70%, scale in below 30%, floor of 2 (keeps
  zone redundancy), ceiling of 10. Tune via the `autoscaling` object or set
  `autoscaling = { enabled = false }` for fixed capacity. `worker_count` is
  the resting/default capacity; autoscaling governs runtime capacity.

### Availability
- Zone balancing enabled by default (requires a zone-supporting region and
  ≥2 instances).
- HTTPS-only, TLS 1.2 minimum, FTP disabled, HTTP/2.
- ARR affinity off — these are stateless APIs; don't pin clients to workers.
- `always_on` so no instance cold-starts under load.

### Health
- Load-balancer health check on `health_check_path` (`/health` by default);
  instances that fail leave rotation and are **replaced** after
  `health_check_eviction_time_in_min` (default 10) — this is the Linux
  self-healing story: a wedged worker is swapped for a fresh one automatically.
- Ship a real health endpoint in the container; every safety mechanism in the
  module (eviction, swap warmup) keys off it.

### Rollouts
- A `staging` deployment slot is created by default for blue-green releases:
  deploy the new image to staging, swap when ready (swaps are performed by
  your pipeline / the portal, not by this module).
- Swap warmup is preconfigured: `WEBSITE_SWAP_WARMUP_PING_PATH` points at the
  health check, so a cold slot never takes production traffic.
- Registry access uses a system-assigned managed identity with an `AcrPull`
  grant (app and slot each get one) when `container_registry_id` is set — no
  stored registry passwords anywhere.

### Observability
- Workspace-based Application Insights per service; the connection string is
  injected as `APPLICATIONINSIGHTS_CONNECTION_STRING` so instrumented apps
  light up with zero code changes. Sampling (default 100%) and a daily data
  cap (default 50 GB) are the cost guardrails.
- A dedicated Log Analytics workspace per service (30-day retention), or pass
  `log_analytics_workspace_id` to centralize.
- Diagnostic settings stream `allLogs` + `AllMetrics` from both the app and
  the staging slot into that workspace; file-system HTTP logs, failed-request
  tracing and detailed errors are also on for on-box debugging.

## Notes
- Names are derived from `service_name`; `app-<service_name>` must be
  globally unique in Azure.
- The module creates the resource group by default so it is self-contained;
  set `create_resource_group = false` to deploy into a shared existing group.
- To release a new version: update `container_image` and apply, or push the
  image to the staging slot from CI and swap.
