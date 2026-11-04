variable "aws_region" {
  description = "AWS region in which to create the bucket."
  type        = string
  default     = "us-east-1"
  nullable    = false
}

variable "bucket_name" {
  description = "Globally unique S3 bucket name (3-63 lowercase letters, numbers, dots, or hyphens)."
  type        = string
  nullable    = false

  validation {
    condition = (
      length(var.bucket_name) >= 3 &&
      length(var.bucket_name) <= 63 &&
      can(regex("^[a-z0-9][a-z0-9.-]*[a-z0-9]$", var.bucket_name)) &&
      !can(regex("[.][.]", var.bucket_name)) &&
      !can(regex("[.-][.]|[.][-]", var.bucket_name)) &&
      !can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$", var.bucket_name))
    )
    error_message = "bucket_name must follow S3 naming rules: 3-63 lowercase letters, numbers, dots, or hyphens; no adjacent periods, period-hyphen combinations, or IPv4-address form."
  }
}

variable "enable_versioning" {
  description = "Keep prior object versions so accidental overwrites and deletes can be recovered."
  type        = bool
  default     = true
  nullable    = false
}

variable "tags" {
  description = "Additional tags to apply to the S3 bucket."
  type        = map(string)
  default     = {}
  nullable    = false
}
