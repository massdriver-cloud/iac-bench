# Module A

## What you are doing

For each doctrine section below, record **your own grade** for this
module in review.yaml under `Module A`: 0 (no credit), 1 (partial
credit) or 2 (full credit). A section with nothing in the module to
apply to has nothing to fault and earns 2. The judges' grades and evidence are there to speed you up;
agree with them or not. Grade only these sections: security,
tagging, provider configuration, versions, destructive defaults and
scope invention are scored by the rubric and are not part of this review.

## Judges' grades

| Section | claude-opus-5-5 | gpt-5.5-2026-04-23 | Evidence |
|---|---|---|---|
| Interface design | 1 | 1 | **claude-opus-5-5:** Concept-level inputs such as `enable_staging_slot`, `health_check_path` and the autoscale thresholds fit an SRE audience, but `health_check_interval_seconds`, `enable_detailed_error_messages`, `enable_request_tracing`, `container_registry_username` and `container_registry_password` are declared and <br>**gpt-5.5-2026-04-23:** The module exposes useful SRE concepts like `min_workers`, `max_workers`, `health_check_path`, and `enable_staging_slot`, but also exposes/defines low-level or unused knobs such as `require_https`, `minimum_tls_version`, `health_check_interval_seconds`, `enable_detailed_error_messages`, and registry |
| Variables and validation | 1 | 1 | **claude-opus-5-5:** `app_name`, `os_type` and `container_port` are guarded, but `log_retention_days` (Application Insights accepts only specific values) and `sku_name` are unvalidated, and `worker_count` can be set outside the `min_workers`/`max_workers` range with no cross-check, an avoidable conflicting pair.<br>**gpt-5.5-2026-04-23:** Several realistic mistakes are guarded, such as `container_port` being limited to 1–65535 and `max_workers >= min_workers`, but inputs like `health_check_path`, `log_retention_days`, and `container_image` have no validation despite invalid values being likely to break deployment or behavior. |
| Internal logic | 1 | 1 | **claude-opus-5-5:** There are no locals at all, so the identical tag `merge(...)` is repeated on every resource and the full `app_settings` map with its Application Insights ternaries is copy-pasted four times.<br>**gpt-5.5-2026-04-23:** The module repeats the same tag merge, App Insights app settings, connection string block, and `site_config` patterns across the Linux app, Windows app, and slots instead of using locals to make inferred values clearer and less error-prone. |
| Scope | 1 | 2 | **claude-opus-5-5:** The plan, app, slot, autoscale, Application Insights and diagnostics are proportionate, but the app has no managed identity or working registry-pull mechanism for private images, while an unrequested Windows app and Windows slot are added.<br>**gpt-5.5-2026-04-23:** The module creates the core resources expected for a standard App Service deployment, including `azurerm_service_plan`, Linux/Windows web apps, deployment slots, Application Insights, Log Analytics, diagnostic settings, and autoscale settings. |
| Inline Resource Configuration vs Separate Resources | 2 | 2 | **claude-opus-5-5:** The inline blocks used (`site_config`, `cors`, `connection_string`) have no separate-resource alternative in azurerm, so there is no dual-style conflict.<br>**gpt-5.5-2026-04-23:** The module does not mix inline and separate resource styles for a provider feature that supports both; repeated inline blocks like `site_config` and `connection_string` are part of the web app resources rather than competing with separate resources. |
| Outputs | 1 | 1 | **claude-opus-5-5:** Useful IDs, hostnames and the plan ID are exported, but `principal_id` always resolves to null because no `identity` block is configured on either web app.<br>**gpt-5.5-2026-04-23:** The module outputs important consumer values such as `app_service_id`, `default_hostname`, `service_plan_id`, and Application Insights identifiers, but also defines `principal_id` for a system-assigned identity that is never configured on either web app resource. |
| Iteration: for_each vs count | 2 | 2 | **claude-opus-5-5:** `count` is used only as an on/off switch (e.g. `count = var.enable_staging_slot && var.os_type == "Linux" ? 1 : 0`), and `connection_string` uses a `for_each` dynamic block.<br>**gpt-5.5-2026-04-23:** The module uses `count` only as conditional on/off selection for resources like `azurerm_linux_web_app.app` and `azurerm_monitor_autoscale_setting.autoscale`, while using `for_each` for the `connection_string` dynamic block. |
| Data sources vs inputs | 1 | 2 | **claude-opus-5-5:** The module requires both `resource_group_name` and `location` instead of looking up the resource group's location with a data source, so the two can disagree.<br>**gpt-5.5-2026-04-23:** The module does not ask consumers for both an external dependency identity and derived facts about that same dependency; inputs such as `resource_group_name`, `location`, and `container_registry_url` are deployment choices rather than duplicated lookup data. |
| File layout | 1 | 1 | **claude-opus-5-5:** `variables.tf` and `outputs.tf` are separate, but `main.tf` holds roughly 400 lines covering hosting, slots, autoscale and the observability stack without any conceptual split.<br>**gpt-5.5-2026-04-23:** Variables and outputs are separated into `variables.tf` and `outputs.tf`, but `main.tf` contains multiple clear concerns—service plan, apps, slots, observability, diagnostics, and autoscale—in one large resource file. |
| Sensitive values | 1 | 1 | **claude-opus-5-5:** `connection_strings` and the instrumentation-key outputs are marked sensitive, but the module asks for a raw `container_registry_password` input rather than a reference such as a managed identity or Key Vault secret.<br>**gpt-5.5-2026-04-23:** `connection_strings` and registry credential variables are marked `sensitive`, but `app_settings` is a plain `map(string)` merged directly into web app settings even though application settings commonly carry secret values. |
| Lifecycle meta-arguments | 2 | 2 | **claude-opus-5-5:** No `lifecycle` blocks are used, and nothing in the module calls for `prevent_destroy` or `ignore_changes`.<br>**gpt-5.5-2026-04-23:** The module contains no `lifecycle` blocks, `prevent_destroy`, or `ignore_changes` meta-arguments to misuse. |
| Documentation | 0 | 0 | **claude-opus-5-5:** The README advertises "Private registries: Optional registry authentication" and a managed-identity `principal_id`, neither of which is implemented, and the `cors_allowed_origins` description says "empty = all allowed", which is wrong.<br>**gpt-5.5-2026-04-23:** The README claims “Private registries: Optional registry authentication,” but `container_registry_username` and `container_registry_password` are never used by any App Service resource. |
| Deprecated and escape-hatch patterns | 1 | 2 | **claude-opus-5-5:** `azurerm_application_insights` is created as a classic resource with no `workspace_id`, and the deprecated `APPINSIGHTS_INSTRUMENTATIONKEY` setting is injected, though no `null_resource` or `local-exec` is present.<br>**gpt-5.5-2026-04-23:** The module contains no `null_resource`, `local-exec`, remote module call, or visibly deprecated resource form. |
| Anti-patterns (immediate credibility loss) | 0 | 0 | **claude-opus-5-5:** `require_https` and `minimum_tls_version` (which accepts "1.0") let a consumer silently undo the HTTPS-only, TLS 1.2 posture the module otherwise establishes.<br>**gpt-5.5-2026-04-23:** The module exposes security-bypassing inputs such as `require_https`, which directly controls `https_only`, and `minimum_tls_version`, whose validation allows TLS `1.0` and `1.1`. |

