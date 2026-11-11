variable "bucket_name" {
  description = "Globally unique S3 bucket name. Use 3–63 lowercase letters, numbers, periods, or hyphens."
  type        = string

  validation {
    condition = (
      length(var.bucket_name) >= 3 && length(var.bucket_name) <= 63 &&
      can(regex("^[a-z0-9][a-z0-9.-]*[a-z0-9]$", var.bucket_name)) &&
      !strcontains(var.bucket_name, "..") &&
      !can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$", var.bucket_name)) &&
      !startswith(var.bucket_name, "xn--") &&
      !startswith(var.bucket_name, "sthree-") &&
      !startswith(var.bucket_name, "amzn-s3-demo-") &&
      !endswith(var.bucket_name, "-s3alias") &&
      !endswith(var.bucket_name, "--ol-s3") &&
      !endswith(var.bucket_name, ".mrap") &&
      !endswith(var.bucket_name, "--x-s3") &&
      !endswith(var.bucket_name, "--table-s3")
    )
    error_message = "bucket_name must be a valid S3 general-purpose bucket name; it must also be globally unique."
  }
}

variable "tags" {
  description = "Tags to apply to the bucket."
  type        = map(string)
  default     = {}
}

variable "kms_key_arn" {
  description = "Optional ARN of a customer-managed KMS key for default encryption. If null, S3-managed encryption (SSE-S3) is used. The key must be in the bucket's region and its policy must authorize users of the bucket."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_arn == null ? true : can(regex("^arn:[^:]+:kms:[^:]+:[0-9]{12}:key/.+$", var.kms_key_arn))
    error_message = "kms_key_arn must be a KMS key ARN, not an alias or key ID."
  }
}

variable "force_destroy" {
  description = "Allow OpenTofu to delete all objects and versions when destroying the bucket. Leave false to protect data."
  type        = bool
  default     = false
}
