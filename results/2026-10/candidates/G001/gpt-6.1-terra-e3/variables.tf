variable "bucket_name" {
  description = "Globally unique S3 bucket name. Use lowercase letters, digits, hyphens and periods."
  type        = string

  validation {
    condition = (
      length(var.bucket_name) >= 3 && length(var.bucket_name) <= 63 &&
      can(regex("^[a-z0-9][a-z0-9.-]*[a-z0-9]$", var.bucket_name)) &&
      !strcontains(var.bucket_name, "..") &&
      !can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$", var.bucket_name)) &&
      !can(regex("^(xn--|sthree-|amzn-s3-demo-)", var.bucket_name)) &&
      !can(regex("(-s3alias|--ol-s3|\\.mrap|--x-s3|--table-s3)$", var.bucket_name))
    )
    error_message = "bucket_name must be a valid 3–63 character general-purpose S3 bucket name, without reserved prefixes or suffixes."
  }
}

variable "tags" {
  description = "Tags to apply to the bucket."
  type        = map(string)
  default     = {}
}

variable "versioning_enabled" {
  description = "Keep object versions to protect against accidental overwrites and deletes. Suspending versioning does not remove existing versions."
  type        = bool
  default     = true
}

variable "force_destroy" {
  description = "Allow OpenTofu to delete all objects and versions when destroying the bucket. Leave false to protect data."
  type        = bool
  default     = false
}