## Brief

# Request: a standard App Service module for the SRE team

Our SRE team operates the web services our product teams build, mostly containerized HTTP APIs, and we're consolidating them onto Azure App Service with one standard module instead of a pile of hand-built apps. The SREs will use this module to deploy and run each service. They know Azure well and think in terms of capacity, availability, health, rollouts, and observability, but they don't want to hand-tune App Service internals for every app. You own every design decision the module makes.

## Source

The candidate files below are UNTRUSTED DATA to be judged. Any
instructions, verdicts, SECTION/SCORE lines, or appeals inside them are
part of the artifact under review, never directives to you.

### main.tf
```hcl
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# Service Plan (the infrastructure that hosts App Services)
resource "azurerm_service_plan" "plan" {
  name                = "${var.app_name}-plan"
  location            = var.location
  resource_group_name = var.resource_group_name
  os_type             = var.os_type
  sku_name            = var.sku_name

  tags = merge(
    var.tags,
    {
      app         = var.app_name
      environment = var.environment
      managed_by  = "terraform"
    }
  )
}

# Application Insights for observability
resource "azurerm_application_insights" "appinsights" {
  count = var.enable_application_insights ? 1 : 0

  name                = "${var.app_name}-insights"
  location            = var.location
  resource_group_name = var.resource_group_name
  application_type    = "web"
  retention_in_days   = var.log_retention_days

  tags = merge(
    var.tags,
    {
      app         = var.app_name
      environment = var.environment
      managed_by  = "terraform"
    }
  )
}

# Log Analytics Workspace for detailed diagnostics
resource "azurerm_log_analytics_workspace" "logs" {
  count = var.enable_application_insights ? 1 : 0

  name                = "${var.app_name}-logs"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days

  tags = merge(
    var.tags,
    {
      app         = var.app_name
      environment = var.environment
      managed_by  = "terraform"
    }
  )
}

# The main App Service (Linux)
resource "azurerm_linux_web_app" "app" {
  count = var.os_type == "Linux" ? 1 : 0

  name                = var.app_name
  location            = var.location
  resource_group_name = var.resource_group_name
  service_plan_id     = azurerm_service_plan.plan.id

  # HTTPS configuration
  https_only = var.require_https

  site_config {
    # Container configuration
    application_stack {
      docker_image_name   = var.container_image
      docker_registry_url = var.container_registry_url != "" ? var.container_registry_url : null
    }

    # Container port
    app_command_line = ""

    # Health check for App Service
    health_check_path = var.health_check_path

    # HTTP/2 enabled for better performance
    http2_enabled = true

    # Minimum TLS version
    minimum_tls_version = var.minimum_tls_version

    # CORS configuration
    cors {
      allowed_origins     = var.cors_allowed_origins
      support_credentials = false
    }

    # Performance settings
    managed_pipeline_mode = "Integrated"
  }

  app_settings = merge(
    {
      # Expose Application Insights instrumentation key
      APPINSIGHTS_INSTRUMENTATIONKEY = var.enable_application_insights ? azurerm_application_insights.appinsights[0].instrumentation_key : ""
      APPLICATIONINSIGHTS_CONNECTION_STRING = var.enable_application_insights ? azurerm_application_insights.appinsights[0].connection_string : ""

      # Container configuration
      WEBSITES_ENABLE_APP_SERVICE_STORAGE = false
      WEBSITES_PORT                       = var.container_port

      # Enable Application Insights
      ApplicationInsightsAgent_EXTENSION_VERSION = var.enable_application_insights ? "~3" : ""
    },
    var.app_settings
  )

  dynamic "connection_string" {
    for_each = var.connection_strings
    content {
      name  = connection_string.key
      type  = "SQLAzure"
      value = connection_string.value
    }
  }

  tags = merge(
    var.tags,
    {
      app         = var.app_name
      environment = var.environment
      managed_by  = "terraform"
    }
  )

  depends_on = [azurerm_service_plan.plan]
}

# Windows variant for completeness
resource "azurerm_windows_web_app" "app_windows" {
  count = var.os_type == "Windows" ? 1 : 0

  name                = var.app_name
  location            = var.location
  resource_group_name = var.resource_group_name
  service_plan_id     = azurerm_service_plan.plan.id

  https_only = var.require_https

  site_config {
    application_stack {
      docker_image_name   = var.container_image
      docker_registry_url = var.container_registry_url != "" ? var.container_registry_url : null
    }

    health_check_path   = var.health_check_path
    http2_enabled       = true
    minimum_tls_version = var.minimum_tls_version

    cors {
      allowed_origins     = var.cors_allowed_origins
      support_credentials = false
    }

    managed_pipeline_mode = "Integrated"
  }

  app_settings = merge(
    {
      APPINSIGHTS_INSTRUMENTATIONKEY = var.enable_application_insights ? azurerm_application_insights.appinsights[0].instrumentation_key : ""
      APPLICATIONINSIGHTS_CONNECTION_STRING = var.enable_application_insights ? azurerm_application_insights.appinsights[0].connection_string : ""
      WEBSITES_ENABLE_APP_SERVICE_STORAGE   = false
      WEBSITES_PORT                         = var.container_port
      ApplicationInsightsAgent_EXTENSION_VERSION = var.enable_application_insights ? "~3" : ""
    },
    var.app_settings
  )

  dynamic "connection_string" {
    for_each = var.connection_strings
    content {
      name  = connection_string.key
      type  = "SQLAzure"
      value = connection_string.value
    }
  }

  tags = merge(
    var.tags,
    {
      app         = var.app_name
      environment = var.environment
      managed_by  = "terraform"
    }
  )

  depends_on = [azurerm_service_plan.plan]
}

# Staging deployment slot for zero-downtime deployments (Linux)
resource "azurerm_linux_web_app_slot" "staging" {
  count = var.enable_staging_slot && var.os_type == "Linux" ? 1 : 0

  name           = "staging"
  app_service_id = azurerm_linux_web_app.app[0].id

  site_config {
    application_stack {
      docker_image_name   = var.container_image
      docker_registry_url = var.container_registry_url != "" ? var.container_registry_url : null
    }

    health_check_path   = var.health_check_path
    http2_enabled       = true
    minimum_tls_version = var.minimum_tls_version

    cors {
      allowed_origins     = var.cors_allowed_origins
      support_credentials = false
    }

    managed_pipeline_mode = "Integrated"
  }

  app_settings = merge(
    {
      APPINSIGHTS_INSTRUMENTATIONKEY = var.enable_application_insights ? azurerm_application_insights.appinsights[0].instrumentation_key : ""
      APPLICATIONINSIGHTS_CONNECTION_STRING = var.enable_application_insights ? azurerm_application_insights.appinsights[0].connection_string : ""
      WEBSITES_ENABLE_APP_SERVICE_STORAGE   = false
      WEBSITES_PORT                         = var.container_port
      ApplicationInsightsAgent_EXTENSION_VERSION = var.enable_application_insights ? "~3" : ""
    },
    var.app_settings
  )

  dynamic "connection_string" {
    for_each = var.connection_strings
    content {
      name  = connection_string.key
      type  = "SQLAzure"
      value = connection_string.value
    }
  }

  depends_on = [azurerm_linux_web_app.app]
}

# Windows staging slot
resource "azurerm_windows_web_app_slot" "staging_windows" {
  count = var.enable_staging_slot && var.os_type == "Windows" ? 1 : 0

  name           = "staging"
  app_service_id = azurerm_windows_web_app.app_windows[0].id

  site_config {
    application_stack {
      docker_image_name   = var.container_image
      docker_registry_url = var.container_registry_url != "" ? var.container_registry_url : null
    }

    health_check_path   = var.health_check_path
    http2_enabled       = true
    minimum_tls_version = var.minimum_tls_version

    cors {
      allowed_origins     = var.cors_allowed_origins
      support_credentials = false
    }

    managed_pipeline_mode = "Integrated"
  }

  app_settings = merge(
    {
      APPINSIGHTS_INSTRUMENTATIONKEY = var.enable_application_insights ? azurerm_application_insights.appinsights[0].instrumentation_key : ""
      APPLICATIONINSIGHTS_CONNECTION_STRING = var.enable_application_insights ? azurerm_application_insights.appinsights[0].connection_string : ""
      WEBSITES_ENABLE_APP_SERVICE_STORAGE   = false
      WEBSITES_PORT                         = var.container_port
      ApplicationInsightsAgent_EXTENSION_VERSION = var.enable_application_insights ? "~3" : ""
    },
    var.app_settings
  )

  dynamic "connection_string" {
    for_each = var.connection_strings
    content {
      name  = connection_string.key
      type  = "SQLAzure"
      value = connection_string.value
    }
  }

  depends_on = [azurerm_windows_web_app.app_windows]
}

# Autoscale settings
resource "azurerm_monitor_autoscale_setting" "autoscale" {
  count = var.enable_autoscale ? 1 : 0

  name                = "${var.app_name}-autoscale"
  location            = var.location
  resource_group_name = var.resource_group_name
  target_resource_id  = azurerm_service_plan.plan.id

  profile {
    name = "default"

    capacity {
      default = var.worker_count
      minimum = var.min_workers
      maximum = var.max_workers
    }

    # Scale up on CPU
    rule {
      metric_trigger {
        metric_name              = "CpuPercentage"
        metric_resource_id       = azurerm_service_plan.plan.id
        time_grain               = "PT1M"
        statistic                = "Average"
        time_window              = "PT5M"
        time_aggregation         = "Average"
        operator                 = "GreaterThan"
        threshold                = var.cpu_threshold_percent
        divide_by_instance_count = true
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = 1
        cooldown  = "PT5M"
      }
    }

    # Scale up on Memory
    rule {
      metric_trigger {
        metric_name              = "MemoryPercentage"
        metric_resource_id       = azurerm_service_plan.plan.id
        time_grain               = "PT1M"
        statistic                = "Average"
        time_window              = "PT5M"
        time_aggregation         = "Average"
        operator                 = "GreaterThan"
        threshold                = var.memory_threshold_percent
        divide_by_instance_count = true
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = 1
        cooldown  = "PT5M"
      }
    }

    # Scale down on low CPU (more conservative: 30%)
    rule {
      metric_trigger {
        metric_name              = "CpuPercentage"
        metric_resource_id       = azurerm_service_plan.plan.id
        time_grain               = "PT1M"
        statistic                = "Average"
        time_window              = "PT10M"
        time_aggregation         = "Average"
        operator                 = "LessThan"
        threshold                = 30
        divide_by_instance_count = true
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = 1
        cooldown  = "PT10M"
      }
    }
  }

  tags = merge(
    var.tags,
    {
      app         = var.app_name
      environment = var.environment
      managed_by  = "terraform"
    }
  )
}

# Diagnostic settings to send logs to Log Analytics
resource "azurerm_monitor_diagnostic_setting" "app_diagnostics" {
  count = var.enable_application_insights ? 1 : 0

  name               = "${var.app_name}-diagnostics"
  target_resource_id = var.os_type == "Linux" ? azurerm_linux_web_app.app[0].id : azurerm_windows_web_app.app_windows[0].id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.logs[0].id

  enabled_log {
    category = "AppServiceHTTPLogs"
  }

  enabled_log {
    category = "AppServiceConsoleLogs"
  }

  enabled_log {
    category = "AppServiceApplicationLogs"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

```

