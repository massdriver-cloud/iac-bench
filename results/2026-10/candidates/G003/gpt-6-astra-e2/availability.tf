variable "enable_public_availability_test" {
  description = "Probe production readiness from three Azure locations and alert when two fail. Disable explicitly for allowlisted APIs and supply an internal synthetic check instead."
  type        = bool
  default     = true
}

resource "azurerm_application_insights_standard_web_test" "production" {
  count                   = var.enable_public_availability_test ? 1 : 0
  name                    = "${var.name}-readiness"
  resource_group_name     = azurerm_resource_group.this.name
  location                = azurerm_resource_group.this.location
  application_insights_id = azurerm_application_insights.app["production"].id
  geo_locations           = ["emea-nl-ams-azr", "emea-gb-db3-azr", "us-va-ash-azr"]
  frequency               = 300
  timeout                 = 30
  enabled                 = true
  retry_enabled           = true
  tags                    = local.tags

  request {
    url                              = "https://${azurerm_linux_web_app.production.default_hostname}${var.health_check_path}"
    http_verb                        = "GET"
    follow_redirects_enabled         = false
    parse_dependent_requests_enabled = false
  }

  validation_rules {
    expected_status_code        = 200
    ssl_check_enabled           = true
    ssl_cert_remaining_lifetime = 14
  }

  lifecycle {
    precondition {
      condition     = length(var.ingress_cidrs) == 0
      error_message = "The standard public availability check requires public ingress. Set enable_public_availability_test=false for an allowlisted API and configure an internal synthetic check."
    }
  }
}

resource "azurerm_monitor_metric_alert" "availability" {
  count               = var.enable_public_availability_test ? 1 : 0
  name                = "${var.name}-availability"
  resource_group_name = azurerm_resource_group.this.name
  scopes = [
    azurerm_application_insights_standard_web_test.production[0].id,
    azurerm_application_insights.app["production"].id
  ]
  description   = "Production readiness or TLS validation failed from at least two probe locations. Check App Service health, container startup, dependencies and the latest rollout."
  severity      = 1
  frequency     = "PT1M"
  window_size   = "PT5M"
  auto_mitigate = true
  tags          = local.tags

  application_insights_web_test_location_availability_criteria {
    web_test_id           = azurerm_application_insights_standard_web_test.production[0].id
    component_id          = azurerm_application_insights.app["production"].id
    failed_location_count = 2
  }
  action {
    action_group_id = azurerm_monitor_action_group.sre.id
  }
}
