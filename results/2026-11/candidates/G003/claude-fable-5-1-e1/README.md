# App Service standard module (containerized HTTP APIs)

One opinionated module per service. You give it a name, a region and an image;
it gives you a hardened Linux Web App with capacity management, health checks,
optional slot-based rollouts and a full observability stack.

## What gets created

| Area | Resources |
|------|-----------|
| Placement | Resource group (or reuse an existing one) |
| Compute | Linux App Service Plan + Linux Web App (container), system-assigned identity |
| Capacity | Azure Monitor autoscale setting owning instance count (fixed or CPU-driven) |
| Availability | Optional zone redundancy, health-check eviction, `LeastRequests` balancing |
| Rollouts | Optional `staging` slot with sticky settings for swap-based deploys |
| Observability | Log Analytics (or BYO), workspace-based App Insights, diagnostic settings on app/plan/slot |
| Alerting | Action group + metric alerts: HTTP 5xx, response time, health-check status, plan CPU, plan memory |
| Registry | Optional AcrPull role assignment + managed-identity pull when `acr_id` is set |

## Minimal usage

```hcl
name            = "payments-api"
location        = "westeurope"
container_image = "team/payments-api:1.4.2"
```

See `minimal.tfvars`. Everything else has production-oriented defaults
(`P1v3`, 2–4 instances, `/healthz`, alerts on, 30-day log retention).

## Design decisions worth knowing

* **Capacity is owned by autoscale.** `capacity = { min, max }` is the only
  knob. `worker_count` on the plan is ignored after creation so scale events
  never appear as drift. On Basic SKUs there is no autoscale; `min` must equal
  `max`.
* **Image is owned by this module.** Rollouts = bump `container_image`, apply.
  If you swap slots out-of-band, the next apply will converge both slots back
  to `container_image` — treat the variable as the source of truth.
* **Secrets:** put them in `sensitive_app_settings` (ideally as Key Vault
  references; grant the output `principal_id` access to the vault).
* **Hardening defaults:** HTTPS-only, TLS 1.2, FTPS/FTP/WebDeploy disabled,
  no session affinity, optional CIDR allow-list applied to both the app and
  the SCM/Kudu endpoint.
