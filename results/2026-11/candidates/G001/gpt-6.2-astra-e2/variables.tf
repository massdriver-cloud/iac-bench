variable "bucket_label" {
  description = "Short lowercase app/environment label, e.g. gallery-prod. The module adds a unique suffix."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,33}[a-z0-9])?$", var.bucket_label))
    error_message = "Use 1–35 lowercase letters, digits or hyphens; start and end with a letter or digit."
  }
}

variable "tags" {
  description = "Additional AWS tags, for example Team or CostCenter."
  type        = map(string)
  default     = {}
  nullable    = false
}
