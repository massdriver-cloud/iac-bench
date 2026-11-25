# -----------------------------------------------------------------------------
# The only input an app team must supply is `name`. Everything else has a
# safe, opinionated default.
# -----------------------------------------------------------------------------

variable "name" {
  description = "Short identifier for the bucket, usually the application or asset purpose (e.g. \"checkout-uploads\"). Used as the bucket name prefix; AWS appends a unique suffix so the name is globally unique. Lowercase letters, numbers and hyphens only, 1-30 characters, must start/end with a letter or number."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9](?:[a-z0-9-]{0,28}[a-z0-9])?$", var.name))
    error_message = "name must be 1-30 characters of lowercase letters, numbers or hyphens, starting and ending with a letter or number."
  }

  validation {
    condition     = !can(regex("--", var.name)) && !startswith(var.name, "xn--")
    error_message = "name must not contain consecutive hyphens or start with \"xn--\" (S3 naming rules)."
  }
}

variable "tags" {
  description = "Additional tags to apply to the bucket (e.g. team, environment, cost-center). The module always adds Name and ManagedBy tags."
  type        = map(string)
  default     = {}
}

variable "kms_key_arn" {
  description = "Optional ARN of a customer-managed KMS key for encryption. Leave unset to use S3-managed AES256 encryption, which is the right choice for most applications."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null || can(regex("^arn:aws[a-zA-Z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/.+$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN (arn:aws:kms:<region>:<account>:key/<id>), not an alias."
  }
}

variable "force_destroy" {
  description = "Allow the bucket (and all of its objects and versions) to be deleted by OpenTofu. Keep false for anything holding real data; set true only for scratch/test buckets."
  type        = bool
  default     = false
}

variable "infrequent_access_transition_days" {
  description = "Move current objects to STANDARD_IA after this many days (cheaper storage for assets that stop being read often). Must be >= 30 (S3 minimum for IA). Set to null to keep everything in STANDARD."
  type        = number
  default     = 90

  validation {
    condition     = var.infrequent_access_transition_days == null || var.infrequent_access_transition_days >= 30
    error_message = "infrequent_access_transition_days must be at least 30 (the S3 minimum billable duration for STANDARD_IA), or null to disable."
  }
}

variable "expiration_days" {
  description = "Permanently delete current objects this many days after creation. Off by default: application assets are never silently deleted. Turn on for logs or other genuinely disposable data. Must be greater than infrequent_access_transition_days when both are set."
  type        = number
  default     = null

  validation {
    condition     = var.expiration_days == null || var.expiration_days >= 1
    error_message = "expiration_days must be a positive number of days, or null to never expire objects."
  }
}

variable "noncurrent_version_expiration_days" {
  description = "Delete old (noncurrent) object versions this many days after they are superseded. Versioning is always on; this keeps the cost of overwritten/deleted objects bounded."
  type        = number
  default     = 90

  validation {
    condition     = var.noncurrent_version_expiration_days >= 1
    error_message = "noncurrent_version_expiration_days must be at least 1."
  }
}
