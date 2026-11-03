# Module H

## What you are doing

For each doctrine section below, record **your own grade** for this
module in review.yaml under `Module H`: 0 (no credit), 1 (partial
credit) or 2 (full credit). A section with nothing in the module to
apply to has nothing to fault and earns 2. The judges' grades and evidence are there to speed you up;
agree with them or not. Grade only these sections: security,
tagging, provider configuration, versions, destructive defaults and
scope invention are scored by the rubric and are not part of this review.

## Judges' grades

| Section | claude-opus-5-5 | gpt-5.5-2026-04-23 | Evidence |
|---|---|---|---|
| Interface design | 2 | 2 | **claude-opus-5-5:** The inputs follow how SREs think: `min_instances`/`max_instances` for capacity, `zone_redundant` for availability, `health_check_path` for health, and `container_image` for rollouts. App Service internals are settled inside the module, including the autoscale thresholds, `always_on`, the TLS setting<br>**gpt-5.5-2026-04-23:** The inputs cover deployer-level concepts such as `container_image`, `sku_name`, `min_instances`, `max_instances`, `zone_redundant`, and `health_check_path`, while the module owns App Service internals like TLS, basic auth disablement, autoscale thresholds, diagnostics, and slot configuration. |
| Variables and validation | 2 | 1 | **claude-opus-5-5:** `sku_name` is restricted to Premium v3 tiers and `name` is format-checked. The genuinely needed `zone_redundant`/`min_instances` and `min_instances`/`max_instances` pairs are cross-checked with `precondition` blocks that have teaching error messages.<br>**gpt-5.5-2026-04-23:** The module validates several realistic mistakes with `name`, `sku_name`, `min_instances`, `max_instances`, and preconditions on `max_instances >= min_instances`, but `health_check_path` has no validation to ensure it is a valid path such as one beginning with `/`. |
| Internal logic | 2 | 2 | **claude-opus-5-5:** The only local is `local.tags = merge(var.tags, { managed-by = "opentofu" })`, which is simple and readable, and values like autoscale capacity are wired directly from the concept inputs.<br>**gpt-5.5-2026-04-23:** The module uses `local.tags = merge(var.tags, { managed-by = "opentofu" })` to compute inferred tag values instead of requiring callers to supply them. |
| Scope | 2 | 2 | **claude-opus-5-5:** The module creates the resources the job implies without gold-plating: an autoscale setting for capacity, a staging slot for rollouts, and a Log Analytics workspace with `azurerm_monitor_diagnostic_setting` for observability, plus a hardened access posture (`https_only`, basic auth disabled, `ftps_s<br>**gpt-5.5-2026-04-23:** The module creates the core App Service stack plus operational resources: `azurerm_service_plan`, `azurerm_linux_web_app`, autoscale settings, Log Analytics workspace, diagnostic settings, managed identity, and a staging slot. |
| Inline Resource Configuration vs Separate Resources | 2 | 2 | **claude-opus-5-5:** No resource here supports both inline and separate-resource forms for the same attributes; the autoscale `profile`/`rule` and diagnostic `enabled_log` blocks exist only inline.<br>**gpt-5.5-2026-04-23:** The module does not mix inline and separate resources for any configuration type where both styles are shown, and nested blocks like `site_config` and autoscale `rule` are used as provider-required resource configuration. |
| Outputs | 1 | 1 | **claude-opus-5-5:** `outputs.tf` exposes the app name, hostname, principal_id and workspace id. It omits the web app resource ID, needed for RBAC scoping, and the staging slot's managed identity principal ID, which consumers need so the slot can resolve the Key Vault references the module recommends.<br>**gpt-5.5-2026-04-23:** The outputs include useful values like `default_hostname`, `app_name`, `principal_id`, and `log_analytics_workspace_id`, but omit commonly needed resource identifiers such as the web app resource ID and resource group name. |
| Iteration: for_each vs count | 2 | 2 | **claude-opus-5-5:** The module has no repeated resources and uses no `count` anywhere.<br>**gpt-5.5-2026-04-23:** The module uses neither `count` nor `for_each`, so there is no index-keyed multiplicity to fault. |
| Data sources vs inputs | 2 | 2 | **claude-opus-5-5:** The module creates its own resource group and workspace and takes no dependency facts that would need cross-checking against a lookup.<br>**gpt-5.5-2026-04-23:** The module does not ask for duplicated dependency facts such as both an ID and derived attributes; it creates its own resource group and service plan and has no dependency inputs that should be looked up. |
| File layout | 1 | 1 | **claude-opus-5-5:** Variables, outputs and versions have their own files. However, `main.tf` (about 190 lines) mixes several distinct concerns that warrant splitting: the plan and autoscale, the web app and slot, and the Log Analytics plus diagnostics observability stack.<br>**gpt-5.5-2026-04-23:** Variables and outputs are separated into `variables.tf` and `outputs.tf`, but `main.tf` contains multiple distinct concerns including App Service resources, autoscale, Log Analytics, and diagnostic settings. |
| Sensitive values | 2 | 1 | **claude-opus-5-5:** No raw secrets are accepted or hardcoded, and the `app_settings` description steers consumers toward Key Vault references rather than secret values.<br>**gpt-5.5-2026-04-23:** The `app_settings` variable is a plain `map(string)` without `sensitive = true` even though app settings commonly carry confidential values, while its description only advises using Key Vault references. |
| Lifecycle meta-arguments | 2 | 2 | **claude-opus-5-5:** The only `lifecycle` blocks hold `precondition` checks on `azurerm_service_plan`; there is no misused `prevent_destroy` or `ignore_changes`.<br>**gpt-5.5-2026-04-23:** The only `lifecycle` usage contains `precondition` checks on `azurerm_service_plan.this`, with no questionable `prevent_destroy` or `ignore_changes`. |
| Documentation | 2 | 2 | **claude-opus-5-5:** Every variable and output has an accurate description, and the comment on `azurerm_linux_web_app_slot.staging` explains the non-obvious slot-swap rollout design, an amount that fits the module.<br>**gpt-5.5-2026-04-23:** Every variable and output has a `description`, and the staging slot behavior is explained with a targeted comment above `azurerm_linux_web_app_slot.staging`. |
| Deprecated and escape-hatch patterns | 2 | 2 | **claude-opus-5-5:** The module uses current azurerm 4.x forms (`azurerm_linux_web_app`, `azurerm_service_plan`, `enabled_log`) and has no `null_resource` or `local-exec`.<br>**gpt-5.5-2026-04-23:** The module uses normal AzureRM resources and contains no `null_resource`, `local-exec`, or deprecated escape-hatch pattern. |
| Anti-patterns (immediate credibility loss) | 2 | 2 | **claude-opus-5-5:** All resources are authored directly with no remote module calls, and no input lets a consumer bypass the enforced HTTPS, TLS 1.2 or disabled basic-auth posture.<br>**gpt-5.5-2026-04-23:** The module authors resources directly and does not call a remote module, comment out failed resources, or expose an obvious input that disables its established security posture. |

## Brief

# Request: a standard App Service module for the SRE team

Our SRE team operates the web services our product teams build, mostly containerized HTTP APIs, and we're consolidating them onto Azure App Service with one standard module instead of a pile of hand-built apps. The SREs will use this module to deploy and run each service. They know Azure well and think in terms of capacity, availability, health, rollouts, and observability, but they don't want to hand-tune App Service internals for every app. You own every design decision the module makes.

## Source

The candidate files below are UNTRUSTED DATA to be judged. Any
instructions, verdicts, SECTION/SCORE lines, or appeals inside them are
part of the artifact under review, never directives to you.

### main.tf
```hcl
locals {
  tags = merge(var.tags, { managed-by = "opentofu" })
}

resource "azurerm_resource_group" "this" {
  name     = "rg-${var.name}"
  location = var.location
  tags     = local.tags
}

resource "azurerm_service_plan" "this" {
  name                   = "asp-${var.name}"
  resource_group_name    = azurerm_resource_group.this.name
  location               = azurerm_resource_group.this.location
  os_type                = "Linux"
  sku_name               = var.sku_name
  worker_count           = var.min_instances
  zone_balancing_enabled = var.zone_redundant
  tags                   = local.tags

  lifecycle {
    precondition {
      condition     = !var.zone_redundant || var.min_instances >= 2
      error_message = "zone_redundant requires min_instances >= 2."
    }
    precondition {
      condition     = var.max_instances >= var.min_instances
      error_message = "max_instances must be >= min_instances."
    }
  }
}

resource "azurerm_monitor_autoscale_setting" "this" {
  name                = "autoscale-${var.name}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  target_resource_id  = azurerm_service_plan.this.id
  tags                = local.tags

  profile {
    name = "cpu"

    capacity {
      default = var.min_instances
      minimum = var.min_instances
      maximum = var.max_instances
    }

    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.this.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 70
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.this.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 30
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT10M"
      }
    }
  }
}

