# GKE Standard — production cluster module

The platform team's standard module for shared, production GKE Standard
clusters. Every new cluster comes from this module: the team fills in the
per-cluster inputs, the module owns the rest.

## What the module decides for you

- **Regional cluster** — control plane and nodes span the zones of the chosen
  region, so a zone outage doesn't take the cluster down.
- **Network-team integration** — VPC-native cluster on the pre-existing
  subnetwork `<vpc>-gke-<region>`, using its `pods` and `services` secondary
  ranges (names overridable). The network is looked up, never created, and the
  module fails fast at plan time if the expected secondary ranges are missing.
- **Security** — private nodes, shielded VMs with secure boot, Dataplane V2
  (NetworkPolicy enforcement for tenant isolation), Workload Identity
  Federation for GKE (pods reach Pub/Sub / Cloud Storage / Cloud SQL through
  Google service accounts — no exported keys), dedicated least-privilege node
  service account, legacy metadata endpoints off, optional private endpoint /
  authorized networks / Binary Authorization.
- **Operability** — release channel (default `REGULAR`) with a maintenance
  window, auto-repair + auto-upgrade with surge upgrades, system and workload
  logging, Managed Service for Prometheus, NodeLocal DNSCache, per-cluster
  cost metering, optional Pub/Sub upgrade notifications and Google Groups
  RBAC.
- **Node pools as code** — the default pool is removed; pools are declared in
  `var.node_pools` with production defaults (autoscaling, `e2-standard-4`,
  `pd-balanced`, image streaming).

## Usage

```hcl
# prod.tfvars
name                   = "platform-prod"
region                 = "us-east1"
network                = "apps-prod"
master_ipv4_cidr_block = "10.255.16.0/28"   # unique /28 per cluster — ask the network team

labels = { env = "prod" }

node_pools = {
  default = { machine_type = "n2-standard-8", max_count = 10 }
  batch = {
    spot         = true
    machine_type = "e2-standard-4"
    max_count    = 20
    taints       = [{ key = "spot", value = "true", effect = "NO_SCHEDULE" }]
  }
}
```

```sh
tofu plan -var-file=prod.tfvars
```

- `minimal.tfvars` — smallest valid instantiation (staging VPC, one default
  node pool). `project_id` defaults to the provider/environment project.
- `example.tfvars` — a fuller instantiation exercising multiple node pools,
  spot capacity, taints, labels and authorized networks.

## Notes for the platform team

- **Outbound access**: nodes are private by default. Pulling public images or
  reaching the internet from nodes requires Cloud NAT on the subnet (usually
  provided by the network team); Google APIs need Private Google Access.
- **Workload Identity**: grant a Kubernetes service account access to a Google
  service account via `roles/iam.workloadIdentityUser` on
  `<project>.svc.id.goog[<k8s-namespace>/<ksa>]`, annotate the KSA, done.
- **Cluster deletion**: set `deletion_protection = true` once a cluster serves
  production traffic; destroying then requires flipping it back first.
- **Upgrades**: stick to the release channel; pin `kubernetes_version` only
  temporarily. Point `upgrade_notification_topic` at a Pub/Sub topic to get
  notified of upcoming upgrades.

## Inputs

See `variables.tf` — every variable is documented inline. Required (no
default): `name`, `region`, `network`, `master_ipv4_cidr_block`.

## Outputs

Cluster identity and connection material (`endpoint`, `ca_certificate`),
`workload_identity_pool`, `node_service_account_email`, network references,
node pool names. See `outputs.tf`.