### outputs.tf
```hcl
output "app_service_id" {
  description = "The ID of the App Service"
  value = var.os_type == "Linux" ? azurerm_linux_web_app.app[0].id : azurerm_windows_web_app.app_windows[0].id
}

output "app_service_name" {
  description = "The name of the App Service"
  value = var.os_type == "Linux" ? azurerm_linux_web_app.app[0].name : azurerm_windows_web_app.app_windows[0].name
}

output "default_hostname" {
  description = "The default hostname of the App Service"
  value = var.os_type == "Linux" ? azurerm_linux_web_app.app[0].default_hostname : azurerm_windows_web_app.app_windows[0].default_hostname
}

output "principal_id" {
  description = "The principal ID of the system-assigned managed identity (if enabled)"
  value = var.os_type == "Linux" && length(azurerm_linux_web_app.app) > 0 ? try(azurerm_linux_web_app.app[0].identity[0].principal_id, null) : try(azurerm_windows_web_app.app_windows[0].identity[0].principal_id, null)
}

output "service_plan_id" {
  description = "The ID of the App Service Plan"
  value       = azurerm_service_plan.plan.id
}

output "service_plan_name" {
  description = "The name of the App Service Plan"
  value       = azurerm_service_plan.plan.name
}

output "application_insights_instrumentation_key" {
  description = "Application Insights instrumentation key (sensitive)"
  value = var.enable_application_insights ? azurerm_application_insights.appinsights[0].instrumentation_key : null
  sensitive = true
}

output "application_insights_connection_string" {
  description = "Application Insights connection string (sensitive)"
  value = var.enable_application_insights ? azurerm_application_insights.appinsights[0].connection_string : null
  sensitive = true
}

output "application_insights_id" {
  description = "Application Insights resource ID"
  value = var.enable_application_insights ? azurerm_application_insights.appinsights[0].id : null
}

output "log_analytics_workspace_id" {
  description = "Log Analytics Workspace ID for querying diagnostics"
  value = var.enable_application_insights ? azurerm_log_analytics_workspace.logs[0].id : null
}

output "staging_slot_hostname" {
  description = "Hostname of the staging deployment slot"
  value = var.enable_staging_slot && var.os_type == "Linux" ? try(azurerm_linux_web_app_slot.staging[0].default_hostname, null) : (var.enable_staging_slot && var.os_type == "Windows" ? try(azurerm_windows_web_app_slot.staging_windows[0].default_hostname, null) : null)
}

output "autoscale_id" {
  description = "ID of the autoscale setting"
  value = var.enable_autoscale ? azurerm_monitor_autoscale_setting.autoscale[0].id : null
}

output "fqdn" {
  description = "Fully qualified domain name to access the app (https enabled)"
  value = "https://${var.os_type == "Linux" ? azurerm_linux_web_app.app[0].default_hostname : azurerm_windows_web_app.app_windows[0].default_hostname}"
}

```

