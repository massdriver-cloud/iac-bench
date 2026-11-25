# Aurora Global Database operations

Owner: platform on-call plus the service incident commander. Store actual identifiers, access instructions and application routing commands in the service's incident system **before** go-live. Keep this document and the configuration available outside the primary region. Database failover does not fail over EKS, ingress, queues, or other dependencies.

## Go-live gate / quarterly drill

1. Verify both regional clusters have two healthy instances in distinct AZs, the secondary is a member of the global database, and both regions can run the full measured write workload. Confirm regional quotas and capacity; do not depend on scaling up during an outage.
2. Bootstrap SQL roles/grants; test IAM token logins from the real EKS workload identities in each region. Secondary writes should be rejected before promotion. Confirm non-TLS and unauthorized SG/user/role connections are rejected. Test TLS hostname validation, not just encryption.
3. Confirm BOTH SNS subscriptions; inject a test alarm and verify the real paging escalation, including delivery when primary-region monitoring is unavailable. Observe `AWS/RDS` `AuroraGlobalDBRPOLag` in the secondary, dimension `DBClusterIdentifier`. It is milliseconds; 1000 ms is the configured warning. Add an external service transaction probe in the surviving region.
4. Have the incident role ready in both regions, independently of primary-region EKS/STS endpoints: RDS global describe/failover/switchover operations, cluster describe, CloudWatch reads and service deployment/routing permissions. Runtime app roles deliberately cannot perform promotion. Grant the incident role only approved global/cluster resources where AWS supports resource scoping. Test the permissions, not just IAM simulation.
5. Run a planned switchover in staging under production-like load, then switch back. Separately rehearse an **unplanned** managed failover using a disposable environment; a graceful switchover alone does not test data-loss handling. Record from first failed customer write through first successful committed write in the recovery region. Use an independently recorded sequence of acknowledged transaction IDs/timestamps to measure loss; CloudWatch lag is not proof of committed-data preservation.
6. Acceptance: <=5 minutes end-to-end, <=5 seconds of acknowledged writes lost in the drill, fresh IAM connections successful, pools and traffic routing recovered. Stop adoption if these cannot be demonstrated. Rehearse PITR restore and payment reconciliation too. Regularly repeat after major workload, engine or driver changes.

## Planned maintenance / no-loss regional switchover

Freeze infrastructure automation. Check all replication lag and cluster health, quiesce risky migrations, and use **switchover**, not an unplanned failover. With a recent AWS CLI:

```sh
GLOBAL=checkout-prod-global
TARGET_ARN=arn:aws:rds:us-west-2:123456789012:cluster:checkout-prod-secondary
RECOVERY_REGION=us-west-2
aws rds switchover-global-cluster --region "$RECOVERY_REGION" \
  --global-cluster-identifier "$GLOBAL" \
  --target-db-cluster-identifier "$TARGET_ARN"
```

Poll global/cluster status to completion (do not assume command acceptance means ready). Switch application write traffic and reconnect pools as below. Managed switchover synchronizes the target before changing roles, aiming for no data loss. Keep a write interruption budget; test it. When switching back, use the same managed switchover with the *current* secondary ARN.

## Unplanned regional outage — target <=5 minutes

**Do not wait for a restore or for OpenTofu. Do not run `tofu apply`.** Have this staffed/approved procedure preauthorized so a human decision does not consume the recovery budget. The times below are an operational budget, not an AWS guarantee.

1. **0–1 minute: detect/triage.** Use independent application probes, regional AWS health and secondary-side lag/missing-data pages. Rule out a single local instance failure (Aurora handles that automatically). Record outage time, last-known lag, last successful transaction/probe and last replication observation. If the primary remains healthy, prefer managed switchover. Stale telemetry cannot establish an upper bound on loss.
2. **1–2 minutes: authorize and fence.** Incident commander approves potential data loss and chooses the healthy secondary. Stop/fence application writes and traffic to the old region, disable automated jobs/consumers there and freeze deploy/apply automation. Verify the target is healthy and has its expected instances. Do not independently promote/detach both clusters or let an old writer serve customers when it returns. If lag was already high, state explicitly that the five-second target might be exceeded; do not promise otherwise. Escalate immediately rather than hiding the breach.
3. **2–3 minutes: managed failover, from the surviving region.** Fill in actual output values, not the placeholders below:

   ```sh
   GLOBAL=checkout-prod-global
   RECOVERY_REGION=us-west-2
   TARGET_ARN=arn:aws:rds:us-west-2:123456789012:cluster:checkout-prod-secondary
   aws rds failover-global-cluster --region "$RECOVERY_REGION" \
     --global-cluster-identifier "$GLOBAL" \
     --target-db-cluster-identifier "$TARGET_ARN" \
     --allow-data-loss
   ```

   `--allow-data-loss` is intentional and requires incident authorization. Poll `describe-global-clusters` and `describe-db-clusters` until the requested target is the global writer and its cluster/instances are available. The AWS managed operation performs the topology transition. If its control plane is unavailable, escalate to AWS and the disaster-recovery lead; do not repeatedly detach clusters or invent a split-brain recovery. Full regional control-plane failure can break the RTO target.
