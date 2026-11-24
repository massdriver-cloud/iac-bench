variable "bucket_name" {
  description = "Globally unique S3 bucket name within the AWS partition. Use 3–63 lowercase letters, digits, or hyphens, with no dots. Changing the name requires replacement."
  type        = string
  nullable    = false

  validation {
    condition = (
      can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.bucket_name)) &&
      !can(regex("^(xn--|sthree-|amzn-s3-demo-)", var.bucket_name)) &&
      !can(regex("(-s3alias|--ol-s3|--x-s3|--table-s3)$", var.bucket_name))
    )
    error_message = "Use 3–63 lowercase letters, digits, or hyphens, starting and ending with a letter or digit. Reserved S3 prefixes and suffixes are not allowed."
  }
}

variable "aws_region" {
  description = "AWS region for the bucket. If omitted, use the AWS provider's environment or shared configuration. Set it explicitly for reproducible deployments."
  type        = string
  default     = null
}

variable "tags" {
  description = "Optional tags, such as Application, Environment, or CostCenter. Name and ManagedBy are set by this module."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "kms_key_arn" {
  description = "Optional ARN (not alias) of an enabled symmetric customer-managed KMS key in the bucket region. Omit to use S3-managed encryption (SSE-S3)."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null ? true : can(regex("^arn:[a-z0-9-]+:kms:[a-z0-9-]+:[0-9]{12}:key/[a-zA-Z0-9-]+$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN (not a key ID or alias ARN), or null."
  }
}

variable "noncurrent_version_expiration_days" {
  description = "Optional number of days after an object version becomes noncurrent before S3 can permanently delete it. Omit to retain noncurrent versions indefinitely."
  type        = number
  default     = null

  validation {
    condition     = var.noncurrent_version_expiration_days == null ? true : (var.noncurrent_version_expiration_days >= 1 && floor(var.noncurrent_version_expiration_days) == var.noncurrent_version_expiration_days)
    error_message = "Set noncurrent_version_expiration_days to a positive whole number or null."
  }
}
