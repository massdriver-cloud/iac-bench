# Module E

## What you are doing

For each doctrine section below, record **your own grade** for this
module in review.yaml under `Module E`: 0 (no credit), 1 (partial
credit) or 2 (full credit). A section with nothing in the module to
apply to has nothing to fault and earns 2. The judges' grades and evidence are there to speed you up;
agree with them or not. Grade only these sections: security,
tagging, provider configuration, versions, destructive defaults and
scope invention are scored by the rubric and are not part of this review.

## Judges' grades

| Section | claude-opus-5-5 | gpt-5.5-2026-04-23 | Evidence |
|---|---|---|---|
| Interface design | 1 | 1 | **claude-opus-5-5:** The capacity, health, rollout and observability inputs (`plan_sku_name`, autoscale bounds, `health_check_path`, `enable_staging_slot`, `alert_action_group_ids`) suit SREs, but the module still exposes decisions the use case settles (`always_on`, whose own description says it "Should remain true for <br>**gpt-5.5-2026-04-23:** The module exposes several App Service internals such as `var.always_on`, `var.enable_app_service_storage`, and `var.app_settings` overriding `local.standard_app_settings`, which is more hand-tuning than the standard SRE-facing use case calls for. |
| Variables and validation | 1 | 1 | **claude-opus-5-5:** Names, port and `instance_count` are deliberately validated, but `log_retention_days` is unguarded although it also feeds App Insights retention (which accepts only specific values), and the avoidable `instance_count` vs `autoscale_min_instances`/`autoscale_max_instances` inputs can be set to confli<br>**gpt-5.5-2026-04-23:** Some inputs are validated, such as `var.container_port`, but routine breakage-prone inputs like `autoscale_min_instances`, `autoscale_max_instances`, autoscale thresholds, `log_retention_days`, and `health_check_eviction_time_in_minutes` have no validation or cross-checks. |
| Internal logic | 1 | 2 | **claude-opus-5-5:** The naming and tag locals are readable, but `log_analytics_name = "law-...-${local.suffix}"` ends in a trailing hyphen whenever `web_app_name` is set (because `suffix` is then ""), producing an invalid workspace name.<br>**gpt-5.5-2026-04-23:** `locals` cleanly derive names, common tags, standard app settings, and diagnostic log categories from concept inputs such as `service_name` and `environment`. |
| Scope | 2 | 2 | **claude-opus-5-5:** The plan, Linux web app, staging slot, Log Analytics, App Insights, diagnostic setting, CPU autoscale and 5xx/CPU alerts cover availability, rollout and observability proportionately, and HTTPS-only and disabled basic auth set the access posture.<br>**gpt-5.5-2026-04-23:** The module creates the core App Service resources plus managed identity, staging slot, Log Analytics, Application Insights, diagnostic settings, autoscale, and metric alerts, which fit the requested standard App Service operating bundle. |
| Inline Resource Configuration vs Separate Resources | 2 | 2 | **claude-opus-5-5:** The inline blocks used (`connection_string`, autoscale `profile`, alert `action`) have no separate-resource alternative in azurerm, and no attribute is configured in both styles.<br>**gpt-5.5-2026-04-23:** The module does not mix inline and separate resources for the same configurable attributes; nested blocks like `connection_string` and `cors` appear only inside the web app resources. |
| Outputs | 2 | 2 | **claude-opus-5-5:** The outputs cover what consumers need, including `web_app_id`, `default_hostname`, `url`, `principal_id`, `service_plan_id`, `log_analytics_workspace_id` and the slot hostname, without dumping every attribute.<br>**gpt-5.5-2026-04-23:** Outputs include practical consumer values such as `web_app_id`, `default_hostname`, `url`, `principal_id`, `service_plan_id`, `log_analytics_workspace_id`, and staging slot host/name values. |
| Iteration: for_each vs count | 2 | 2 | **claude-opus-5-5:** `count` is used only as an on/off switch (`var.enable_staging_slot ? 1 : 0`, `var.enable_autoscale ? 1 : 0`), and the repeated blocks use `for_each` over `toset(...)`.<br>**gpt-5.5-2026-04-23:** `count` is used only as an on/off switch for resources like `azurerm_linux_web_app_slot.staging` and `azurerm_monitor_autoscale_setting.service_plan_cpu`, while repeated dynamic entries use `for_each`. |
| Data sources vs inputs | 2 | 2 | **claude-opus-5-5:** Dependencies are taken by identity only (`alert_action_group_ids`, `resource_group_name`), and the module never asks for derived facts that a lookup should supply.<br>**gpt-5.5-2026-04-23:** The module does not require paired dependency facts that could conflict, such as asking for both an Azure resource ID and separately supplied derived facts about that same dependency. |
| File layout | 1 | 1 | **claude-opus-5-5:** `variables.tf`, `outputs.tf` and `versions.tf` are separated, but `main.tf` holds roughly 350 lines mixing the app/slot, monitoring, autoscale and alerting concerns with no conceptual split.<br>**gpt-5.5-2026-04-23:** Variables and outputs are separated, but `main.tf` combines multiple clear concerns including App Service, Log Analytics/Application Insights, autoscale, and metric alerts in one resource file. |
| Sensitive values | 1 | 2 | **claude-opus-5-5:** The registry password, `app_settings`, `connection_strings` and the App Insights connection-string output are marked `sensitive`, but private registry access is offered only through raw `container_registry_username`/`container_registry_password` rather than the managed-identity pull the app's `Syste<br>**gpt-5.5-2026-04-23:** Secret-bearing inputs such as `container_registry_password`, `app_settings`, and `connection_strings` are marked `sensitive = true`, and the Application Insights connection string output is also sensitive. |
| Lifecycle meta-arguments | 2 | 2 | **claude-opus-5-5:** No `lifecycle` blocks are used, so nothing misapplies `prevent_destroy` or `ignore_changes`.<br>**gpt-5.5-2026-04-23:** The module contains no `lifecycle` blocks using `prevent_destroy` or `ignore_changes`. |
| Documentation | 1 | 2 | **claude-opus-5-5:** Every variable and output has a description, but there is no README and no comments explaining non-obvious interplay such as `instance_count` vs autoscale, and the `container_registry_username` description promises outside-configured managed registry access that the module does not support.<br>**gpt-5.5-2026-04-23:** Every declared variable in `variables.tf` and every output in `outputs.tf` has a description. |
| Deprecated and escape-hatch patterns | 2 | 2 | **claude-opus-5-5:** The module uses current resource forms (`azurerm_linux_web_app`, `azurerm_service_plan`, `enabled_log`/`enabled_metric`) and contains no `null_resource` or `local-exec`.<br>**gpt-5.5-2026-04-23:** The module contains no `null_resource`, `local-exec`, or obvious deprecated resource forms. |
| Anti-patterns (immediate credibility loss) | 2 | 2 | **claude-opus-5-5:** All resources are authored directly, with no remote module call and no input that bypasses the HTTPS/TLS/basic-auth posture.<br>**gpt-5.5-2026-04-23:** The module authors Azure resources directly and does not call a remote module or delete/comment out errored resources. |

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
  workload_name = lower("${var.service_name}-${var.environment}")
  rg_name       = coalesce(var.resource_group_name, "rg-${local.workload_name}")
  suffix        = var.web_app_name == null ? random_string.suffix[0].result : ""

  web_app_name = coalesce(
    var.web_app_name,
    "app-${substr(local.workload_name, 0, 49)}-${local.suffix}"
  )

  log_analytics_name        = "law-${substr(local.workload_name, 0, 50)}-${local.suffix}"
  application_insights_name = "appi-${substr(local.workload_name, 0, 50)}"
  service_plan_name         = "asp-${substr(local.workload_name, 0, 50)}"

  common_tags = merge(
    {
      service     = var.service_name
      environment = var.environment
      managed_by  = "opentofu"
      module      = "standard-app-service"
    },
    var.tags
  )

  standard_app_settings = {
    WEBSITES_ENABLE_APP_SERVICE_STORAGE   = tostring(var.enable_app_service_storage)
    WEBSITES_PORT                         = tostring(var.container_port)
    APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.main.connection_string
    APPINSIGHTS_INSTRUMENTATIONKEY        = azurerm_application_insights.main.instrumentation_key
    SLOT_NAME                             = "production"
  }

  app_settings = merge(local.standard_app_settings, var.app_settings)

  app_service_diagnostic_log_categories = [
    "AppServiceHTTPLogs",
    "AppServiceConsoleLogs",
    "AppServiceAppLogs",
    "AppServiceAuditLogs",
    "AppServiceIPSecAuditLogs",
    "AppServicePlatformLogs"
  ]
}