4. **3–5 minutes: reconnect and route.** Determine the current writer (do not trust static Terraform labels):

   ```sh
   WRITER_ARN=$(aws rds describe-global-clusters --region "$RECOVERY_REGION" \
     --global-cluster-identifier "$GLOBAL" \
     --query 'GlobalClusters[0].GlobalClusterMembers[?IsWriter==`true`].DBClusterArn | [0]' \
     --output text)
   WRITER_REGION=$(printf '%s' "$WRITER_ARN" | cut -d: -f4)
   HOST=$(aws rds describe-db-clusters --region "$WRITER_REGION" \
     --db-cluster-identifier "$WRITER_ARN" \
     --query 'DBClusters[0].Endpoint' --output text)
   # Run as the approved application identity from the local recovery VPC:
   PGPASSWORD=$(aws rds generate-db-auth-token --region "$WRITER_REGION" \
     --hostname "$HOST" --port 5432 --username app) \
     psql "host=$HOST port=5432 dbname=app user=app sslmode=verify-full sslrootcert=/etc/rds/global-bundle.pem" \
       -c 'SELECT pg_is_in_recovery(), current_user;'
   ```

   Ensure the result is the intended write-capable cluster; perform a real application canary transaction and read it back. Distribute the new **regional endpoint and signing region** to surviving-region workloads via the service's tested deployment/config path. Drain old connections, clear pinned DNS/IPs and reconnect with fresh IAM tokens. The AWS global writer DNS endpoint also follows managed role changes, but existing sockets do not move and IAM token signing must use the right region/hostname; using the discovered regional endpoint avoids ambiguity. Respect DNS TTLs and retry transient read-only/connection errors with bounded exponential backoff. Regional IAM connect permissions were preinstalled by the module.

   Route customer write traffic to the healthy EKS region only after successful canaries. Validate checkout end-to-end and then resume jobs/consumers. Do not replay payment requests without idempotency keys and reconciliation. Record first recovered successful commit and actual loss evidence. Database availability alone is not service recovery.

## Stabilize, reconcile, and return to a protected topology

* Keep the failed region fenced even if it returns. Inspect the managed failover result: AWS may reattach it as a secondary after recovery. Never use its stale former-writer data as an independent source of truth or route writes to both clusters. Reconcile missing transactions against payment-provider/idempotency records; do not blindly replay.
* Preserve incident evidence. Check tables, extensions, SQL users, IAM, TLS, KMS access, secret replica, backups and load/lag. Ensure there is once again a healthy cross-region secondary. If AWS didn't recover it, follow the approved AWS rejoin/rebuild procedure; this is a **new** recovery operation, not `tofu apply` against stale topology.
* Infrastructure remains frozen until refresh-only plans and normal plans have been reviewed against actual roles. Provider aliases identify geographic regions, not movable roles. Do not swap `primary_region` and `secondary_region` to represent promotion: that can replace resources, keys or subnets. Import/reconcile any rebuilt clusters with their existing geographic addresses. Do not approve destructive changes to the live writer.
* The RPO alarm is deliberately in the initially secondary region. While that region is writer, missing secondary RPO metrics can alarm; do not disable paging globally. Before adopting a permanently reversed topology, re-home replication monitoring to the actual secondary and review backup windows and credential/secret ownership. Alternatively perform a tested managed **switchover back** once the original region is healthy and caught up, restoring the initial layout and monitoring. No automatic failback.
* Verify a new backup/PITR recovery point in the current writer region and restore it in isolation. Global replicas are not independent protection from logical corruption. Preserve keys and snapshots for compliance retention even if decommissioning old infrastructure.
* Close the incident only after measured RTO/RPO, data reconciliation and restore/failover results are recorded. A five-second target breach is a business incident even when the database becomes available quickly.
