variable "bucket_name" {
  type        = string
  description = "Globally unique S3 bucket name within the AWS partition. Use lowercase letters, digits and hyphens only (no dots, for virtual-hosted HTTPS compatibility)."
  nullable    = false

  validation {
    condition = (
      can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.bucket_name)) &&
      !can(regex("^(xn--|sthree-|amzn-s3-demo-)", var.bucket_name)) &&
      !can(regex("(-s3alias|--ol-s3|--x-s3|--table-s3|-an)$", var.bucket_name))
    )
    error_message = "Use 3–63 lowercase letters, digits or hyphens, beginning and ending with a letter or digit. S3-reserved prefixes and suffixes are not allowed."
  }
}

variable "tags" {
  type        = map(string)
  description = "Optional tags for the bucket, such as Application, Environment and CostCenter. Name is set to the bucket name."
  default     = {}
  nullable    = false
}

variable "kms_key_arn" {
  type        = string
  description = "Optional ARN of an existing symmetric customer-managed KMS key in the bucket's region. If omitted, use S3-managed encryption (SSE-S3)."
  default     = null

  validation {
    condition = var.kms_key_arn == null || can(regex(
      "^arn:[a-z0-9-]+:kms:[a-z0-9-]+:[0-9]{12}:key/[a-zA-Z0-9-]+$", var.kms_key_arn
    ))
    error_message = "Provide a KMS key ARN (not an alias or a bare key ID), or omit kms_key_arn to use SSE-S3."
  }
}

variable "noncurrent_version_expiration_days" {
  type        = number
  description = "Optional number of days after an object version becomes noncurrent before S3 may permanently delete it. Omit to retain noncurrent versions indefinitely."
  default     = null

  validation {
    condition = var.noncurrent_version_expiration_days == null ? true : (
      var.noncurrent_version_expiration_days >= 1 &&
      var.noncurrent_version_expiration_days == floor(var.noncurrent_version_expiration_days)
    )
    error_message = "Set noncurrent_version_expiration_days to a positive whole number of days, or omit it."
  }
}