resource "random_string" "suffix" {
  count   = var.web_app_name == null ? 1 : 0
  length  = 6
  upper   = false
  special = false

  keepers = {
    service_name = var.service_name
    environment  = var.environment
  }
}

resource "azurerm_resource_group" "main" {
  count    = var.create_resource_group ? 1 : 0
  name     = local.rg_name
  location = var.location
  tags     = local.common_tags
}

resource "azurerm_log_analytics_workspace" "main" {
  name                = local.log_analytics_name
  location            = var.location
  resource_group_name = local.rg_name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = local.common_tags

  depends_on = [azurerm_resource_group.main]
}

resource "azurerm_application_insights" "main" {
  name                                 = local.application_insights_name
  location                             = var.location
  resource_group_name                  = local.rg_name
  workspace_id                         = azurerm_log_analytics_workspace.main.id
  application_type                     = "web"
  daily_data_cap_in_gb                 = var.application_insights_daily_cap_gb
  daily_data_cap_notifications_enabled = false
  retention_in_days                    = var.log_retention_days
  tags                                 = local.common_tags
}

resource "azurerm_service_plan" "main" {
  name                = local.service_plan_name
  location            = var.location
  resource_group_name = local.rg_name
  os_type             = "Linux"
  sku_name            = var.plan_sku_name
  worker_count        = var.instance_count
  tags                = local.common_tags

  depends_on = [azurerm_resource_group.main]
}

