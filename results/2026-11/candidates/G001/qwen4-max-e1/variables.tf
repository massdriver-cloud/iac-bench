# ---------------------------------------------------------------------------
# Required inputs — the only things an app team must decide.
# ---------------------------------------------------------------------------

variable "application" {
  description = <<-EOT
    Short name of the application this bucket belongs to (e.g. "storefront",
    "media-pipeline"). Used in the bucket name and tags. Must be lowercase
    letters, digits and hyphens, 2-24 characters, starting with a letter and
    ending with a letter or digit. No dots or underscores: they break
    virtual-hosted-style TLS access to S3.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,22}[a-z0-9]$", var.application))
    error_message = "application must be 2-24 characters of lowercase letters, digits or hyphens, start with a letter and end with a letter or digit."
  }

  validation {
    condition     = !strcontains(var.application, "--")
    error_message = "application must not contain consecutive hyphens."
  }
}

variable "environment" {
  description = "Deployment environment this bucket belongs to. One of: dev, test, staging, prod."
  type        = string

  validation {
    condition     = contains(["dev", "test", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, test, staging, prod."
  }
}

# ---------------------------------------------------------------------------
# Optional inputs — sensible defaults; most teams never touch these.
# ---------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region to create the bucket in. Defaults to us-east-1."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", var.aws_region))
    error_message = "aws_region must look like an AWS region name, e.g. us-east-1 or eu-west-2."
  }
}

variable "tags" {
  description = <<-EOT
    Additional tags to apply to the bucket (e.g. team, cost-center). The
    module always sets Application, Environment, Name and ManagedBy itself;
    those reserved keys cannot be overridden here.
  EOT
  type        = map(string)
  default     = {}

  validation {
    condition = length(setintersection(
      keys(var.tags),
      ["Application", "Environment", "Name", "ManagedBy"]
    )) == 0
    error_message = "tags may not override the module-managed keys: Application, Environment, Name, ManagedBy."
  }
}

variable "kms_key_arn" {
  description = <<-EOT
    Optional ARN of a customer-managed KMS key to encrypt objects with
    (SSE-KMS, with S3 Bucket Keys enabled to keep request costs down). Leave
    null to use standard S3-managed encryption (SSE-S3, AES256), which is the
    right choice for most applications. If set, remember the app's IAM role
    needs kms:Decrypt/kms:GenerateDataKey on this key.
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/.+$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN (arn:aws:kms:<region>:<account>:key/<id>), or null."
  }
}

variable "noncurrent_version_expiration_days" {
  description = <<-EOT
    How many days to keep old (noncurrent) object versions after they are
    replaced or deleted. Versioning is always on so accidental overwrites and
    deletes are recoverable; this bounds the storage cost of that safety net.
  EOT
  type        = number
  default     = 30

  validation {
    condition     = var.noncurrent_version_expiration_days >= 7 && floor(var.noncurrent_version_expiration_days) == var.noncurrent_version_expiration_days
    error_message = "noncurrent_version_expiration_days must be a whole number of at least 7 days."
  }
}

variable "force_destroy" {
  description = <<-EOT
    Allow Terraform/OpenTofu to delete the bucket even if it still contains
    objects. Defaults to false so a stray `destroy` can never wipe your
    application's assets. Only set true for throwaway dev buckets you are
    certain you want to delete.
  EOT
  type        = bool
  default     = false
}
