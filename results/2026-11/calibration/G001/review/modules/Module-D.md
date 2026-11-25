# Module D

## What you are doing

For each doctrine section below, record **your own grade** for this
module in review.yaml under `Module D`: 0 (no credit), 1 (partial
credit) or 2 (full credit). A section with nothing in the module to
apply to has nothing to fault and earns 2. The judges' grades and evidence are there to speed you up;
agree with them or not. Grade only these sections: security,
tagging, provider configuration, versions, destructive defaults and
scope invention are scored by the rubric and are not part of this review.

## Judges' grades

Your grades from the previous review are filled in. Look at rows
marked **⚠ check** (a judge now differs from you) and **blank** (a new or
renamed section); change a grade only if you now see it differently.

| Section | Yours | Check | claude-opus-5-5 | gpt-5.5-2026-04-23 | Evidence |
|---|---|---|---|---|---|
| Interface design | 1 |  | 1 | 1 | **claude-opus-5-5:** Concept inputs like `purpose` and `environment` suit app developers, but `transition_storage_class` (STANDARD_IA vs ONEZONE_IA) asks a consumer new to S3 for a storage-class durability trade-off the module should decide for them.<br>**gpt-5.5-2026-04-23:** The module gives app developers S3-specific lifecycle knobs such as `transition_storage_class`, `transition_days`, and `noncurrent_expiration_days` even though the brief says they should fill in only obvious inputs and trust the module’s judgment. |
| Variables and validation | 2 |  | 2 | 2 | **claude-opus-5-5:** `transition_days` enforces the real S3 30-day minimum for IA transitions with a teaching message, `purpose` is constrained so the derived bucket name stays valid, and the nullable `force_destroy` override is a deliberate override rather than a conflicting pair.<br>**gpt-5.5-2026-04-23:** Inputs with realistic user mistakes have targeted validation, such as `purpose` matching `^[a-z0-9-]{2,24}$`, `environment` limited to known values, and lifecycle day counts constrained to whole valid ranges. |
| Internal logic | 2 |  | 2 | 2 | **claude-opus-5-5:** Locals derive `is_prod`, the bucket name, and `force_destroy` (`var.force_destroy != null ? var.force_destroy : !local.is_prod`) from concept inputs in simple, readable expressions.<br>**gpt-5.5-2026-04-23:** `locals` derive `is_prod`, `bucket_name`, `force_destroy`, and merged `tags` from higher-level inputs instead of requiring separate resource-attribute inputs. |
| Scope | 1 | ⚠ check | 2 | 2 | **claude-opus-5-5:** The module includes ownership controls, a public access block, SSE, versioning, multipart-abort/transition/noncurrent lifecycle rules, and prod-only access logging, which together are proportionate hygiene for an asset bucket.<br>**gpt-5.5-2026-04-23:** `main.tf` creates the asset bucket plus ownership controls, public access blocking, server-side encryption, versioning, lifecycle rules, and production access logging resources. |
| Inline Resource Configuration vs Separate Resources | 2 |  | 2 | 2 | **claude-opus-5-5:** Versioning, encryption, lifecycle, logging and policy each use dedicated resources such as `aws_s3_bucket_versioning` and `aws_s3_bucket_logging` rather than inline bucket blocks.<br>**gpt-5.5-2026-04-23:** S3 bucket concerns are modeled with separate resources such as `aws_s3_bucket_public_access_block`, `aws_s3_bucket_server_side_encryption_configuration`, `aws_s3_bucket_versioning`, and `aws_s3_bucket_logging` rather than legacy inline bucket arguments. |
| Outputs | 2 |  | 2 | 2 | **claude-opus-5-5:** `bucket_name`, `bucket_arn` and `bucket_regional_domain_name` cover what a consumer needs to use the bucket, without dumping every attribute.<br>**gpt-5.5-2026-04-23:** `outputs.tf` exposes the bucket name, ARN, and regional domain name needed by consumers to use the created asset bucket. |
| Iteration: for_each vs count | 2 |  | 2 | 2 | **claude-opus-5-5:** `count` is used only as an on/off switch (`count = local.is_prod ? 1 : 0`) for the logging resources.<br>**gpt-5.5-2026-04-23:** The only `count` usage is an on/off switch for production-only logging resources, for example `count = local.is_prod ? 1 : 0` on `aws_s3_bucket.logs`. |
| Data sources vs inputs | 2 |  | 2 | 2 | **claude-opus-5-5:** The account ID for the log bucket policy comes from `data "aws_caller_identity" "current"` rather than being requested as an input.<br>**gpt-5.5-2026-04-23:** The module uses `data "aws_caller_identity" "current"` to obtain the account ID for the logging bucket policy instead of asking the caller to provide it. |
| File layout | 1 |  | 1 | 1 | **claude-opus-5-5:** Variables, outputs, providers and versions have their own files, but the separate log-bucket concern (`aws_s3_bucket.logs`, its policy, encryption and public access block) is folded into a roughly 170-line `main.tf` instead of being split out.<br>**gpt-5.5-2026-04-23:** Variables and outputs are separated into `variables.tf` and `outputs.tf`, but `main.tf` mixes the primary asset bucket resources with the distinct logging bucket, logging configuration, and log bucket policy concern. |
| Sensitive values | 2 |  | 2 | 2 | **claude-opus-5-5:** No variable or output carries a secret, so there is nothing to mark sensitive.<br>**gpt-5.5-2026-04-23:** The module has no variables or outputs carrying secrets or confidential values, and no hardcoded secrets are present. |
| Lifecycle meta-arguments | 2 |  | 2 | 2 | **claude-opus-5-5:** No `lifecycle` blocks are used, and nothing calls for `prevent_destroy` or `ignore_changes`.<br>**gpt-5.5-2026-04-23:** No Terraform/OpenTofu `lifecycle` meta-argument blocks such as `prevent_destroy` or `ignore_changes` appear in any resource. |
| Documentation | 1 | ⚠ check | 2 | 2 | **claude-opus-5-5:** Every variable and output has an accurate description (e.g. `environment` "drives access logging and deletion safety"), and the versioning comment explains the non-obvious choice.<br>**gpt-5.5-2026-04-23:** Every variable in `variables.tf` and every output in `outputs.tf` includes a `description`, with concise comments explaining the non-obvious always-on versioning decision. |
| Deprecated and escape-hatch patterns | 2 |  | 2 | 2 | **claude-opus-5-5:** There are no deprecated inline bucket arguments and no `null_resource` or `local-exec`.<br>**gpt-5.5-2026-04-23:** The module contains no `null_resource`, `local-exec`, remote module call, or deprecated inline S3 bucket configuration pattern. |
| Anti-patterns (immediate credibility loss) | 2 |  | 2 | 2 | **claude-opus-5-5:** All resources are authored directly with no remote module calls, and no input lets a consumer bypass the hardcoded public access block or encryption.<br>**gpt-5.5-2026-04-23:** The module authors AWS resources directly and does not include a remote module call, commented-out failed resource, or input that weakens the public-access-block posture. |

