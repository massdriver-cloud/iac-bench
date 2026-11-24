variable "name_prefix" {
  description = "Short app/environment name, e.g. gallery-prod. A unique suffix is added for S3's global namespace."
  type        = string
  nullable    = false
  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,33}[a-z0-9])?$", var.name_prefix)) && !startswith(var.name_prefix, "xn--") && !startswith(var.name_prefix, "sthree-") && !startswith(var.name_prefix, "amzn-s3-demo-")
    error_message = "Use 1-35 lowercase letters, digits or internal hyphens and avoid S3 reserved prefixes."
  }
}

variable "tags" {
  description = "Optional ownership, environment and billing tags for the bucket."
  type        = map(string)
  default     = {}
  nullable    = false
}
