variable "app_name" {
  type        = string
  description = "Globally unique DNS label for the production app. Also used as the prefix for dedicated resources."
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,37}[a-z0-9]$", var.app_name))
    error_message = "Use 3-39 lowercase letters, digits or hyphens, starting with a letter and ending with a letter or digit."
  }
}

variable "location" {
  type        = string
  description = "Azure region supporting Linux Premium v3 plans."
  default     = "eastus"
}

variable "image" {
  type        = string
  description = "Production image as repository:tag (without registry hostname). Use immutable release tags."
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9._/-]*:[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$", var.image))
    error_message = "Supply a repository and explicit tag, e.g. library/nginx:1.27-alpine."
  }
}

variable "registry_url" {
  type        = string
  default     = "https://index.docker.io"
  description = "HTTPS registry origin for both slots. No embedded credentials."
  validation {
    condition     = can(regex("^https://[a-zA-Z0-9.-]+(:[0-9]+)?$", var.registry_url))
    error_message = "Use an HTTPS registry origin without a path."
  }
}

variable "acr_id" {
  type        = string
  default     = null
  description = "Optional existing Azure Container Registry resource ID matching registry_url. Grants the app's pull identity AcrPull."
}

variable "container_port" {
  type        = number
  default     = 80
  description = "HTTP listening port inside the container."
  validation {
    condition     = var.container_port >= 1 && var.container_port <= 65535 && floor(var.container_port) == var.container_port
    error_message = "Supply an integer TCP port between 1 and 65535."
  }
}

variable "health_path" {
  type        = string
  default     = "/health"
  description = "Unauthenticated readiness endpoint; must return HTTP 200 when ready."
  validation {
    condition     = startswith(var.health_path, "/") && !startswith(var.health_path, "//")
    error_message = "Health path must start with a single slash."
  }
}

variable "capacity" {
  type = object({
    sku            = optional(string, "P1v3")
    workers        = optional(number, 2)
    zone_redundant = optional(bool, false)
  })
  default     = {}
  description = "Fixed plan capacity shared by production and staging; zone redundancy requires a supported region."
  validation {
    condition     = contains(["P1v3", "P2v3", "P3v3"], var.capacity.sku) && var.capacity.workers >= 2 && var.capacity.workers <= 30 && floor(var.capacity.workers) == var.capacity.workers
    error_message = "Use P1v3, P2v3 or P3v3 with 2-30 whole workers."
  }
}

variable "staging_image" {
  type        = string
  default     = null
  description = "Set to a candidate repository:tag to provision the staging slot. Null omits the slot."
  validation {
    condition     = var.staging_image == null || can(regex("^[a-z0-9][a-z0-9._/-]*:[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$", var.staging_image))
    error_message = "Supply null or a tagged staging image."
  }
}

variable "app_settings" {
  type        = map(string)
  default     = {}
  description = "Service configuration shared by both slots. Avoid secrets in state. Platform routing, storage and warmup settings take precedence."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Azure tags for all taggable resources."
}
