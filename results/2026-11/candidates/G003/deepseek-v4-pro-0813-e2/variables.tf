variable "name" {
  description = "Name of the app service. Also becomes the base of the resource name."
  type        = string

  validation {
    condition     = length(var.name) <= 40
    error_message = "The name must be 40 characters or less (Azure App Service site name limit)."
  }
}

variable "resource_group_name" {
  description = "Name of the resource group to deploy into."
  type        = string
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
}

variable "app_service_plan_id" {
  description = <<-EOT
    Optional. ID of an existing App Service Plan to attach the app to.
    If omitted, a plan is created for you from the capacity/availability inputs below.
  EOT
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# Capacity & availability
# ---------------------------------------------------------------------------

variable "capacity_sku" {
  description = "The App Service Plan SKU (e.g. P1v2, P2v3, S1)."
  type        = string
  default     = "P1v3"

  validation {
    condition     = can(regex("^(F1|B[123]|S[123]|P[123]v[23]|P1mv3)$", var.capacity_sku))
    error_message = "capacity_sku must be a supported production (non-Free B/S/P) SKU pattern."
  }
}

variable "os_type" {
  description = "OS of the host. Containerized workloads are always Linux."
  type        = string
  default     = "Linux"

  validation {
    condition     = var.os_type == "Linux"
    error_message = "This module only supports Linux container workloads."
  }
}

variable "worker_count" {
  description = "Fixed number of worker instances. Ignored when autoscaling is enabled."
  type        = number
  default     = 2
}

variable "autoscale" {
  description = "Autoscale settings for the plan. Leave null to use a fixed worker_count."
  type = object({
    min_capacity = number
    max_capacity = number
    target_cpu   = number
  })
  default = null

  validation {
    condition = var.autoscale == null || (
      var.autoscale.min_capacity >= 1 &&
      var.autoscale.max_capacity >= var.autoscale.min_capacity &&
      var.autoscale.target_cpu > 0 && var.autoscale.target_cpu < 100
    )
    error_message = "autoscale must have min >= 1, max >= min, and 0 < target_cpu < 100."
  }
}

variable "zone_redundant" {
  description = "Deploy the plan across availability zones. Requires a v3 SKU and >= 3 instances."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Container image
# ---------------------------------------------------------------------------

variable "docker_image" {
  description = "Container image and tag to run (e.g. 'myorg/myservice:latest')."
  type        = string
}

variable "docker_registry_url" {
  description = "URL of the container registry, e.g. https://index.docker.io or https://myacr.azurecr.io."
  type        = string
  default     = "https://index.docker.io"
}

variable "docker_registry_username" {
  description = "Username for a private registry. Defaults to managed identity/runtime credential for ACR."
  type        = string
  default     = null
  sensitive   = true
}

variable "docker_registry_password" {
  description = "Password for a private registry."
  type        = string
  default     = null
  sensitive   = true
}

# ---------------------------------------------------------------------------
# Runtime / health / rollout
# ---------------------------------------------------------------------------

variable "port" {
  description = "Port the container listens on for HTTP."
  type        = number
  default     = 80
}

variable "always_on" {
  description = "Keep the app always loaded (required for paid plans; disable to allow idle shutdown)."
  type        = bool
  default     = true
}

variable "startup_command" {
  description = "Optional command run at container startup to override the image CMD."
  type        = string
  default     = null
}

variable "slot_enabled" {
  description = "Create a staging deployment slot for canary/rollout."
  type        = bool
  default     = false
}

variable "staging_traffic" {
  description = "Percentage of production traffic routed to the staging slot (0-100). Ignored when slot_enabled is false."
  type        = number
  default     = 0

  validation {
    condition     = var.staging_traffic >= 0 && var.staging_traffic <= 100
    error_message = "staging_traffic must be between 0 and 100."
  }
}

# ---------------------------------------------------------------------------
# Observability & identity
# ---------------------------------------------------------------------------

variable "app_insights_enabled" {
  description = "Provision Application Insights and wire it into the app."
  type        = bool
  default     = true
}

variable "system_identity_enabled" {
  description = "Enable a system-assigned managed identity on the app."
  type        = bool
  default     = true
}

variable "log_analytics_workspace_id" {
  description = "Optional Log Analytics workspace to attach for container/diagnostic logs."
  type        = string
  default     = null
}

variable "app_settings" {
  description = "Extra app settings applied to both production and staging slots."
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}