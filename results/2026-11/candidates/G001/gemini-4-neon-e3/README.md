# Standard Application S3 Bucket Module

The standard OpenTofu module for provisioning Amazon S3 buckets for application assets (user uploads, images and videos, generated files, and logs).

Application developers only need to provide a couple of obvious inputs (`app_name`, `environment`, and optionally `purpose` and `workload_profile`). Every security, encryption, lifecycle, cost-hygiene, and IAM detail is handled automatically with opinionated defaults.

---

## What You Get Automatically

| Concern | Default Behavior |
|---|---|
| **Global naming** | Automatically named `<app_name>-<purpose>-<environment>-<account_id>-<region>` so names never collide across accounts or regions. |
| **Private by default** | All four S3 Public Access Block settings are permanently enabled and legacy ACLs are disabled (`BucketOwnerEnforced`). Public asset delivery uses CloudFront Origin Access Control (OAC). |
| **Encryption at rest** | Dedicated, auto-rotating AWS KMS customer-managed key with S3 Bucket Keys enabled (cuts KMS API costs by ~99%). Opt in to `encryption_type = "sse_s3"` or bring an existing `kms_key_arn` when needed. |
| **Encryption in transit** | Bucket policy denies all non-HTTPS requests (`aws:SecureTransport = false`), denies TLS < 1.2, and blocks upload header downgrades while keeping standard SDK/presigned uploads working out of the box. |
| **Data protection & cost hygiene** | Workload-tuned versioning, automatic cleanup of incomplete multipart uploads, Intelligent-Tiering for objects > 128 KB (avoiding monitoring fees on small objects), and bounded noncurrent version retention. |
| **Least-privilege app IAM** | Generates ready-to-attach `read_only` and `read_write` IAM managed policies (automatically scoped to both the bucket and its KMS key, excluding destructive actions like `s3:DeleteObjectVersion` and bucket-admin permissions). |
| **Production guardrails** | `force_destroy = true` is blocked on `prod`/`production` environments, and wildcard CORS (`"*"`) is blocked whenever write methods (`PUT`/`POST`/`DELETE`) are enabled. |
| **Consistent tagging** | Tags every created resource with `Application`, `Environment`, `Purpose`, `WorkloadProfile`, `DataClassification`, `ManagedBy`, and optional `Owner` + custom `tags`. |

---

## Quick Start Examples

### 1. Minimal App Asset Bucket (User Uploads, General Files)

```hcl
app_name    = "checkout"
environment = "prod"
```

Uses the `assets` profile: versioning enabled, KMS encryption with Bucket Keys, Intelligent-Tiering for objects > 128 KB, noncurrent versions retained 90 days (keeping at least 3 recent versions), and incomplete multipart uploads aborted after 7 days.

### 2. Browser Direct Uploads (Presigned URLs + CORS)

```hcl
app_name         = "profile-service"
environment      = "prod"
purpose          = "uploads"
owner            = "identity-team"
workload_profile = "assets"

cors_allowed_origins = [
  "https://app.example.com",
]

enable_eventbridge = true # Trigger downstream image resizing or virus scanning
```

### 3. Images & Videos Served via CloudFront (Private Bucket + OAC)

```hcl
app_name         = "catalog"
environment      = "prod"
purpose          = "media"
workload_profile = "assets"

cloudfront_distribution_arns = [
  "arn:aws:cloudfront::123456789012:distribution/E1234567890ABC",
]

enable_transfer_acceleration = true
```

Both the bucket policy and the managed KMS key policy are automatically updated to allow your CloudFront distribution to read objects via OAC while keeping the bucket completely private. Use the `bucket_regional_domain_name` output as your CloudFront origin domain.

### 4. Generated Files & Temporary Exports

```hcl
app_name               = "reporting"
environment            = "prod"
purpose                = "exports"
workload_profile       = "temporary"
object_expiration_days = 14 # Override profile default of 30 days
```

Uses the `temporary` profile: versioning suspended, incomplete uploads cleaned up after 3 days, objects automatically expired after 14 days.

### 5. Application Logs

```hcl
app_name         = "payments"
environment      = "prod"
purpose          = "logs"
workload_profile = "logs"
encryption_type  = "sse_s3"
```

