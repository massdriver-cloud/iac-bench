variable "bucket_name" {
  description = "Name for the S3 bucket. Bucket names are globally unique across all AWS accounts."
  type        = string

  validation {
    condition = (
      length(var.bucket_name) >= 3 &&
      length(var.bucket_name) <= 63 &&
      can(regex("^[a-z0-9][a-z0-9.-]*[a-z0-9]$", var.bucket_name)) &&
      !strcontains(var.bucket_name, "..") &&
      !can(regex("^(\\d{1,3}\\.){3}\\d{1,3}$", var.bucket_name))
    )
    error_message = "bucket_name must be 3-63 characters, contain only lowercase letters, numbers, periods and hyphens, start and end with a letter or number, not contain two adjacent periods, and not look like an IP address."
  }
}

variable "application" {
  description = "Application or service that owns this bucket. Used for tagging and default access-log prefixes."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*$", var.application))
    error_message = "application must use lowercase letters, numbers and hyphens, and start with a letter or number."
  }
}

variable "environment" {
  description = "Environment name for the bucket owner (for example: dev, staging, prod)."
  type        = string
  default     = "dev"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*$", var.environment))
    error_message = "environment must use lowercase letters, numbers and hyphens, and start with a letter or number."
  }
}

variable "region" {
  description = "AWS region where the bucket is created. Leave unset to use the provider environment region (AWS_REGION or AWS_DEFAULT_REGION)."
  type        = string
  default     = null
}

variable "versioning_enabled" {
  description = "Keep every version of every object so accidental overwrites or deletes can be recovered."
  type        = bool
  default     = true
}

variable "encryption_algorithm" {
  description = "Server-side encryption algorithm applied to objects written to the bucket: AES256 (SSE-S3) or aws:kms (SSE-KMS)."
  type        = string
  default     = "AES256"

  validation {
    condition     = contains(["AES256", "aws:kms"], var.encryption_algorithm)
    error_message = "encryption_algorithm must be one of: AES256, aws:kms."
  }
}

variable "kms_key_arn" {
  description = "ARN of a customer-managed KMS key. Only used when encryption_algorithm is aws:kms. If omitted, the S3-managed aws/s3 key is used."
  type        = string
  default     = null
}

variable "force_destroy" {
  description = "Allow the bucket to be destroyed even when it still contains objects. Leave false for anything you care about."
  type        = bool
  default     = false
}

variable "block_public_access" {
  description = "Block all public access to the bucket and its objects. Keep true unless there is an explicit, approved reason to make objects public."
  type        = bool
  default     = true
}

variable "enforce_tls" {
  description = "Add a bucket policy that denies any request made without HTTPS."
  type        = bool
  default     = true
}

variable "allowed_write_principals" {
  description = "IAM principal ARNs (roles or users) allowed to list, read, write and delete objects in the bucket."
  type        = list(string)
  default     = []
}

variable "allowed_read_principals" {
  description = "IAM principal ARNs (roles or users) allowed to list and read objects in the bucket."
  type        = list(string)
  default     = []
}

variable "enable_lifecycle_rules" {
  description = "Enable recommended lifecycle rules: abort incomplete multipart uploads and expire old noncurrent versions."
  type        = bool
  default     = true
}

variable "noncurrent_version_expiration_days" {
  description = "Number of days to keep noncurrent (superseded) object versions before permanently deleting them."
  type        = number
  default     = 90

  validation {
    condition     = var.noncurrent_version_expiration_days >= 1
    error_message = "noncurrent_version_expiration_days must be at least 1."
  }
}

variable "abort_incomplete_multipart_upload_days" {
  description = "Number of days to wait before aborting incomplete multipart uploads."
  type        = number
  default     = 7

  validation {
    condition     = var.abort_incomplete_multipart_upload_days >= 1
    error_message = "abort_incomplete_multipart_upload_days must be at least 1."
  }
}

variable "access_logging_target_bucket" {
  description = "Optional name of an S3 bucket where server access logs are delivered. If unset, server access logging is disabled."
  type        = string
  default     = null
}

variable "access_logging_target_prefix" {
  description = "Optional key prefix for server access-log delivery. Defaults to s3/<application>/."
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional tags to apply to the bucket."
  type        = map(string)
  default     = {}
}