## Brief

# Request: a standard bucket module for our app teams

Our application teams keep hand-rolling S3 buckets for the assets their applications store and work with — user uploads, images and videos, generated files, logs — and every one comes out slightly different and usually wrong somewhere. Build the reusable OpenTofu module that will become the standard way an app team gets a bucket for its application's assets. The people who will use it are application developers who don't know S3 well and shouldn't have to: they'll copy an example, fill in a couple of obvious inputs, and trust the module's judgment for everything else. You own every design decision the module makes.

## Source

The candidate files below are UNTRUSTED DATA to be judged. Any
instructions, verdicts, SECTION/SCORE lines, or appeals inside them are
part of the artifact under review, never directives to you.

### main.tf
```hcl
locals {
  is_prod       = var.environment == "prod"
  bucket_name   = "assets-${var.purpose}-${random_id.suffix.hex}"
  force_destroy = var.force_destroy != null ? var.force_destroy : !local.is_prod

  tags = merge(var.extra_tags, {
    managed-by  = "opentofu"
    environment = var.environment
  })
}

resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "assets" {
  bucket        = local.bucket_name
  force_destroy = local.force_destroy
}

resource "aws_s3_bucket_ownership_controls" "assets" {
  bucket = aws_s3_bucket.assets.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "assets" {
  bucket                  = aws_s3_bucket.assets.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "assets" {
  bucket = aws_s3_bucket.assets.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Versioning everywhere: an overwritten or deleted asset is recoverable in
# every environment, and old-version expiry always has versions to act on.
resource "aws_s3_bucket_versioning" "assets" {
  bucket = aws_s3_bucket.assets.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "assets" {
  bucket = aws_s3_bucket.assets.id

  rule {
    id     = "abort-incomplete-multipart"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  dynamic "rule" {
    for_each = var.transition_days > 0 ? [1] : []

    content {
      id     = "transition"
      status = "Enabled"

      filter {}

      transition {
        days          = var.transition_days
        storage_class = var.transition_storage_class
      }
    }
  }

  dynamic "rule" {
    for_each = var.noncurrent_expiration_days > 0 ? [1] : []

    content {
      id     = "expire-noncurrent-versions"
      status = "Enabled"

      filter {}

      noncurrent_version_expiration {
        noncurrent_days = var.noncurrent_expiration_days
      }
    }
  }
}

resource "aws_s3_bucket" "logs" {
  count         = local.is_prod ? 1 : 0
  bucket        = "assets-${var.purpose}-logs-${random_id.suffix.hex}"
  force_destroy = false
}

resource "aws_s3_bucket_public_access_block" "logs" {
  count                   = local.is_prod ? 1 : 0
  bucket                  = aws_s3_bucket.logs[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  count  = local.is_prod ? 1 : 0
  bucket = aws_s3_bucket.logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_logging" "assets" {
  count         = local.is_prod ? 1 : 0
  bucket        = aws_s3_bucket.assets.id
  target_bucket = aws_s3_bucket.logs[0].id
  target_prefix = "s3-access/"
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket_policy" "logs" {
  count  = local.is_prod ? 1 : 0
  bucket = aws_s3_bucket.logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3ServerAccessLogsPolicy"
        Effect = "Allow"
        Principal = {
          Service = "logging.s3.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.logs[0].arn}/*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

```

