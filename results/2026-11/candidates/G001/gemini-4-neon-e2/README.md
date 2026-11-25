# Standard Application Assets S3 Bucket Module

A secure-by-default OpenTofu module for provisioning Amazon S3 buckets for application assets — user uploads, images and videos, generated files, and logs — without requiring application teams to master S3 internals.

## Quick Start

Provide just three inputs in a `.tfvars` file (see `minimal.tfvars`):

```hcl
app_name    = "checkout"
environment = "prod"
owner       = "payments-team"
```

Then attach one of the generated least-privilege IAM policies (`read_write_policy_arn` or `read_only_policy_arn`) to your application's IAM role (ECS task role, Lambda execution role, EKS IRSA role). Both policies automatically include the exact S3 and KMS permissions required.

## What You Get Automatically

- **Collision-free, deterministic bucket naming** (`<app>-<purpose>-<env>-<hash>`) scoped to the AWS account and region.
- **Private by default**: all four S3 Public Access Block settings enabled, legacy ACLs disabled (`BucketOwnerEnforced`).
- **Encryption at rest & in transit**:
  - Dedicated customer-managed KMS key with annual key rotation and S3 Bucket Key enabled (~99% KMS cost reduction).
  - Bucket policy denying non-HTTPS requests, TLS < 1.2, and encryption downgrade headers without breaking standard SDK uploads.
- **Data protection & cost hygiene**:
  - Object versioning enabled by default (profile-aware) with automatic noncurrent version tiering/expiration and delete marker cleanup.
  - Orphaned multipart uploads aborted automatically after 7 days.
  - Automatic S3 Intelligent-Tiering for objects >= 128 KB (objects < 128 KB stay in Standard to avoid monitoring fees).
  - `force_destroy` disabled by default and strictly blocked in `prod`.
- **Auditability**: S3 server access logging enabled out of the box (either to your central log bucket or an auto-provisioned, hardened, date-partitioned companion log bucket with 90-day retention).
- **Event-driven ready**: Amazon EventBridge notifications enabled by default so downstream services (thumbnailing, virus scanning, indexing) can subscribe cleanly.
- **Least-privilege IAM policies**: ready-to-attach `read_only` and `read_write` IAM managed policies (intentionally excluding destructive bucket/version-purge actions).

## Common Examples

### 1. User Uploads & Media (Browser Direct Uploads + CloudFront CDN)

```hcl
app_name    = "storefront"
purpose     = "media"
environment = "prod"
owner       = "consumer-web"
use_case    = "media"

cors_allowed_origins = ["https://shop.example.com"]
cloudfront_distribution_arns = [
  "arn:aws:cloudfront::123456789012:distribution/E1A2B3C4D5E6F7",
]
```

### 2. Application Logs

```hcl
app_name    = "billing-api"
purpose     = "logs"
environment = "prod"
owner       = "billing-team"
use_case    = "logs" # Unversioned; IA at 30d, Glacier IR at 90d, expires at 365d
```

### 3. Ephemeral Generated Exports

```hcl
app_name               = "reporting"
purpose                = "exports"
environment            = "prod"
owner                  = "analytics-team"
use_case               = "ephemeral" # Unversioned; expires at 30d
object_expiration_days = 14          # Optional override
```

### 4. Mixed Bucket with Prefix-Scoped Expiration

```hcl
app_name    = "documents"
environment = "prod"
owner       = "core-platform"

custom_lifecycle_rules = [
  {
    id              = "expire-temp-uploads"
    prefix          = "tmp/"
    expiration_days = 7
  }
]
```

## Workload Profiles (`use_case`)

| `use_case` | Versioning | Intelligent-Tiering (>=128KB) | Current Object Expiry | Noncurrent Version Retention |
|---|---|---|---|---|
| `assets` *(default)* | Enabled | Enabled | Never | IA at 30d, expire at 90d |
| `media` | Enabled | Enabled | Never | Expire at 30d |
| `logs` | Suspended | Disabled (IA 30d, Glacier IR 90d) | 365 days | N/A |
| `ephemeral` | Suspended | Disabled | 30 days | N/A |

Every profile setting can be overridden individually via variables (`versioning_enabled`, `intelligent_tiering_enabled`, `object_expiration_days`, `noncurrent_version_expiration_days`, `noncurrent_version_transition_ia_days`).