resource "azurerm_linux_web_app" "main" {
  name                = local.web_app_name
  location            = var.location
  resource_group_name = local.rg_name
  service_plan_id     = azurerm_service_plan.main.id

  https_only                                     = true
  client_affinity_enabled                        = false
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  app_settings                                   = local.app_settings
  tags                                           = local.common_tags

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on                         = var.always_on
    ftps_state                        = "Disabled"
    http2_enabled                     = true
    minimum_tls_version               = "1.2"
    scm_minimum_tls_version           = "1.2"
    use_32_bit_worker                 = false
    health_check_path                 = var.health_check_path
    health_check_eviction_time_in_min = var.health_check_path == null ? null : var.health_check_eviction_time_in_minutes

    application_stack {
      docker_image_name        = var.container_image
      docker_registry_url      = var.container_registry_url
      docker_registry_username = var.container_registry_username
      docker_registry_password = var.container_registry_password
    }

    dynamic "cors" {
      for_each = length(var.allowed_origins) > 0 ? [1] : []
      content {
        allowed_origins     = var.allowed_origins
        support_credentials = false
      }
    }
  }

  dynamic "connection_string" {
    for_each = var.connection_strings
    content {
      name  = connection_string.value.name
      type  = connection_string.value.type
      value = connection_string.value.value
    }
  }
}

resource "azurerm_linux_web_app_slot" "staging" {
  count          = var.enable_staging_slot ? 1 : 0
  name           = var.staging_slot_name
  app_service_id = azurerm_linux_web_app.main.id

  https_only                                     = true
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  app_settings                                   = merge(local.app_settings, { SLOT_NAME = var.staging_slot_name })
  tags                                           = local.common_tags

  site_config {
    always_on                         = var.always_on
    ftps_state                        = "Disabled"
    http2_enabled                     = true
    minimum_tls_version               = "1.2"
    scm_minimum_tls_version           = "1.2"
    use_32_bit_worker                 = false
    health_check_path                 = var.health_check_path
    health_check_eviction_time_in_min = var.health_check_path == null ? null : var.health_check_eviction_time_in_minutes

    application_stack {
      docker_image_name        = var.container_image
      docker_registry_url      = var.container_registry_url
      docker_registry_username = var.container_registry_username
      docker_registry_password = var.container_registry_password
    }

    dynamic "cors" {
      for_each = length(var.allowed_origins) > 0 ? [1] : []
      content {
        allowed_origins     = var.allowed_origins
        support_credentials = false
      }
    }
  }

  dynamic "connection_string" {
    for_each = var.connection_strings
    content {
      name  = connection_string.value.name
      type  = connection_string.value.type
      value = connection_string.value.value
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "web_app" {
  name                       = "diag-${local.web_app_name}"
  target_resource_id         = azurerm_linux_web_app.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  dynamic "enabled_log" {
    for_each = toset(local.app_service_diagnostic_log_categories)
    content {
      category = enabled_log.value
    }
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_autoscale_setting" "service_plan_cpu" {
  count               = var.enable_autoscale ? 1 : 0
  name                = "autoscale-${local.service_plan_name}"
  resource_group_name = local.rg_name
  location            = var.location
  target_resource_id  = azurerm_service_plan.main.id
  enabled             = true
  tags                = local.common_tags

  profile {
    name = "cpu"

    capacity {
      default = tostring(var.instance_count)
      minimum = tostring(var.autoscale_min_instances)
      maximum = tostring(var.autoscale_max_instances)
    }

    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.main.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = var.autoscale_cpu_scale_out_threshold
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
        metric_resource_id = azurerm_service_plan.main.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = var.autoscale_cpu_scale_in_threshold
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT10M"
      }
    }
  }

  depends_on = [azurerm_resource_group.main]
}

resource "azurerm_monitor_metric_alert" "web_app_5xx" {
  name                = "alert-${local.web_app_name}-5xx"
  resource_group_name = local.rg_name
  scopes              = [azurerm_linux_web_app.main.id]
  description         = "HTTP 5xx responses are elevated for ${local.web_app_name}."
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  enabled             = true
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "Http5xx"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 10
  }

  dynamic "action" {
    for_each = toset(var.alert_action_group_ids)
    content {
      action_group_id = action.value
    }
  }

  depends_on = [azurerm_resource_group.main]
}

resource "azurerm_monitor_metric_alert" "service_plan_cpu" {
  name                = "alert-${local.service_plan_name}-cpu"
  resource_group_name = local.rg_name
  scopes              = [azurerm_service_plan.main.id]
  description         = "App Service Plan CPU is high for ${local.service_plan_name}."
  severity            = 3
  frequency           = "PT1M"
  window_size         = "PT5M"
  enabled             = true
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.Web/serverfarms"
    metric_name      = "CpuPercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 85
  }

  dynamic "action" {
    for_each = toset(var.alert_action_group_ids)
    content {
      action_group_id = action.value
    }
  }

  depends_on = [azurerm_resource_group.main]
}

