variable "service_name" {
  description = "Globally unique public app name; also used as a prefix for the dedicated SRE resources."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,37}[a-z0-9]$", var.service_name))
    error_message = "Use 3-39 lowercase letters, digits, or internal hyphens, beginning with a letter."
  }
}
variable "location" {
  description = "Azure region supporting Linux Premium v3 capacity (and zones if enabled)."
  type        = string
  default     = "eastus"
}
variable "container" {
  description = "Public registry HTTPS URL, repository:tag, and HTTP listen port of the release. Use a release-specific immutable tag."
  type        = object({ registry_url = optional(string, "https://index.docker.io"), image = string, port = optional(number, 8080) })
  validation {
    condition     = can(regex("^https://[A-Za-z0-9.-]+(:[0-9]+)?$", var.container.registry_url)) && can(regex("^[a-z0-9._/-]+:[A-Za-z0-9_.-]+$", var.container.image)) && var.container.port >= 1 && var.container.port <= 65535 && floor(var.container.port) == var.container.port
    error_message = "Provide an HTTPS registry origin (no trailing slash), a tagged image, and a valid integer port."
  }
}
variable "health_path" {
  description = "Unauthenticated readiness endpoint returning HTTP 200 when the container can serve traffic."
  type        = string
  default     = "/health"
  validation {
    condition     = startswith(var.health_path, "/") && !can(regex("[[:space:]?#]", var.health_path))
    error_message = "Use an absolute URL path without whitespace, query, or fragment."
  }
}
variable "capacity" {
  description = "Baseline and maximum plan workers. Equal values select fixed capacity. Zone spread requires a supported region and at least two workers."
  type        = object({ sku = optional(string, "P1v3"), minimum = optional(number, 2), maximum = optional(number, 4), zone_redundant = optional(bool, false) })
  default     = {}
  validation {
    condition     = contains(["P1v3", "P2v3", "P3v3"], var.capacity.sku) && floor(var.capacity.minimum) == var.capacity.minimum && floor(var.capacity.maximum) == var.capacity.maximum && var.capacity.minimum >= (var.capacity.zone_redundant ? 2 : 1) && var.capacity.maximum >= var.capacity.minimum && var.capacity.maximum <= 30
    error_message = "Use a supported Premium v3 SKU and ordered whole worker counts in 1..30 (minimum 2 for zones)."
  }
}
variable "candidate_image" {
  description = "Optional tagged candidate in the same registry. Creates a staging slot with the same runtime contract and no routed production traffic."
  type        = string
  default     = null
  validation {
    condition     = var.candidate_image == null || can(regex("^[a-z0-9._/-]+:[A-Za-z0-9_.-]+$", var.candidate_image))
    error_message = "Use a tagged image for the candidate."
  }
}
variable "app_settings" {
  description = "Application environment; use Key Vault references rather than plaintext secrets. Module runtime settings take precedence."
  type        = map(string)
  default     = {}
}
variable "alert_action_group_ids" {
  description = "Existing Azure Monitor action groups notified of production HTTP 5xx alerts."
  type        = set(string)
  default     = []
}
variable "tags" {
  type        = map(string)
  description = "Tags for resources owned by this service."
  default     = {}
}
