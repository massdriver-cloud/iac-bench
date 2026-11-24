variable "app_name" {
  description = "Short name of the application that owns the bucket (lowercase letters, digits and hyphens; 2-20 characters). Example: \"checkout\"."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.app_name)) && length(var.app_name) >= 2 && length(var.app_name) <= 20
    error_message = "app_name must be 2-20 characters, start with a letter, contain only lowercase letters, digits and hyphens, and must not end with a hyphen."
  }
}

variable "environment" {
  description = "Deployment environment the bucket serves."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "owner_team" {
  description = "Team responsible for the bucket (used for tagging and ownership questions). Example: \"payments-team\"."
  type        = string

  validation {
    condition     = length(trimspace(var.owner_team)) > 0 && length(var.owner_team) <= 64
    error_message = "owner_team must be a non-empty string of at most 64 characters."
  }
}

variable "asset_class" {
  description = <<-EOT
    What kind of assets the bucket holds. The module picks versioning, lifecycle
    and retention settings from this:
      - user-uploads: files users upload. Kept until deleted; old versions expire after 90 days.
      - media:        images and video. Moves to cheaper storage after 90 days; old versions expire after 30 days.
      - generated:    files the application can regenerate. Current objects expire after 30 days.
      - logs:         application logs. Current objects expire after 90 days.
  EOT
  type        = string
  default     = "user-uploads"

  validation {
    condition     = contains(["user-uploads", "media", "generated", "logs"], var.asset_class)
    error_message = "asset_class must be one of: user-uploads, media, generated, logs."
  }
}

variable "cors_allowed_origins" {
  description = "Browser origins allowed to read/write the bucket directly (for example, presigned uploads from a web app). Leave empty to disable CORS. Example: [\"https://app.example.com\"]."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for o in var.cors_allowed_origins : can(regex("^https://", o)) || can(regex("^http://localhost(:[0-9]+)?$", o))])
    error_message = "Each CORS origin must start with https:// (or be http://localhost, for development)."
  }
}
