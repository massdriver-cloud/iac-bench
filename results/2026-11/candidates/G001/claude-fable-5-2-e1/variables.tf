# -----------------------------------------------------------------------------
# The two inputs every team must fill in.
# -----------------------------------------------------------------------------

variable "application" {
  description = "Name of the application that owns this bucket, e.g. \"checkout\" or \"photo-service\". Lowercase letters, digits and hyphens. Becomes the first part of the bucket name."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,22}[a-z0-9]$", var.application))
    error_message = "application must be 3-24 characters, start with a lowercase letter, end with a letter or digit, and contain only lowercase letters, digits and hyphens (e.g. \"photo-service\")."
  }

  validation {
    condition     = !strcontains(var.application, "--") && !startswith(var.application, "sthree-") && !startswith(var.application, "amzn-s3-demo-")
    error_message = "application must not contain consecutive hyphens or start with \"sthree-\" or \"amzn-s3-demo-\" (S3 reserves those bucket name patterns)."
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

# -----------------------------------------------------------------------------
# Common, optional inputs. The defaults are the recommended settings.
# -----------------------------------------------------------------------------

variable "purpose" {
  description = "What the bucket holds, in one or two words, e.g. \"uploads\", \"media\", \"exports\", \"logs\". Lets one application have several buckets. Becomes part of the bucket name."
  type        = string
  default     = "assets"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,14}[a-z0-9]$", var.purpose)) && !strcontains(var.purpose, "--")
    error_message = "purpose must be 2-16 characters, start with a lowercase letter, end with a letter or digit, and contain only lowercase letters, digits and single hyphens (e.g. \"uploads\")."
  }
}

variable "read_write_role_names" {
  description = "Names (not ARNs) of IAM roles in this account that your application runs as and that should be able to list, read, upload and delete files in the bucket. The module attaches a least-privilege policy to each. Deletes are recoverable (see noncurrent_version_retention_days)."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for n in var.read_write_role_names : can(regex("^[A-Za-z0-9+=,.@_-]{1,64}$", n))])
    error_message = "read_write_role_names must contain IAM role names (e.g. \"checkout-api\"), not ARNs or paths."
  }
}

variable "read_only_role_names" {
  description = "Names (not ARNs) of IAM roles in this account that should only be able to list and read files in the bucket."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for n in var.read_only_role_names : can(regex("^[A-Za-z0-9+=,.@_-]{1,64}$", n))])
    error_message = "read_only_role_names must contain IAM role names (e.g. \"reporting-worker\"), not ARNs or paths."
  }
}

variable "cors_allowed_origins" {
  description = "Web origins whose browser code may upload to / download from the bucket directly using pre-signed URLs, e.g. [\"https://app.example.com\"]. Leave empty if only your backend talks to the bucket. This does NOT make anything public; every request still needs valid credentials or a pre-signed URL."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for o in var.cors_allowed_origins :
      can(regex("^https://(\\*\\.)?[A-Za-z0-9.-]+(:[0-9]+)?$", o)) || can(regex("^http://localhost(:[0-9]+)?$", o))
    ])
    error_message = "Each CORS origin must be an https:// origin without a path (e.g. \"https://app.example.com\" or \"https://*.example.com\"), or http://localhost[:port] for local development. A bare \"*\" is not allowed."
  }
}

variable "cloudfront_distribution_arns" {
  description = "ARNs of CloudFront distributions allowed to read files from this bucket through Origin Access Control. This is the supported way to serve images/videos to the public: the bucket itself always stays private."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for a in var.cloudfront_distribution_arns : can(regex("^arn:aws[a-z-]*:cloudfront::[0-9]{12}:distribution/[A-Z0-9]+$", a))])
    error_message = "Each entry must be a CloudFront distribution ARN, e.g. \"arn:aws:cloudfront::123456789012:distribution/E2ABCDEFGHIJKL\"."
  }
}

variable "expire_objects_after_days" {
  description = "Automatically delete files this many days after they were uploaded. Leave null (the default) to keep files until your application deletes them. Useful for logs, temporary exports and other generated files."
  type        = number
  default     = null

  validation {
    condition     = var.expire_objects_after_days == null ? true : (var.expire_objects_after_days >= 1 && floor(var.expire_objects_after_days) == var.expire_objects_after_days)
    error_message = "expire_objects_after_days must be a whole number of days >= 1, or null to never expire."
  }
}

variable "noncurrent_version_retention_days" {
  description = "How many days an overwritten or deleted file can still be recovered. After this, the old version is permanently removed."
  type        = number
  default     = 30

  validation {
    condition     = var.noncurrent_version_retention_days >= 1 && var.noncurrent_version_retention_days <= 3650 && floor(var.noncurrent_version_retention_days) == var.noncurrent_version_retention_days
    error_message = "noncurrent_version_retention_days must be a whole number between 1 and 3650."
  }
}

variable "tags" {
  description = "Extra tags to add to every resource. The module already sets Application, Environment, Purpose and ManagedBy."
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# Platform-level inputs. App teams normally never touch these.
# -----------------------------------------------------------------------------

variable "kms_key_arn" {
  description = "ARN of an existing KMS key to encrypt the bucket with. Leave null (the default) and the module creates and manages a dedicated key with rotation enabled. If you bring your own key, its key policy is your responsibility (including CloudFront access, if used)."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null ? true : can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/[a-z0-9-]+$", var.kms_key_arn))
    error_message = "kms_key_arn must be a full KMS key ARN (arn:aws:kms:<region>:<account>:key/<id>), not an alias or bare key ID."
  }
}

variable "access_log_bucket_name" {
  description = "Name of an existing central S3 access-log bucket (same region and account) to deliver this bucket's access logs to. Leave null (the default) and the module creates a small, locked-down companion log bucket. A central bucket's policy must already allow S3 log delivery from this account."
  type        = string
  default     = null

  validation {
    condition     = var.access_log_bucket_name == null ? true : can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.access_log_bucket_name))
    error_message = "access_log_bucket_name must be a valid S3 bucket name (not an ARN)."
  }
}

variable "access_log_retention_days" {
  description = "How long access logs are kept in the companion log bucket created by this module. Ignored when access_log_bucket_name is set."
  type        = number
  default     = 365

  validation {
    condition     = var.access_log_retention_days >= 30 && var.access_log_retention_days <= 3650 && floor(var.access_log_retention_days) == var.access_log_retention_days
    error_message = "access_log_retention_days must be a whole number between 30 and 3650."
  }
}

variable "force_destroy" {
  description = "Allow `tofu destroy` to delete the bucket even when it still contains files (all files and all versions are lost). Refused for environment = \"prod\"."
  type        = bool
  default     = false
}