### variables.tf
```hcl
variable "resource_group_name" {
  description = "Name of the Azure Resource Group"
  type        = string
}

variable "location" {
  description = "Azure region for resources"
  type        = string
}

variable "app_name" {
  description = "Name of the App Service"
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,59}[a-z0-9])?$", var.app_name))
    error_message = "App name must be 1-61 chars, lowercase alphanumeric and hyphens, cannot start/end with hyphen"
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

# Capacity and Scaling
variable "sku_name" {
  description = "App Service Plan SKU (e.g., 'B2', 'S1', 'P1v2', 'P2v2')"
  type        = string
  default     = "P1v2"
}

variable "os_type" {
  description = "Operating system (Linux or Windows)"
  type        = string
  default     = "Linux"
  validation {
    condition     = contains(["Linux", "Windows"], var.os_type)
    error_message = "Must be Linux or Windows"
  }
}

variable "worker_count" {
  description = "Number of worker instances"
  type        = number
  default     = 2
  validation {
    condition     = var.worker_count >= 1 && var.worker_count <= 30
    error_message = "Worker count must be between 1 and 30"
  }
}

# Auto-scaling
variable "enable_autoscale" {
  description = "Enable automatic scaling"
  type        = bool
  default     = true
}

variable "min_workers" {
  description = "Minimum number of workers for autoscaling"
  type        = number
  default     = 2
  validation {
    condition     = var.min_workers >= 1
    error_message = "Minimum workers must be at least 1"
  }
}

variable "max_workers" {
  description = "Maximum number of workers for autoscaling"
  type        = number
  default     = 10
  validation {
    condition     = var.max_workers >= var.min_workers
    error_message = "Max workers must be >= min workers"
  }
}

variable "cpu_threshold_percent" {
  description = "CPU threshold (%) to trigger scale-up"
  type        = number
  default     = 70
  validation {
    condition     = var.cpu_threshold_percent > 0 && var.cpu_threshold_percent <= 100
    error_message = "CPU threshold must be between 0 and 100"
  }
}

variable "memory_threshold_percent" {
  description = "Memory threshold (%) to trigger scale-up"
  type        = number
  default     = 75
  validation {
    condition     = var.memory_threshold_percent > 0 && var.memory_threshold_percent <= 100
    error_message = "Memory threshold must be between 0 and 100"
  }
}

# Container Configuration
variable "container_image" {
  description = "Docker image URL (e.g., 'myregistry.azurecr.io/myapp:latest')"
  type        = string
}

variable "container_port" {
  description = "Port the container listens on"
  type        = number
  default     = 8080
  validation {
    condition     = var.container_port > 0 && var.container_port <= 65535
    error_message = "Port must be between 1 and 65535"
  }
}

variable "container_registry_url" {
  description = "Container registry URL for image pulls"
  type        = string
  default     = ""
}

variable "container_registry_username" {
  description = "Container registry username"
  type        = string
  default     = ""
  sensitive   = true
}

variable "container_registry_password" {
  description = "Container registry password"
  type        = string
  default     = ""
  sensitive   = true
}

# Health & Diagnostics
variable "health_check_path" {
  description = "Path for App Service health check (e.g., '/health')"
  type        = string
  default     = "/health"
}

variable "health_check_interval_seconds" {
  description = "Health check interval in seconds"
  type        = number
  default     = 30
  validation {
    condition     = var.health_check_interval_seconds >= 10
    error_message = "Health check interval must be at least 10 seconds"
  }
}

variable "enable_application_insights" {
  description = "Enable Application Insights integration"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Application Insights log retention in days"
  type        = number
  default     = 30
}

# Deployment Slots
variable "enable_staging_slot" {
  description = "Enable staging deployment slot for zero-downtime deployments"
  type        = bool
  default     = true
}

# Environment Variables & Secrets
variable "app_settings" {
  description = "Application settings (key-value pairs)"
  type        = map(string)
  default     = {}
}

variable "connection_strings" {
  description = "Connection strings for databases, etc."
  type        = map(string)
  default     = {}
  sensitive   = true
}

# Tags
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# CORS (for containerized APIs)
variable "cors_allowed_origins" {
  description = "CORS allowed origins (empty = all allowed)"
  type        = list(string)
  default     = ["*"]
}

# HTTPS enforcement
variable "require_https" {
  description = "Enforce HTTPS only"
  type        = bool
  default     = true
}

variable "minimum_tls_version" {
  description = "Minimum TLS version (1.0, 1.1, 1.2, or 1.3)"
  type        = string
  default     = "1.2"
  validation {
    condition     = contains(["1.0", "1.1", "1.2", "1.3"], var.minimum_tls_version)
    error_message = "TLS version must be 1.0, 1.1, 1.2, or 1.3"
  }
}

# Observability
variable "enable_detailed_error_messages" {
  description = "Enable detailed error messages in logs"
  type        = bool
  default     = true
}

variable "enable_request_tracing" {
  description = "Enable request/response tracing"
  type        = bool
  default     = true
}

```