Uses the `logs` profile: versioning suspended, automatic tiering (`STANDARD_IA` at 30d -> `GLACIER_IR` at 90d -> `GLACIER` at 180d) and expiration at 365 days.

---

## Granting Your Application Access

Attach the generated IAM policy directly to your ECS task role, EKS IRSA role, or Lambda execution role — KMS permissions are already included:

```hcl
resource "aws_iam_role_policy_attachment" "app_bucket_rw" {
  role       = aws_iam_role.app.name
  policy_arn = module.assets_bucket.read_write_iam_policy_arn
}
```

Use `read_only_iam_policy_arn` for read-only workers or analytics services, or consume `read_write_iam_policy_json` / `read_only_iam_policy_json` directly if you compose inline policies.

---

## Workload Profiles Summary

| Profile | Versioning | Intelligent-Tiering (>128 KB) | Current Object Tiering | Current Object Expiration | Noncurrent Expiration | Abort Multipart |
|---|---|---|---|---|---|---|
| `assets` *(default)* | Enabled | Enabled | — | Never | 90 days (IA at 30d, keep 3) | 7 days |
| `temporary` | Suspended | Disabled | — | 30 days | 7 days (if overridden on) | 3 days |
| `logs` | Suspended | Disabled | IA (30d) -> Glacier IR (90d) -> Glacier (180d) | 365 days | 30 days (if overridden on) | 7 days |
| `archive` | Enabled | Disabled | Glacier IR (30d) -> Deep Archive (180d) | Never | 365 days (IA at 30d, keep 3) | 7 days |

Every profile setting can be individually overridden (`versioning_enabled`, `object_expiration_days`, `noncurrent_version_expiration_days`, `abort_incomplete_multipart_upload_days`), and prefix-specific rules can be added via `custom_lifecycle_rules`.

---

## Key Inputs

| Name | Required | Default | Description |
|---|---|---|---|
| `app_name` | Yes | — | Lowercase app/service name (2–24 chars). |
| `environment` | Yes | — | Deployment environment, e.g. `dev`, `staging`, `prod` (2–12 chars). |
| `purpose` | No | `"assets"` | Short label for bucket contents (e.g. `uploads`, `media`, `exports`, `logs`). |
| `workload_profile` | No | `"assets"` | Preset profile: `assets`, `temporary`, `logs`, or `archive`. |
| `encryption_type` | No | `"kms"` | `kms` (dedicated auto-rotating CMK + Bucket Keys) or `sse_s3`. |
| `kms_key_arn` | No | `null` | Existing KMS key ARN when `encryption_type = "kms"`. |
| `cors_allowed_origins` | No | `[]` | Browser origins allowed for direct uploads/fetches. |
| `cloudfront_distribution_arns` | No | `[]` | CloudFront distribution ARNs granted OAC read access. |
| `access_log_bucket_name` | No | `null` | Centralized S3 access logging bucket (must allow `logging.s3.amazonaws.com` writes). |
| `create_iam_policies` | No | `true` | Creates managed `read_only` and `read_write` IAM policies. |
| `enable_eventbridge` | No | `false` | Emit S3 object events to EventBridge. |
| `enable_transfer_acceleration` | No | `false` | Enable S3 Transfer Acceleration for large global uploads. |
| `force_destroy` | No | `false` | Allow destroying non-empty bucket (blocked in `prod`/`production`). |

See `variables.tf` for the full list of inputs and validation rules.

## Key Outputs

| Name | Description |
|---|---|
| `bucket_name` | S3 bucket name (ID). |
| `bucket_arn` | S3 bucket ARN. |
| `bucket_regional_domain_name` | Regional domain name (use for CloudFront origins). |
| `kms_key_arn` | Active KMS key ARN (or `null` for SSE-S3). |
| `read_only_iam_policy_arn` | Managed read-only IAM policy ARN. |
| `read_write_iam_policy_arn` | Managed read-write IAM policy ARN. |
| `read_only_iam_policy_json` | Least-privilege read-only IAM policy JSON. |
| `read_write_iam_policy_json` | Least-privilege read-write IAM policy JSON. |
| `effective_configuration` | Resolved summary of active profile, encryption, and lifecycle settings. |
