# ------------------------------------------------------------------------------
# Standard App Service module for the SRE team.
#
# This module provisions an Azure App Service (Linux, containerized) with:
#   - Capacity / autoscaling (scale-out rules per SRE policy)
#   - Availability (zone redundancy, always-on, health checks)
#   - Health (HTTP health check path with tuned thresholds)
#   - Rollouts (deployment slots + sensible site config)
#   - Observability (diagnostic settings -> Log Analytics + app insights)
#
# The SREs think in capacity/availability/health/rollouts/observability terms;
# this module hides App Service internals behind those knobs.
# ------------------------------------------------------------------------------

terraform {
  required_version = ">= 1.3"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}