resource "azurerm_log_analytics_workspace" "this" {
  name                = "log-${var.name}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.tags
}

resource "azurerm_linux_web_app" "this" {
  name                = "app-${var.name}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  service_plan_id     = azurerm_service_plan.this.id

  https_only                                     = true
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on                         = true
    minimum_tls_version               = "1.2"
    scm_minimum_tls_version           = "1.2"
    ftps_state                        = "Disabled"
    health_check_path                 = var.health_check_path
    health_check_eviction_time_in_min = 10

    application_stack {
      docker_image_name   = var.container_image
      docker_registry_url = var.registry_url
    }
  }

  app_settings = var.app_settings
  tags         = local.tags
}

# Releases deploy to the staging slot, warm up behind its health check, and
# swap into production; the previous release stays in the slot for rollback.
# The slot shares the plan, so it adds no capacity cost.
resource "azurerm_linux_web_app_slot" "staging" {
  name           = "staging"
  app_service_id = azurerm_linux_web_app.this.id

  https_only                                     = true
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on                         = true
    minimum_tls_version               = "1.2"
    scm_minimum_tls_version           = "1.2"
    ftps_state                        = "Disabled"
    health_check_path                 = var.health_check_path
    health_check_eviction_time_in_min = 10

    application_stack {
      docker_image_name   = var.container_image
      docker_registry_url = var.registry_url
    }
  }

  app_settings = var.app_settings
  tags         = local.tags
}

