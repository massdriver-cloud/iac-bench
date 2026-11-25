variable "name" {
  description = "Globally unique App Service name; also the prefix for resources owned by this module."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,38}[a-z0-9]$", var.name))
    error_message = "Use 4-40 lowercase letters, digits or hyphens, starting with a letter and ending with a letter or digit."
  }
}

variable "location" {
  description = "Azure region; must support the selected SKU and, if enabled, availability zones."
  type        = string
  default     = "westeurope"
}

variable "container_image" {
  description = "Production image including tag or digest, without the registry hostname (for example team/api@sha256:...). Prefer immutable digests."
  type        = string
  validation {
    condition     = length(trimspace(var.container_image)) > 0
    error_message = "Provide a container image with a tag or digest."
  }
}

variable "registry_url" {
  description = "HTTPS registry endpoint. Public pulls need no credentials; private ACR uses the app's managed identity."
  type        = string
  default     = "https://mcr.microsoft.com"
  validation {
    condition     = can(regex("^https://[^/]+$", var.registry_url))
    error_message = "Use an HTTPS registry origin without a trailing slash."
  }
}

variable "acr_resource_id" {
  description = "Optional existing Azure Container Registry resource ID. Grants AcrPull to production and staging system-assigned identities. Registry must use RBAC registry permissions, not repository ABAC."
  type        = string
  default     = null
}

variable "container_port" {
  description = "HTTP port exposed by the container; App Service terminates external TLS."
  type        = number
  default     = 8080
  validation {
    condition     = var.container_port >= 1 && var.container_port <= 65535 && floor(var.container_port) == var.container_port
    error_message = "Container port must be an integer from 1 to 65535."
  }
}

variable "health_check_path" {
  description = "Anonymous readiness endpoint returning HTTP 200-299 without redirects; used for health and swap warmup."
  type        = string
  default     = "/health"
  validation {
    condition     = startswith(var.health_check_path, "/")
    error_message = "The health check path must start with /."
  }
}

variable "sku_name" {
  description = "Dedicated Premium v3 plan size. Restricting SKUs keeps always-on, slots and autoscaling available."
  type        = string
  default     = "P1v3"
  validation {
    condition     = contains(["P1v3", "P2v3", "P3v3"], var.sku_name)
    error_message = "Choose P1v3, P2v3 or P3v3."
  }
}

variable "instance_count" {
  description = "Fixed worker count, or minimum/default worker count when autoscaling. Two by default for instance redundancy."
  type        = number
  default     = 2
  validation {
    condition     = var.instance_count >= 1 && var.instance_count <= 30 && floor(var.instance_count) == var.instance_count
    error_message = "Instance count must be an integer from 1 to 30."
  }
}

variable "zone_redundant" {
  description = "Distribute workers across zones in a supported region. Requires at least three workers in this module. Cannot generally be changed on an existing plan."
  type        = bool
  default     = false
}

variable "autoscale" {
  description = "Optional CPU autoscale: scale out above 70% over 5 minutes, in below 30% over 10 minutes."
  type = object({
    enabled       = optional(bool, false)
    max_instances = optional(number, 5)
  })
  default = {}
  validation {
    condition     = var.autoscale.max_instances >= 1 && var.autoscale.max_instances <= 30 && floor(var.autoscale.max_instances) == var.autoscale.max_instances
    error_message = "Autoscale maximum must be an integer from 1 to 30."
  }
}

variable "staging_enabled" {
  description = "Create a staging slot for controlled warmup, swap and rollback. Slots share plan workers and capacity."
  type        = bool
  default     = true
}

variable "staging_image" {
  description = "Optional independently pinned staging image. Null uses container_image. Promotion and rollback are explicit operational actions, never automatic swaps."
  type        = string
  default     = null
}

variable "app_settings" {
  description = "Production environment variables, including Key Vault reference strings. Prefer references to plaintext secrets; values are stored in state. Module-owned settings take precedence."
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "staging_app_settings" {
  description = "Staging overrides of production environment variables. Mark environment-specific keys in slot_sticky_settings."
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "slot_sticky_settings" {
  description = "Environment-specific app setting names that stay with their slot during swaps (for example database Key Vault references)."
  type        = list(string)
  default     = []
}

variable "integration_subnet_id" {
  description = "Optional existing subnet delegated to Microsoft.Web/serverFarms for regional VNet integration (outbound only). Provision adequate IP space, DNS and egress outside this module."
  type        = string
  default     = null
}

variable "vnet_route_all_enabled" {
  description = "Route all outbound traffic through the integration subnet. Requires subnet connectivity to registry, monitoring and application dependencies."
  type        = bool
  default     = false
}

variable "alert_email_addresses" {
  description = "Optional SRE email receivers for HTTP 5xx, response latency, CPU and memory alerts. Alerts still exist without receivers."
  type        = set(string)
  default     = []
}

variable "response_time_threshold_seconds" {
  description = "Alert threshold for average production HTTP response time over 5 minutes."
  type        = number
  default     = 2
  validation {
    condition     = var.response_time_threshold_seconds > 0
    error_message = "Response time threshold must be positive."
  }
}

variable "tags" {
  description = "Resource tags for ownership, environment and cost attribution."
  type        = map(string)
  default     = {}
}
