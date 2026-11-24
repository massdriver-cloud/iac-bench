# Standard Cloud SQL PostgreSQL root module

One root deployment manages one PostgreSQL primary, its databases, IAM database users, and additive connection-role IAM grants. Use separate state per instance and a secured remote state backend in your deployment system. No external modules, VPCs, PSA connections, GKE clusters, or Compute Engine instances are created.

## Standard policy

- Private IP only, on the existing environment VPC. No public IP or authorized networks. Private services access is a prerequisite, not owned here.
- Cloud SQL Auth Proxy / language connector required, with TLS and IAM database authentication enabled. Use automatic IAM authentication; there are no managed passwords, built-in users, or password outputs.
- Enterprise edition, regional HA by default, SSD storage with unlimited automatic growth. HA protects against zonal failures, not region loss.
- Daily backups, 14 retained backups, and seven-day point-in-time recovery. These are regional recovery facilities, not a cross-region DR solution. Test restores periodically; backup retention is not a guarantee of recovery time.
- API-side and OpenTofu-side instance deletion protection by default.
- Explicit maintenance window, stable update track. Major upgrades require an explicit version change and a tested upgrade procedure.

DBAs choose location/network, PostgreSQL major version, tier, HA versus zonal operation, initial disk size, maintenance/backup timing, application database names, identities, labels, and additional PostgreSQL flags. IAM authentication cannot be turned off through the flags input. New disks default to 20 GB; automatic growth can increase costs and disks cannot shrink.

## Use

1. Supply real project, instance, region, network, database names, and identity emails in an environment-specific tfvars file. `minimal.tfvars` is a literal planning example, not an existing deployment target.
2. Enable `sqladmin.googleapis.com` in the service project. The network team must have configured the selected VPC's private services access, sufficient allocated address space, and Shared VPC permissions where applicable. API activation is deliberately left to project provisioning.
3. Authenticate the deployment principal using environment credentials / workload identity. It needs Cloud SQL instance/database/user administration, project IAM policy read/write, and permission to use the existing network (including the host project for Shared VPC). These are deployment permissions, not application permissions.
4. Run:

   ```sh
   tofu init
   tofu plan -var-file=minimal.tfvars
   tofu apply -var-file=environment.tfvars
   ```

The supplied example contains every required input. Region and project IDs must correspond to your real infrastructure before applying. Keep the generated provider lock file under version control.

## Connect from GKE or Compute Engine

Run the Cloud SQL Auth Proxy v2 alongside the application, or use a supported language connector, with private-IP routing and automatic IAM authentication. For example, on a host with network access to the selected VPC:

```sh
cloud-sql-proxy --private-ip --auto-iam-authn PROJECT:REGION:INSTANCE
psql 'host=127.0.0.1 port=5432 dbname=app user=dba@example.com sslmode=disable'
```

The localhost hop above is to the local proxy; the proxy-to-Cloud-SQL hop is encrypted. Bind the proxy to loopback, not a publicly reachable interface. The caller's ADC identity must match an admitted IAM database identity. For GKE use Workload Identity Federation, typically impersonating the admitted Google service account; for Compute Engine use its attached service account. Do not distribute service account keys. Allow the required Google API/connector egress (including TCP 443 and 3307) and private VPC routes. A connector provides authentication and encryption, **not** a network tunnel into the VPC. Engineers need a VPC-connected execution environment or VPN as well.

Human PostgreSQL login names are their full email. Service account PostgreSQL login names omit `.gserviceaccount.com`; use `iam_database_usernames` for the exact names. This module supports individual Google users and service accounts, not IAM groups or direct federated principal database users.

Each admitted identity receives `roles/cloudsql.client` and `roles/cloudsql.instanceUser` in the instance project, plus an instance-local IAM SQL user. These are additive project-level grants, not authoritative policy replacement. They do not grant SQL object privileges. Their project scope means they can authorize connections/login to other instances that separately admit that identity. Do not independently manage the same project/role/member tuple in another state: consolidate shared IAM ownership or import and coordinate it before adopting this root.

DBAs must grant least-privilege database/schema/table access using their established privileged SQL administration process after provisioning. This module does not create an administrator password or grant application users superuser/owner privileges. Arrange that administrative bootstrap before onboarding applications. Retain identity-based access/audit records in your organization's Cloud Logging configuration; IAM login attribution does not by itself provide a complete SQL statement audit trail. Query-level auditing and log retention/export policies require a separately defined audit policy.

## Operations and destructive changes

- `connection_name`, `private_ip_address`, `database_names`, and `iam_database_usernames` are integration outputs. Direct private-IP connections are intentionally blocked by connector enforcement.
- Removing a database name destroys that database; instance deletion protection does **not** protect individual databases or users. Review plans and take a verified backup before such changes.
- Removing an identity deletes its SQL user and the role memberships owned here. SQL-owned objects can prevent user deletion; reassign ownership/revoke privileges first. Coordinate project-scoped role removal with any other instances using that identity.
- To delete an instance: take/export any required final backup, set `deletion_protection = false`, apply that change, then explicitly destroy. There is no automatic final export. Do not rely on instance-local backups surviving deletion.
- Keep the provider's disk-size state after automatic growth; never request a disk shrink. Flag changes and major upgrades can restart the instance. Name/network changes may require replacement or a separate migration; inspect the plan and follow Cloud SQL restrictions.
- Regional HA, backup schedules and protection are defaults/policies, not an SLA. Validate capacity, maintenance impact, restore procedures and failover behavior for each workload.
