# GKE Standard production root

One state creates one regional GKE Standard cluster in an existing environment VPC. It uses three zones, private nodes and a private-only Kubernetes endpoint, Dataplane V2 (Kubernetes NetworkPolicy support), a separately managed autoscaling node pool, Regular release channel, auto-repair/upgrade with surge, Shielded Nodes, Workload Identity Federation for GKE, Cloud Logging and Monitoring, and managed Prometheus. The node account has only the GKE default node role and same-project Artifact Registry read access; workloads do not inherit application-service permissions from nodes. There is no public Kubernetes API endpoint. GKE resources and monitoring incur charges.

## Prerequisites

- A project with billing and quota enabled, permissions to enable APIs, create GKE resources and service accounts, and grant project IAM roles. The project must already contain `apps-staging` or `apps-prod`, and its regional subnet `<vpc>-gke-<region>` with secondary ranges `pods` and `services`. Those ranges and the primary subnet must have sufficient free addresses for all clusters, nodes, pod allocations and upgrade surge. The three selected zones must exist and have the required capacity.
- Coordinate a unique canonical RFC1918 /28 for each control plane. It must not overlap any subnet, other control plane, or connected network. This module validates its format, not overlap.
- The network team must provide private-node egress, including regional Cloud NAT for the subnet's primary and pod ranges as appropriate, and access to Google APIs (Private Google Access or equivalent), DNS, and required image registries. This root deliberately does not create shared routers/NAT or modify the shared subnet. For private Cloud SQL or other private services, separately establish the appropriate service networking, routes, DNS and firewall rules. GKE-managed firewall rules and control-plane connectivity must not be blocked.
- Operators need a routed path from an `admin_cidrs` source to the control-plane private IP, within the cluster region; global access is disabled. Authorized networks are enforced on the private endpoint. The CIDR allowlist does not provide connectivity or IAM/RBAC authorization. Configure VPN/Interconnect/bastion and firewall rules as needed. Choose actual trusted source CIDRs; the example addresses are placeholders.

## Usage

Copy `minimal.tfvars` to a deployment-specific file and replace every placeholder with values reserved for that environment. Authenticate using application default credentials, configure a secured remote state backend with locking appropriate to your organization, then run:

```sh
tofu init
tofu plan -var-file=cluster.tfvars
tofu apply -var-file=cluster.tfvars
```

For each cluster use a separate state, name, control-plane CIDR and dedicated node service account. From an authorized, connected host with `gke-gcloud-auth-plugin` installed, obtain credentials with `gcloud container clusters get-credentials CLUSTER --region REGION --project PROJECT --internal-ip`. Grant operators appropriate Google IAM and Kubernetes RBAC separately. The endpoint and CA are available as outputs; state can contain sensitive data and must be access-controlled.

## Operating and tenancy

The general pool starts with and maintains at least one node per zone and can scale to four per zone by default. Autoscaling bounds are per zone; reserve quota and address capacity for surge as well. Use multiple replicas, topology spread/anti-affinity, pod disruption budgets, and resource requests for workloads. GKE performs upgrades automatically; plan and monitor for disruptions and configure organization-specific maintenance windows if required. Regularly monitor cluster/node health, capacity, logs and costs, and configure alerting and backup/restore outside this root.

Dataplane V2 enforces policies but does **not** isolate namespaces by default: deploy default-deny and explicit allow NetworkPolicies, namespace-scoped RBAC, quotas, admission controls and appropriate Pod Security policies for product teams. Workload Identity is enabled, but each team must create Kubernetes service accounts and grant narrowly scoped IAM roles to the corresponding workload principals (or explicitly bind Google service accounts) for Pub/Sub, Storage, Cloud SQL and other services. The node account is not an application identity. Workload identity pools are project-wide: the same namespace and Kubernetes service account name in different clusters in this project can represent the same IAM principal; coordinate names or isolate trust domains into separate projects. External image repositories require separate pull permissions.

Cluster deletion protection defaults to true. To intentionally destroy, set `deletion_protection = false`, apply that change, then run destroy. Enabled project APIs are intentionally not disabled on destroy because they may be shared. The VPC, subnet, NAT, application IAM, Kubernetes objects, alerting and backups are not managed here.
