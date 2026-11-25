variable "bucket_name" {
  description = "Name of the S3 bucket. Must be globally unique in AWS S3."
  type        = string
}

variable "force_destroy" {
  description = "Boolean indicating whether all objects should be deleted from the bucket so that the bucket can be destroyed without error."
  type        = bool
  default     = false
}

variable "tags" {
  description = "A map of tags to add to all resources."
  type        = map(string)
  default     = {}
}

variable "versioning_enabled" {
  description = "Enable versioning for the S3 bucket to protect against accidental overwrites and deletions."
  type        = bool
  default     = true
}

variable "versioning_mfa_delete" {
  description = "Enable MFA delete for versioning ('Enabled' or 'Disabled')."
  type        = string
  default     = null
}

variable "block_public_acls" {
  description = "Whether to block public ACLs for this bucket."
  type        = bool
  default     = true
}

variable "block_public_policy" {
  description = "Whether to block public bucket policies for this bucket."
  type        = bool
  default     = true
}

variable "ignore_public_acls" {
  description = "Whether to ignore public ACLs for this bucket."
  type        = bool
  default     = true
}

variable "restrict_public_buckets" {
  description = "Whether to restrict public bucket policies for this bucket."
  type        = bool
  default     = true
}

variable "object_ownership" {
  description = "Object ownership setting ('BucketOwnerEnforced', 'BucketOwnerPreferred', or 'ObjectWriter')."
  type        = string
  default     = "BucketOwnerEnforced"
}

variable "sse_algorithm" {
  description = "Server-side encryption algorithm to use ('AES256' or 'aws:kms')."
  type        = string
  default     = "AES256"
}

variable "kms_key_arn" {
  description = "ARN of the KMS key to use for encryption. If set, sse_algorithm will default to aws:kms."
  type        = string
  default     = null
}

variable "bucket_key_enabled" {
  description = "Whether Amazon S3 should use an S3 Bucket Key for SSE-KMS encryption."
  type        = bool
  default     = true
}

variable "enforce_tls" {
  description = "Enforce TLS/HTTPS-only requests using bucket policy."
  type        = bool
  default     = true
}

variable "custom_policy_json" {
  description = "Optional additional IAM policy JSON to merge into the bucket policy."
  type        = string
  default     = null
}

variable "abort_incomplete_multipart_upload_days" {
  description = "Number of days after initiation to abort incomplete multipart uploads. Set to 0 or null to disable."
  type        = number
  default     = 7
}

variable "noncurrent_version_expiration_days" {
  description = "Number of days after which noncurrent object versions expire. Set to 0 or null to disable."
  type        = number
  default     = 90
}

variable "expiration_days" {
  description = "Number of days after which current objects expire. Set to null or 0 to disable."
  type        = number
  default     = null
}

variable "cors_rules" {
  description = "List of CORS rules for the bucket."
  type = list(object({
    id              = optional(string)
    allowed_headers = optional(list(string), ["*"])
    allowed_methods = list(string)
    allowed_origins = list(string)
    expose_headers  = optional(list(string), [])
    max_age_seconds = optional(number, 3000)
  }))
  default = []
}

variable "custom_lifecycle_rules" {
  description = "List of custom lifecycle rules."
  type = list(object({
    id                                     = string
    status                                 = optional(string, "Enabled")
    prefix                                 = optional(string, "")
    abort_incomplete_multipart_upload_days = optional(number)
    expiration_days                        = optional(number)
    noncurrent_version_expiration_days     = optional(number)
    transitions = optional(list(object({
      days          = number
      storage_class = string
    })), [])
    noncurrent_version_transitions = optional(list(object({
      noncurrent_days = number
      storage_class   = string
    })), [])
  }))
  default = []
}

variable "logging_target_bucket" {
  description = "Name of the bucket to receive access logs. If null, access logging is disabled."
  type        = string
  default     = null
}

variable "logging_target_prefix" {
  description = "Prefix for access log object keys."
  type        = string
  default     = "log/"
}