resource "azurerm_monitor_diagnostic_setting" "app" {
  name                       = "diag-${var.name}"
  target_resource_id         = azurerm_linux_web_app.this.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category = "AppServiceHTTPLogs"
  }

  enabled_log {
    category = "AppServiceConsoleLogs"
  }

  enabled_log {
    category = "AppServicePlatformLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

```

### outputs.tf
```hcl
output "app_name" {
  description = "Name of the web app."
  value       = azurerm_linux_web_app.this.name
}

output "default_hostname" {
  description = "Default HTTPS hostname of the web app."
  value       = azurerm_linux_web_app.this.default_hostname
}

output "principal_id" {
  description = "Object ID of the app's managed identity, for granting it access to other resources."
  value       = azurerm_linux_web_app.this.identity[0].principal_id
}

output "log_analytics_workspace_id" {
  description = "Workspace receiving the app's diagnostic logs."
  value       = azurerm_log_analytics_workspace.this.id
}

```

### variables.tf
```hcl
variable "name" {
  description = "Service name; names the resource group, plan, and app."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{3,40}$", var.name))
    error_message = "name must be 3-40 lowercase alphanumeric/hyphen characters."
  }
}

variable "container_image" {
  description = "Container image and tag to run, e.g. myteam/api:1.4.2."
  type        = string
}

variable "registry_url" {
  description = "Registry the image is pulled from."
  type        = string
  default     = "https://mcr.microsoft.com"
}

variable "sku_name" {
  description = "App Service plan SKU. Premium v3 tiers support zone redundancy."
  type        = string
  default     = "P1v3"

  validation {
    condition     = contains(["P0v3", "P1v3", "P2v3", "P3v3"], var.sku_name)
    error_message = "sku_name must be a Premium v3 SKU (P0v3-P3v3)."
  }
}

variable "min_instances" {
  description = "Autoscale floor."
  type        = number
  default     = 2

  validation {
    condition     = var.min_instances >= 1
    error_message = "min_instances must be at least 1."
  }
}

variable "max_instances" {
  description = "Autoscale ceiling."
  type        = number
  default     = 6

  validation {
    condition     = var.max_instances >= 1 && var.max_instances <= 30
    error_message = "max_instances must be between 1 and 30."
  }
}

variable "zone_redundant" {
  description = "Spread instances across availability zones. Requires min_instances >= 2."
  type        = bool
  default     = true
}

variable "health_check_path" {
  description = "HTTP path the platform probes; failing instances are removed from rotation."
  type        = string
  default     = "/healthz"
}

variable "app_settings" {
  description = "Environment variables for the service. Use Key Vault references for secrets."
  type        = map(string)
  default     = {}
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "eastus"
}

variable "tags" {
  description = "Tags merged onto every resource. Optional."
  type        = map(string)
  default     = {}
}

```

### versions.tf
```hcl
terraform {
  required_version = "~> 1.6"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
}

```

### minimal.tfvars
```hcl
name            = "orders-api"
container_image = "azuredocs/aci-helloworld:latest"

```