variable "team" {
  description = "Owning team, used for naming and cost allocation."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{2,24}$", var.team))
    error_message = "team must be 2-24 lowercase alphanumeric/hyphen characters."
  }
}

variable "purpose" {
  description = "Short purpose slug for the bucket name (e.g. webapp, downloads)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{2,24}$", var.purpose))
    error_message = "purpose must be 2-24 lowercase alphanumeric/hyphen characters."
  }
}

variable "environment" {
  description = "Deployment environment."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "transition_days" {
  description = "Days before objects transition to infrequent-access storage. Org policy floor: 30."
  type        = number
  default     = 30

  validation {
    condition     = var.transition_days >= 30
    error_message = "Org storage policy forbids transitions earlier than 30 days."
  }
}

variable "public_read" {
  description = "Allow public read access to the bucket contents."
  type        = bool
  default     = false
}