```

### outputs.tf
```hcl
output "resource_group_name" {
  description = "Resource group containing the service resources."
  value       = local.rg_name
}

output "web_app_name" {
  description = "Name of the production App Service app."
  value       = azurerm_linux_web_app.main.name
}

output "web_app_id" {
  description = "Resource ID of the production App Service app."
  value       = azurerm_linux_web_app.main.id
}

output "default_hostname" {
  description = "Default Azure hostname for the production app."
  value       = azurerm_linux_web_app.main.default_hostname
}

output "url" {
  description = "HTTPS URL for the production app default hostname."
  value       = "https://${azurerm_linux_web_app.main.default_hostname}"
}

output "principal_id" {
  description = "System-assigned managed identity principal ID for the production app."
  value       = azurerm_linux_web_app.main.identity[0].principal_id
}

output "service_plan_id" {
  description = "Resource ID of the Linux App Service Plan."
  value       = azurerm_service_plan.main.id
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace."
  value       = azurerm_log_analytics_workspace.main.id
}

output "application_insights_connection_string" {
  description = "Application Insights connection string for instrumentation."
  value       = azurerm_application_insights.main.connection_string
  sensitive   = true
}

output "staging_slot_name" {
  description = "Name of the staging deployment slot, when enabled."
  value       = var.enable_staging_slot ? azurerm_linux_web_app_slot.staging[0].name : null
}

output "staging_slot_default_hostname" {
  description = "Default hostname of the staging deployment slot, when enabled."
  value       = var.enable_staging_slot ? azurerm_linux_web_app_slot.staging[0].default_hostname : null
}

```

### variables.tf
```hcl
variable "service_name" {
  description = "Short product/service name. Used in Azure resource names and tags. Use lowercase letters, numbers, and hyphens."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$", var.service_name))
    error_message = "service_name must be 3-40 characters of lowercase letters, numbers, and hyphens, and must not start or end with a hyphen."
  }
}

variable "environment" {
  description = "Deployment environment name such as dev, test, staging, or prod. Used in names and tags."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,18}[a-z0-9]$", var.environment))
    error_message = "environment must be 3-20 characters of lowercase letters, numbers, and hyphens, and must not start or end with a hyphen."
  }
}

variable "location" {
  description = "Azure region where the service should be deployed."
  type        = string
}

variable "container_image" {
  description = "Container image name including tag, for example nginx:1.27-alpine or myteam/api:2024.10."
  type        = string
}

variable "container_registry_url" {
  description = "Container registry URL. Docker Hub public images use https://index.docker.io. Azure Container Registry uses https://<registry>.azurecr.io."
  type        = string
  default     = "https://index.docker.io"
}

