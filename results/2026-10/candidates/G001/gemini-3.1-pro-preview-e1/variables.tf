variable "app_name" {
  type        = string
  description = "The name of the application."
}

variable "environment" {
  type        = string
  description = "The environment (e.g., dev, staging, prod)."
}

variable "purpose" {
  type        = string
  description = "The purpose of the bucket (e.g., assets, logs, uploads)."
}

variable "versioning_enabled" {
  type        = bool
  default     = true
  description = "Enable versioning for accidental deletion protection. Default is true."
}

variable "force_destroy" {
  type        = bool
  default     = false
  description = "Allow deleting the bucket even if it contains objects. Useful for dev environments."
}