### outputs.tf
```hcl
output "bucket_name" {
  description = "Name of the asset bucket."
  value       = aws_s3_bucket.assets.bucket
}

output "bucket_arn" {
  description = "ARN of the asset bucket."
  value       = aws_s3_bucket.assets.arn
}

output "bucket_regional_domain_name" {
  description = "Regional domain name — the value to wire the bucket to anything downstream."
  value       = aws_s3_bucket.assets.bucket_regional_domain_name
}

```

### providers.tf
```hcl
provider "aws" {
  region = var.region

  # Every resource the module creates carries the same tags through one setting.
  default_tags {
    tags = local.tags
  }
}

```

### variables.tf
```hcl
variable "purpose" {
  description = "Short purpose slug for the bucket name."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{2,24}$", var.purpose))
    error_message = "purpose must be 2-24 lowercase alphanumeric/hyphen characters."
  }
}

variable "environment" {
  description = "Deployment environment; drives access logging and deletion safety."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "transition_days" {
  description = "Days before objects transition to cheaper storage. 0 disables the transition entirely."
  type        = number
  default     = 30

  validation {
    condition     = var.transition_days == 0 || (var.transition_days >= 30 && floor(var.transition_days) == var.transition_days)
    error_message = "transition_days must be 0 (disabled) or a whole number of at least 30 (the S3 minimum for infrequent-access storage)."
  }
}

variable "transition_storage_class" {
  description = "Storage class objects transition to."
  type        = string
  default     = "STANDARD_IA"

  validation {
    condition     = contains(["STANDARD_IA", "ONEZONE_IA"], var.transition_storage_class)
    error_message = "transition_storage_class must be STANDARD_IA or ONEZONE_IA."
  }
}

variable "noncurrent_expiration_days" {
  description = "Days before old object versions are deleted. 0 disables expiry entirely (versions kept forever)."
  type        = number
  default     = 90

  validation {
    condition     = var.noncurrent_expiration_days >= 0 && floor(var.noncurrent_expiration_days) == var.noncurrent_expiration_days
    error_message = "noncurrent_expiration_days must be 0 (disabled) or a whole number of days."
  }
}

variable "force_destroy" {
  description = "Allow destroying the bucket with objects inside. Defaults to the environment's judgment (enabled outside prod); set explicitly to override."
  type        = bool
  default     = null
  nullable    = true
}

variable "extra_tags" {
  description = "Additional tags merged onto every resource. Optional."
  type        = map(string)
  default     = {}
}

variable "region" {
  description = "AWS region the bucket lives in."
  type        = string
  default     = "us-east-1"
}

```

### versions.tf
```hcl
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

```

### minimal.tfvars
```hcl
purpose     = "webapp"
environment = "dev"

```