variable "container_registry_username" {
  description = "Optional container registry username. Leave null for public images or managed registry access configured outside this module."
  type        = string
  default     = null
  sensitive   = true
}

variable "container_registry_password" {
  description = "Optional container registry password. Leave null for public images or managed registry access configured outside this module."
  type        = string
  default     = null
  sensitive   = true
}

variable "container_port" {
  description = "Port exposed by the container for HTTP traffic. Published to the app as WEBSITES_PORT."
  type        = number
  default     = 8080

  validation {
    condition     = var.container_port >= 1 && var.container_port <= 65535
    error_message = "container_port must be a valid TCP port."
  }
}

variable "health_check_path" {
  description = "HTTP path App Service uses for health checks. Set to null to disable App Service health checks."
  type        = string
  default     = "/health"
}

variable "health_check_eviction_time_in_minutes" {
  description = "Minutes of failed health checks before an unhealthy worker is removed from the load balancer."
  type        = number
  default     = 10
}

variable "plan_sku_name" {
  description = "SKU for the Linux App Service Plan. Production services normally use Premium v3 or better."
  type        = string
  default     = "P1v3"
}

variable "instance_count" {
  description = "Initial/manual worker count for the App Service Plan. Autoscale, when enabled, manages this inside the min/max range."
  type        = number
  default     = 2

  validation {
    condition     = var.instance_count >= 1 && var.instance_count <= 30
    error_message = "instance_count must be between 1 and 30."
  }
}

variable "always_on" {
  description = "Keep the app loaded even when idle. Should remain true for HTTP APIs."
  type        = bool
  default     = true
}

variable "enable_app_service_storage" {
  description = "Whether to mount persistent App Service storage into the container. Disabled by default for twelve-factor containerized APIs."
  type        = bool
  default     = false
}

variable "create_resource_group" {
  description = "Create a resource group for the service. Set false to deploy into an existing resource group named by resource_group_name."
  type        = bool
  default     = true
}

variable "resource_group_name" {
  description = "Existing or desired resource group name. When null, a standard name is generated."
  type        = string
  default     = null
}

variable "web_app_name" {
  description = "Optional explicit App Service app name. When null, a globally unique standard name is generated with a stable random suffix."
  type        = string
  default     = null
}

variable "log_retention_days" {
  description = "Retention in days for Log Analytics workspace data."
  type        = number
  default     = 30
}

variable "application_insights_daily_cap_gb" {
  description = "Daily data volume cap for Application Insights, in GB."
  type        = number
  default     = 5
}

variable "enable_autoscale" {
  description = "Create a CPU-based autoscale policy for the App Service Plan."
  type        = bool
  default     = true
}

variable "autoscale_min_instances" {
  description = "Minimum App Service Plan instance count when autoscale is enabled."
  type        = number
  default     = 2
}

variable "autoscale_max_instances" {
  description = "Maximum App Service Plan instance count when autoscale is enabled."
  type        = number
  default     = 5
}

variable "autoscale_cpu_scale_out_threshold" {
  description = "Average CPU percentage over the evaluation window that triggers scale out."
  type        = number
  default     = 70
}

variable "autoscale_cpu_scale_in_threshold" {
  description = "Average CPU percentage over the evaluation window that triggers scale in."
  type        = number
  default     = 35
}

variable "enable_staging_slot" {
  description = "Create a staging deployment slot for warm-up and swap rollouts."
  type        = bool
  default     = true
}

variable "staging_slot_name" {
  description = "Name for the deployment slot created when enable_staging_slot is true."
  type        = string
  default     = "staging"
}

variable "app_settings" {
  description = "Additional application settings exposed as environment variables. These override module-provided defaults when keys overlap."
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "connection_strings" {
  description = "Connection strings to attach to the app and deployment slot."
  type = list(object({
    name  = string
    type  = string
    value = string
  }))
  default   = []
  sensitive = true
}

variable "allowed_origins" {
  description = "Optional CORS allowed origins. Empty disables module-managed CORS."
  type        = list(string)
  default     = []
}

variable "alert_action_group_ids" {
  description = "Azure Monitor action group IDs used by module-created alerts. Empty creates alerts without notification actions."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags to apply to all supported resources."
  type        = map(string)
  default     = {}
}

```

### versions.tf
```hcl
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  features {}
}

```

### minimal.tfvars
```hcl
service_name      = "sample-api"
environment       = "dev"
location          = "eastus"
container_image   = "nginx:1.27-alpine"
container_port    = 80
health_check_path = "/"

```