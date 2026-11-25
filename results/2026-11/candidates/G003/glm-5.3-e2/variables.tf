variable "name" {
  description = "Short, stable name of the service, e.g. 'checkout-api'. Used as the DNS label of the app and as the prefix of every resource this module creates. Must be globally unique: the app answers on <name>-<environment>.azurewebsites.net."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,22}[a-z0-9]$", var.name))
    error_message = "name must be 4-24 characters, start with a lowercase letter, end with a letter or digit, and contain only lowercase letters, digits and hyphens."
  }
}

variable "environment" {
  description = "Deployment environment of this instance, e.g. 'dev', 'stage', 'prod'. Appended to the service name in every resource name and tag."
  type        = string
  default     = "prod"

  validation {
    condition     = can(regex("^[a-z0-9]{1,8}$", var.environment))
    error_message = "environment must be 1-8 lowercase letters or digits."
  }
}

variable "location" {
  description = "Azure region hosting every resource of this service. Use a region with availability zones (e.g. westeurope, northeurope, eastus): Premium v3 plans there are zone-redundant by platform default, and min_instances then keeps one warm instance per zone."
  type        = string
}

variable "tags" {
  description = "Extra tags merged onto every resource. The module always adds application, environment and managed_by tags."
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# Capacity
# ---------------------------------------------------------------------------

variable "instance_size" {
  description = "Size of a single instance: small (P1v3, ~210 ACU / 3.5 GB), medium (P2v3, ~420 ACU / 7 GB), large (P3v3, ~840 ACU / 14 GB). All instances of the service share this size."
  type        = string
  default     = "small"

  validation {
    condition     = contains(["small", "medium", "large"], var.instance_size)
    error_message = "instance_size must be one of: small, medium, large."
  }
}

variable "min_instances" {
  description = "Number of instances always kept warm. 3 is the standard floor: on a zone-redundant plan (the platform default for Premium v3 in zone-capable regions) that means capacity in every zone at all times."
  type        = number
  default     = 3

  validation {
    condition     = var.min_instances >= 1 && floor(var.min_instances) == var.min_instances
    error_message = "min_instances must be a whole number of at least 1."
  }
}

variable "max_instances" {
  description = "Upper bound on the number of instances. The platform scales out on CPU pressure and back in below it. Set equal to min_instances to pin capacity."
  type        = number
  default     = 10

  validation {
    condition     = var.max_instances >= 1 && floor(var.max_instances) == var.max_instances
    error_message = "max_instances must be a whole number of at least 1."
  }
}

# ---------------------------------------------------------------------------
# Health
# ---------------------------------------------------------------------------

variable "health_probe_path" {
  description = "Path the platform polls on every instance to decide whether it is healthy. Instances failing the probe for 10 minutes are taken out of rotation and replaced. Must start with '/'."
  type        = string
  default     = "/health"

  validation {
    condition     = can(regex("^/[A-Za-z0-9._/-]*$", var.health_probe_path))
    error_message = "health_probe_path must be a URL path starting with '/' (letters, digits, '.', '_', '-' and '/' only)."
  }
}

# ---------------------------------------------------------------------------
# Rollouts
# ---------------------------------------------------------------------------

variable "enable_staging_slot" {
  description = "Run a second deployment slot ('staging') with the same configuration as production. New versions are deployed to the slot, warmed, health-checked and then swapped into production with zero downtime."
  type        = bool
  default     = true
}

variable "staging_auto_swap" {
  description = "Automatically promote the staging slot to production whenever a new deployment lands on it. Off by default: promotions are deliberate. The image running on the slot is owned by your delivery pipeline; this module deliberately never reverts it."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Observability
# ---------------------------------------------------------------------------

variable "alert_emails" {
  description = "Addresses paged by this module's alert rules (HTTP 5xx, response latency, CPU saturation). At least one is required: a standard service is never deployed without somebody to page."
  type        = list(string)

  validation {
    condition = length(var.alert_emails) > 0 && alltrue([
      for e in var.alert_emails : can(regex("^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$", e))
    ])
    error_message = "alert_emails must contain at least one syntactically valid email address."
  }
}

variable "log_retention_days" {
  description = "Days that HTTP, console, audit and platform logs of the service are kept in the Log Analytics workspace."
  type        = number
  default     = 90

  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730 && floor(var.log_retention_days) == var.log_retention_days
    error_message = "log_retention_days must be a whole number between 30 and 730."
  }
}

# ---------------------------------------------------------------------------
# The application
# ---------------------------------------------------------------------------

variable "container_image" {
  description = "Container image to run, without the tag, e.g. 'myacr.azurecr.io/team/checkout-api' or 'nginx' for a public Docker Hub image."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9._/-]*$", var.container_image))
    error_message = "container_image must be an image reference without a tag (letters, digits, '.', '_', '/' and '-' only)."
  }
}

variable "container_image_tag" {
  description = "Tag of container_image deployed to production. Pin an exact version: 'latest' hides which build is serving traffic."
  type        = string
  default     = "latest"
}

variable "container_port" {
  description = "Port the container listens on for HTTP traffic. Must match the port your process binds."
  type        = number
  default     = 80

  validation {
    condition     = var.container_port >= 1 && var.container_port <= 65535 && floor(var.container_port) == var.container_port
    error_message = "container_port must be a whole number between 1 and 65535."
  }
}

variable "container_registry" {
  description = "Registry credentials for a private container image: server (e.g. 'myacr.azurecr.io'), username and password. Omit for public images."
  type = object({
    server   = string
    username = string
    password = string
  })
  default   = null
  sensitive = true
}

variable "app_settings" {
  description = "Application environment variables passed to the container (name to value). Names colliding with module-managed settings (APPLICATIONINSIGHTS_CONNECTION_STRING, WEBSITES_PORT, DOCKER_REGISTRY_*) override the module's value."
  type        = map(string)
  default     = {}
}

variable "virtual_network_subnet_id" {
  description = "Optional subnet resource ID to integrate the app with. The subnet must be delegated to 'Microsoft.Web/serverFarms'. Use this when the API must reach private backends."
  type        = string
  default     = null
}
