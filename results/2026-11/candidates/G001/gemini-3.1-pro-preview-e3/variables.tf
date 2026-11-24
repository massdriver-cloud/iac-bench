variable "bucket_name" {
  description = "The name of the bucket. Must be globally unique."
  type        = string
}

variable "environment" {
  description = "The environment for this bucket (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "enable_versioning" {
  description = "Whether to enable bucket versioning. Recommended for application assets."
  type        = bool
  default     = true
}

variable "force_destroy" {
  description = "Whether to allow a non-empty bucket to be destroyed."
  type        = bool
  default     = false
}
