# Production GKE Standard cluster

This root module creates one regional GKE Standard cluster in an existing VPC and its regional GKE subnet. It does not create or modify the VPC/subnet. The subnet must be named `<network_name>-gke-<region>` and must already have secondary IP ranges named `pods` and `services`. The cluster is in the same project as that network.

## Security and operations defaults

- Private nodes **and a private-only control-plane endpoint**; master global access is disabled. Connect the administration/deployment runner to the VPC (for example through VPN or a suitable private network path). The supplied master `/28` must be unused and non-overlapping.
- Regional placement, VPC-native IP allocation, a stable (`REGULAR`) release channel, deletion protection, shielded nodes, disabled legacy metadata endpoints, and disabled client-certificate issuance.
- Workload Identity Federation for GKE, Calico network policy, vertical and horizontal pod autoscaling, managed Prometheus, and system/workload logging.
- One separately managed, autoscaling workload node pool. Nodes use a dedicated service account with only Artifact Registry read, logging writer, and monitoring writer/viewer project roles. The node OAuth scope is `cloud-platform`; IAM roles, not that scope, constrain the node identity.
- Node-pool autoscaling counts are **per zone**. With the default minimum of one, a three-zone regional cluster starts with three workload nodes.

The network team must ensure the subnet has Private Google Access or another suitable path for private nodes to reach required Google APIs, and provide the required egress/firewall routing (for example Cloud NAT where needed). Private control-plane access for cluster admins and deployment automation must also be routed from their client network.

Workload Identity is enabled for integration with services such as Pub/Sub, Cloud Storage, and Cloud SQL. This module intentionally does not grant those application permissions to nodes or create application identities. Create/own a Google service account for each workload as appropriate, grant that identity only its required service roles, and bind the Kubernetes service account to it using the GKE Workload Identity principal or the `roles/iam.workloadIdentityUser` binding pattern. See the `workload_identity_pool` output.

`authorized_master_networks` is optional and applies only to the private endpoint. If supplied, its CIDRs are configured as the control-plane allow list; it does not create a public control-plane endpoint. With no entries, access is limited by the private endpoint and the network path to it.

## Inputs

Required variables are `project_id`, `cluster_name`, `region`, `network_name`, and `master_ipv4_cidr_block`. All other variables have secure/operational defaults; see `variables.tf`. `minimal.tfvars` is an example minimum instantiation. Replace its project and network details and choose a non-overlapping control-plane range for a real environment.

The module enables the Compute Engine, Kubernetes Engine, and IAM APIs (without disabling them on destroy). It assumes the caller can enable APIs, create service accounts and project IAM bindings, and create GKE clusters/node pools in the target project. Network firewall rules, routes, DNS, NAT, and private connectivity for administrators are owned outside this module.
