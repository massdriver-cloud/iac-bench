# ---------------------------------------------------------------------------
# Service identity
# ---------------------------------------------------------------------------

variable "name" {
  description = "Short, DNS-safe name of the service (e.g. \"orders-api\"). Used as the base name of every resource the module creates."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,28}[a-z0-9]$", var.name))
    error_message = "name must be 3-30 characters of lowercase letters, digits and hyphens, and must start and end with a letter or digit."
  }
}

variable "environment" {
  description = "Environment label for this deployment (e.g. \"dev\", \"prod\"). Used in resource names and tags."
  type        = string
  default     = "dev"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,10}[a-z0-9]$", var.environment))
    error_message = "environment must be 2-12 characters of lowercase letters, digits and hyphens, and must start and end with a letter or digit."
  }
}

variable "location" {
  description = "Azure region for the service. Ignored when resource_group_name points at an existing resource group (its location is used instead)."
  type        = string
  default     = "eastus"
}

variable "resource_group_name" {
  description = "Existing resource group to deploy into. Leave null to let the module create and own \"rg-<name>-<environment>\"."
  type        = string
  default     = null
}

variable "subscription_id" {
  description = "Azure subscription the provider operates in. Leave null to use the environment's default subscription."
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional tags merged over the module's own tags (service, environment, managed_by)."
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# Container
# ---------------------------------------------------------------------------

variable "container_image" {
  description = "Container image to run, as a full reference: \"[registry/]repository[:tag]\". Defaults to Docker Hub when no registry host is given and to tag \"latest\" when the tag is omitted."
  type        = string

  validation {
    condition = can(
      regex("^(?:[a-z0-9-]+(?:[.][a-z0-9.-]+)?(?::[0-9]{1,5})?/)?[a-z0-9][a-z0-9._/-]*(?::[a-zA-Z0-9][a-zA-Z0-9._-]*)?$", var.container_image)
    )
    error_message = "container_image must look like \"ghcr.io/org/api:1.2.3\" or \"nginx:latest\" (lowercase repository, optional registry host with optional port, optional tag)."
  }
}

variable "container_port" {
  description = "TCP port the container listens on (surfaced to App Service as WEBSITES_PORT)."
  type        = number
  default     = 80

  validation {
    condition     = var.container_port >= 1 && var.container_port <= 65535
    error_message = "container_port must be a valid TCP port number."
  }
}

variable "container_registry_id" {
  description = "Resource ID of an Azure Container Registry to pull the image from. The app's and the staging slot's system-assigned identities are granted AcrPull on it, and managed-identity registry auth is enabled automatically."
  type        = string
  default     = null

  validation {
    condition     = var.container_registry_id == null || can(regex("^/subscriptions/[0-9a-fA-F-]+/resourceGroups/[^/]+/providers/Microsoft[.]ContainerRegistry/registries/[^/]+$", var.container_registry_id))
    error_message = "container_registry_id must be an ACR resource ID such as \"/subscriptions/.../resourceGroups/rg/providers/Microsoft.ContainerRegistry/registries/myacr\"."
  }
}

# ---------------------------------------------------------------------------
# Capacity & availability
# ---------------------------------------------------------------------------

variable "tier" {
  description = "Capacity tier for the service. small = S1 (1 vCPU / 1.75 GB), medium = P1v3 (2 / 8), large = P2v3 (4 / 16), xlarge = P3v3 (8 / 32)."
  type        = string
  default     = "small"

  validation {
    condition     = contains(["small", "medium", "large", "xlarge"], var.tier)
    error_message = "tier must be one of: small, medium, large, xlarge."
  }
}

variable "min_instances" {
  description = "Autoscale floor: the service never runs below this many instances. Zone-spread tiers are always raised to at least 3 so instances actually spread across zones."
  type        = number
  default     = 2

  validation {
    condition     = var.min_instances >= 1 && var.min_instances <= 30
    error_message = "min_instances must be between 1 and 30."
  }
}

variable "max_instances" {
  description = "Autoscale ceiling. Capped by the tier: 10 instances on small (S1), 30 on the Premium v3 tiers."
  type        = number
  default     = 5

  validation {
    condition     = var.max_instances >= 1 && var.max_instances <= 30
    error_message = "max_instances must be between 1 and 30."
  }
}

variable "zone_redundant" {
  description = "Spread instances across availability zones. null (default) is automatic: enabled on the Premium v3 tiers (medium and up), disabled on small. Premium v3 plans are zone-redundant by platform default in zone-capable regions; this controls even zone balancing and the 3-instance zone floor."
  type        = bool
  default     = null
}

# ---------------------------------------------------------------------------
# Health & rollouts
# ---------------------------------------------------------------------------

variable "health_probe_path" {
  description = "HTTP path App Service probes to decide instance health. Instances failing the probe for 5 consecutive minutes are evicted from the load balancer."
  type        = string
  default     = "/"

  validation {
    condition     = startswith(var.health_probe_path, "/")
    error_message = "health_probe_path must start with '/'."
  }
}

variable "create_staging_slot" {
  description = "Create a \"staging\" deployment slot for blue/green rollouts (Standard tier and above)."
  type        = bool
  default     = true
}

variable "staging_auto_swap" {
  description = "Automatically swap staging into production whenever a deployment lands on the staging slot. Off by default: promotion stays an explicit, deliberate act."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Observability
# ---------------------------------------------------------------------------

variable "alert_emails" {
  description = "Email addresses notified by the action group (health-check, error and saturation alerts, plus autoscale events). Empty by default: alerts exist but notify nobody until you fill this in."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for e in var.alert_emails : can(regex("^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$", e))])
    error_message = "alert_emails must contain valid email addresses."
  }
}

variable "log_retention_days" {
  description = "Interactive retention (days) for the service's Log Analytics workspace."
  type        = number
  default     = 30

  validation {
    condition     = contains([30, 31, 60, 90, 120, 180, 270, 365, 540, 730], var.log_retention_days)
    error_message = "log_retention_days must be one of: 30, 31, 60, 90, 120, 180, 270, 365, 540, 730."
  }
}

variable "app_settings" {
  description = "Extra app settings applied to both the production app and the staging slot, merged over the module's built-ins (WEBSITES_PORT, WEBSITES_ENABLE_APP_SERVICE_STORAGE, App Insights wiring)."
  type        = map(string)
  default     = {}
}
