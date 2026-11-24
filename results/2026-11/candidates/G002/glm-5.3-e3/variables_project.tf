# =========================================================================
# Project
# =========================================================================
# Explicit rather than inherited from the provider: the network name in
# var.network has to be expanded into a self link against the project, and
# "which project" should never be a guess. This is the project that owns the
# apps-* VPC networks and hosts the instances.

variable "project" {
  description = "Project that owns the apps-* networks and hosts the instance. The Google provider should be configured for the same project."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}$", var.project))
    error_message = "The project must be a project id, for example 'acme-apps'."
  }
}
