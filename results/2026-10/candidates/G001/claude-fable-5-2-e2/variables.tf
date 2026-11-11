###############################################################################
# Required inputs - the only things an app team has to fill in.
###############################################################################

variable "app_name" {
  description = "Short name of the application that owns this bucket, e.g. \"checkout\" or \"photo-service\". Lowercase letters, digits and hyphens, 3-24 characters."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,22}[a-z0-9]$", var.app_name)) && !strcontains(var.app_name, "--")
    error_message = "app_name must be 3-24 characters, lowercase letters, digits and single hyphens only, starting with a letter and ending with a letter or digit (e.g. \"photo-service\")."
  }
}

variable "environment" {
  description = "Deployment environment this bucket belongs to, e.g. \"dev\", \"staging\" or \"prod\". Lowercase letters and digits, 2-8 characters."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,7}$", var.environment))
    error_message = "environment must be 2-8 lowercase letters or digits, starting with a letter (e.g. \"dev\", \"staging\", \"prod\")."
  }
}

###############################################################################
# Optional inputs - every default is the recommended setting.
###############################################################################

variable "purpose" {
  description = "What the bucket holds, used in its name so an app can have more than one bucket (e.g. \"uploads\", \"media\", \"exports\", \"logs\"). Lowercase letters, digits and hyphens, 3-15 characters."
  type        = string
  default     = "assets"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,13}[a-z0-9]$", var.purpose)) && !strcontains(var.purpose, "--")
    error_message = "purpose must be 3-15 characters, lowercase letters, digits and single hyphens only, starting with a letter and ending with a letter or digit (e.g. \"uploads\")."
  }
}

variable "read_write_role_names" {
  description = "Names (not ARNs) of the IAM roles your application runs as and that need to read, upload and delete objects. The module attaches a least-privilege policy to each."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for n in var.read_write_role_names : can(regex("^[A-Za-z0-9+=,.@_-]{1,64}$", n))])
    error_message = "read_write_role_names must contain IAM role names (e.g. \"checkout-api\"), not ARNs or paths."
  }
}

variable "read_only_role_names" {
  description = "Names (not ARNs) of IAM roles that only need to list and download objects. The module attaches a least-privilege read-only policy to each."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for n in var.read_only_role_names : can(regex("^[A-Za-z0-9+=,.@_-]{1,64}$", n))])
    error_message = "read_only_role_names must contain IAM role names (e.g. \"reporting-job\"), not ARNs or paths."
  }
}

variable "cors_allowed_origins" {
  description = "Web origins whose browsers may upload to / download from the bucket directly using pre-signed URLs, e.g. [\"https://app.example.com\"]. Leave empty if only your backend talks to the bucket. Wildcard-only origins (\"*\") are rejected."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for o in var.cors_allowed_origins :
      can(regex("^https://[A-Za-z0-9*.-]+(:[0-9]+)?$", o)) || can(regex("^http://localhost(:[0-9]+)?$", o))
    ])
    error_message = "Each CORS origin must be an https:// origin without a path (e.g. \"https://app.example.com\"), or http://localhost[:port] for local development. A bare \"*\" is not allowed."
  }
}

variable "expire_objects_after_days" {
  description = "Automatically delete objects this many days after they were created. Leave null (the default) to keep objects until your application deletes them. Useful for buckets of logs, temporary exports or other generated files."
  type        = number
  default     = null

  validation {
    condition     = var.expire_objects_after_days == null ? true : (var.expire_objects_after_days >= 1 && floor(var.expire_objects_after_days) == var.expire_objects_after_days)
    error_message = "expire_objects_after_days must be a whole number of days, 1 or greater, or null to never expire objects."
  }
}

variable "deleted_object_recovery_days" {
  description = "How many days an overwritten or deleted object can still be recovered (versioning keeps the old copy for this long, then it is permanently removed)."
  type        = number
  default     = 30

  validation {
    condition     = var.deleted_object_recovery_days >= 1 && var.deleted_object_recovery_days <= 365 && floor(var.deleted_object_recovery_days) == var.deleted_object_recovery_days
    error_message = "deleted_object_recovery_days must be a whole number between 1 and 365."
  }
}

variable "kms_key_arn" {
  description = "ARN of an existing KMS key to encrypt the bucket with. Leave null (the default) and the module creates and manages a dedicated key with automatic rotation."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null ? true : can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/[A-Za-z0-9-]+$", var.kms_key_arn))
    error_message = "kms_key_arn must be a full KMS key ARN (arn:aws:kms:<region>:<account>:key/<id>), not an alias or bare key ID."
  }
}

variable "access_log_bucket_name" {
  description = "Name of an existing, central S3 bucket (same region) that should receive this bucket's server access logs. Leave null (the default) and the module creates a dedicated, locked-down log bucket."
  type        = string
  default     = null

  validation {
    condition     = var.access_log_bucket_name == null ? true : can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.access_log_bucket_name))
    error_message = "access_log_bucket_name must be a valid S3 bucket name (not an ARN)."
  }
}

variable "access_log_retention_days" {
  description = "How long access logs are kept in the module-managed log bucket before being deleted. Ignored when access_log_bucket_name is set."
  type        = number
  default     = 90

  validation {
    condition     = var.access_log_retention_days >= 30 && var.access_log_retention_days <= 3650 && floor(var.access_log_retention_days) == var.access_log_retention_days
    error_message = "access_log_retention_days must be a whole number between 30 and 3650."
  }
}

variable "force_destroy" {
  description = "Allow `tofu destroy` to delete the bucket even if it still contains objects. Leave false for anything holding real data; only set true for throwaway environments."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Extra tags to add to every resource. The module always sets Application, Environment, Purpose and ManagedBy."
  type        = map(string)
  default     = {}
}