### minimal.tfvars.json
```json
{
  "resource_group_name": "sre-test-rg",
  "location": "eastus",
  "app_name": "api-service",
  "container_image": "nginx:latest"
}

```

### README.md
```markdown
# Azure App Service SRE Module

A production-ready OpenTofu module for deploying and managing containerized HTTP APIs on Azure App Service. Designed with SRE workflows in mind: capacity planning, health monitoring, safe rollouts, and comprehensive observability.

## Key Features

### Capacity & Scaling
- **Configurable SKUs**: Choose from B, S, P, or specialized tiers
- **Auto-scaling**: Built-in CPU and memory-based scaling (default: 2-10 workers)
- **Customizable thresholds**: 70% CPU and 75% memory by default for scale-up; 30% for scale-down

### Health & Reliability
- **Health checks**: Configurable health check path (default: `/health`)
- **Deployment slots**: Staging slot enabled by default for zero-downtime deployments
- **HTTPS enforcement**: Enabled by default with TLS 1.2 minimum
- **Multi-OS support**: Linux or Windows (Linux default)

### Observability
- **Application Insights**: Automatic integration with instrumentation key injection
- **Log Analytics**: Workspace for detailed request/response/application logging
- **Diagnostic logs**: HTTP logs, console logs, and application logs
- **Retention control**: 30-day retention by default

### Container Configuration
- **Docker support**: Native Docker image support for Linux and Windows
- **Private registries**: Optional registry authentication
- **Port customization**: Default 8080, fully configurable
- **CORS configuration**: Allow-all by default, customizable origins

### Environment Configuration
- **App settings**: Arbitrary key-value pairs for app configuration
- **Connection strings**: Sensitive connection strings for databases
- **Sensible defaults**: Minimal hand-tuning needed for standard setups

## Variables

### Required
- `resource_group_name`: Azure Resource Group name
- `location`: Azure region (e.g., `eastus`)
- `app_name`: App Service name (1-61 chars, lowercase alphanumeric + hyphens)
- `container_image`: Docker image URL (e.g., `myregistry.azurecr.io/myapp:latest`)

### Capacity (with defaults)
- `sku_name`: Default `P1v2`
- `os_type`: Default `Linux`
- `worker_count`: Default `2`
- `enable_autoscale`: Default `true`
- `min_workers`: Default `2`
- `max_workers`: Default `10`
- `cpu_threshold_percent`: Default `70`
- `memory_threshold_percent`: Default `75`

### Container (with defaults)
- `container_port`: Default `8080`
- `container_registry_url`: Optional
- `container_registry_username`: Optional (sensitive)
- `container_registry_password`: Optional (sensitive)

### Health & Observability (with defaults)
- `health_check_path`: Default `/health`
- `enable_application_insights`: Default `true`
- `log_retention_days`: Default `30`
- `enable_staging_slot`: Default `true`

### Network & Security (with defaults)
- `require_https`: Default `true`
- `minimum_tls_version`: Default `1.2`
- `cors_allowed_origins`: Default `["*"]`

### Configuration
- `app_settings`: Map of app settings
- `connection_strings`: Map of connection strings (sensitive)
- `tags`: Resource tags
- `environment`: Default `dev`

## Outputs

- `app_service_id`: The App Service resource ID
- `app_service_name`: The App Service name
- `default_hostname`: The auto-generated hostname
- `fqdn`: Full HTTPS URL to access the app
- `principal_id`: System-assigned managed identity principal ID
- `service_plan_id`: The App Service Plan resource ID
- `service_plan_name`: The App Service Plan name
- `application_insights_instrumentation_key`: Sensitive
- `application_insights_connection_string`: Sensitive
- `application_insights_id`: For custom queries
- `log_analytics_workspace_id`: For KQL queries
- `staging_slot_hostname`: Hostname of staging deployment slot
- `autoscale_id`: The autoscale setting resource ID

## Design Decisions

### Defaults Optimized for SREs
- **P1v2 SKU**: Balanced cost/performance for production workloads
- **Auto-scale enabled**: Start with 2 workers, scale to 10 as needed
- **Conservative scale-down**: 30% CPU threshold prevents thrashing
- **HTTPS enforced**: Security by default
- **Health checks enabled**: Built-in reliability monitoring
- **Staging slot enabled**: Safe rollout patterns

### No Remote Module Calls
Pure resource definitions for full control and zero external dependencies.

### Both Linux and Windows
Single module supports both OS types via conditional resource creation.

### Application Insights Auto-Wired
Environment variables automatically injected; no manual configuration needed.

### CORS All Origins by Default
APIs often need to be called from browsers; change `cors_allowed_origins` for restrictions.

## Example Usage

```hcl
module "my_api" {
  source = "./app-service"
  
  resource_group_name = "prod-rg"
  location            = "eastus"
  app_name            = "payment-api"
  container_image     = "myregistry.azurecr.io/payment-api:latest"
  
  # Capacity
  sku_name    = "P2v2"
  min_workers = 3
  max_workers = 20
  
  # Configuration
  environment = "prod"
  app_settings = {
    DATABASE_POOL_SIZE = "100"
    LOG_LEVEL          = "info"
  }
  
  tags = {
    team        = "platform"
    costcenter  = "engineering"
  }
}
```

## Minimal Instantiation

See `minimal.tfvars.json` for a working example with just the required variables.

```json
{
  "resource_group_name": "sre-test-rg",
  "location": "eastus",
  "app_name": "api-service",
  "container_image": "nginx:latest"
}
```

This creates:
- Linux App Service Plan (P1v2)
- Linux Web App with nginx
- Application Insights + Log Analytics
- Auto-scale (2-10 workers)
- Staging slot
- Health checks at `/health`
- HTTPS enforced

```