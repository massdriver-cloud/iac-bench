# Standard Application Assets S3 Bucket (OpenTofu Module)

The standard OpenTofu module for provisioning Amazon S3 buckets for application assets — user uploads, images and videos, generated files, and logs.

Application developers only need to supply three inputs (`application`, `environment`, and `purpose`). The module handles security, encryption, durability, cost optimization, access logging, and least-privilege IAM policies by default.

## Quick Start

Create a `.tfvars` file (or copy `minimal.tfvars`) with three inputs:

```hcl
application = "storefront"
environment = "prod"
purpose     = "user-uploads"
```

```bash
tofu init
tofu plan -var-file=minimal.tfvars
tofu apply -var-file=minimal.tfvars
```

## What You Get Out of the Box

Every bucket created by this module enforces these defaults automatically:

| Area | Built-in Standard | Why It Matters |
| --- | --- | --- |
| **Public Access** | All 4 Block Public Access settings locked to `true` | Prevents accidental public data exposure. Serve public media through CloudFront OAC instead. |
| **Object Ownership** | `BucketOwnerEnforced` (ACLs disabled) | Eliminates ACL confusion; the bucket owner always owns every uploaded object. |
| **Encryption at Rest** | Dedicated customer-managed KMS key with annual rotation and S3 Bucket Keys enabled | Auditability, rotation, and cryptographic control at minimal KMS cost (up to 99% fewer KMS API calls via Bucket Keys). |
| **Encryption in Transit** | Bucket policy denies non-HTTPS (`aws:SecureTransport = false`) and TLS < 1.2 | Prevents plaintext traffic and legacy TLS downgrades. |
| **Encryption Guardrail** | Denies `PutObject` requests that explicitly specify a weaker algorithm or wrong KMS key | Protects against encryption downgrades without breaking standard AWS SDK calls that omit encryption headers. |
| **Versioning** | Enabled by default, with automatic cleanup of old versions and orphan delete markers | Protects against accidental overwrites and deletes without unbounded storage bills. |
| **Cost Control** | Aborts incomplete multipart uploads automatically; applies `128 KB` minimum transition size; enables Intelligent-Tiering for unpredictable access patterns | Stops silent billing leaks from failed uploads and small-object transition fees. |
| **Access Logging** | S3 Server Access Logging enabled with date-partitioned keys; automatically creates a hardened companion log bucket if no central log bucket is provided | Full audit trail of object access with zero extra setup. |
| **IAM Policies** | Creates ready-to-attach `read-only`, `read-write`, and `write-only` IAM policies covering both S3 and KMS permissions | Application roles attach an output ARN instead of hand-rolling overly permissive `s3:*` policies or forgetting KMS permissions. |
| **Naming & Tagging** | Deterministic globally unique name (`<application>-<environment>-<purpose>-<account_id>-<region>`, safely bounded to 63 chars) and standard tags | Eliminates inconsistent naming and missing cost-allocation tags. |

## Copy-Paste Examples by Workload

### 1. User Uploads (with browser direct-to-S3 presigned uploads)

```hcl
application          = "storefront"
environment          = "prod"
purpose              = "user-uploads"
workload_type        = "user-uploads"
cors_allowed_origins = ["https://app.example.com"]
enable_eventbridge   = true # Trigger async virus scanning / processing
```

### 2. Images & Videos (served via CloudFront OAC)

```hcl
application                  = "media-service"
environment                  = "prod"
purpose                      = "assets"
workload_type                = "media"
cloudfront_distribution_arns = ["arn:aws:cloudfront::123456789012:distribution/E1234567890ABC"]
```

CloudFront OAC permissions are added to **both** the S3 bucket policy and the KMS key policy automatically.

### 3. Generated Files (exports, reports, temporary artifacts)

```hcl
application            = "billing"
environment            = "prod"
purpose                = "exports"
workload_type          = "generated" # Auto-expires objects after 30 days, no Intelligent-Tiering overhead
object_expiration_days = 14          # Optional override
```

### 4. Application Logs (archival & retention)

```hcl
application           = "payments"
environment           = "prod"
purpose               = "audit-logs"
workload_type         = "logs" # Transitions to Glacier Instant Retrieval at 30d, expires at 365d
enable_access_logging = false  # Optional when the bucket itself only stores logs
```

### 5. Using an Organization Central Access Log Bucket

```hcl
application            = "storefront"
environment            = "prod"
purpose                = "user-uploads"
access_log_bucket_name = "org-central-s3-access-logs-123456789012-us-east-1"
```

## Connecting Your Application

Attach one of the generated least-privilege IAM policies to your ECS task role, Lambda execution role, or EKS service account role:

- `read_only_policy_arn` — Read objects and list bucket (plus KMS decrypt)
- `read_write_policy_arn` — Read, write, and delete current objects (intentionally omits `s3:DeleteObjectVersion` so compromised credentials cannot purge version history)
- `write_only_policy_arn` — Upload objects and complete multipart uploads (ideal for log shippers and ingestion workers)

## Workload Presets

| `workload_type` | Intelligent-Tiering | Current Object Archival | Current Object Expiration | Noncurrent Version Transition | Noncurrent Version Expiration | Abort Multipart Uploads |
| --- | --- | --- | --- | --- | --- | --- |
| `general` (default) | Enabled | — | None | 30d (`STANDARD_IA`) | 90d | 7d |
| `user-uploads` | Enabled | — | None | 30d (`STANDARD_IA`) | 90d | 7d |
| `media` | Enabled | — | None | None | 30d | 3d |
| `generated` | Disabled | — | 30d | None | 14d | 7d |
| `logs` | Disabled | 30d (`GLACIER_IR`) | 365d | None | 30d | 7d |

Every preset value can be individually overridden with its corresponding variable (`enable_intelligent_tiering`, `object_expiration_days`, `archive_after_days`, `noncurrent_version_transition_days`, `noncurrent_version_expiration_days`, `abort_incomplete_multipart_upload_days`).
