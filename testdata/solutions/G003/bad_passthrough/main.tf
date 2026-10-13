terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

variable "resource_group_name" { type = string }
variable "location" {
  type    = string
  default = "eastus"
}
variable "plan_name" { type = string }
variable "app_name" { type = string }
variable "sku_name" {
  type    = string
  default = "P1v3"
}
variable "worker_count" {
  type    = number
  default = 1
}
variable "zone_balancing_enabled" {
  type    = bool
  default = false
}
variable "https_only" {
  type    = bool
  default = false
}
variable "ftp_publish_basic_authentication_enabled" {
  type    = bool
  default = true
}
variable "webdeploy_publish_basic_authentication_enabled" {
  type    = bool
  default = true
}
variable "minimum_tls_version" {
  type    = string
  default = "1.2"
}
variable "scm_minimum_tls_version" {
  type    = string
  default = "1.2"
}
variable "ftps_state" {
  type    = string
  default = "Disabled"
}
variable "remote_debugging_enabled" {
  type    = bool
  default = false
}
variable "use_32_bit_worker" {
  type    = bool
  default = true
}
variable "http2_enabled" {
  type    = bool
  default = false
}
variable "load_balancing_mode" {
  type    = string
  default = "LeastRequests"
}
variable "always_on" {
  type    = bool
  default = true
}
variable "health_check_path" {
  type    = string
  default = null
}
variable "docker_image_name" { type = string }
variable "docker_registry_url" {
  type    = string
  default = "https://mcr.microsoft.com"
}
variable "app_settings" {
  type    = map(string)
  default = {}
}
variable "tags" {
  type    = map(string)
  default = {}
}

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_service_plan" "this" {
  name                   = var.plan_name
  resource_group_name    = azurerm_resource_group.this.name
  location               = azurerm_resource_group.this.location
  os_type                = "Linux"
  sku_name               = var.sku_name
  worker_count           = var.worker_count
  zone_balancing_enabled = var.zone_balancing_enabled
  tags                   = var.tags
}

resource "azurerm_linux_web_app" "this" {
  name                = var.app_name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  service_plan_id     = azurerm_service_plan.this.id

  https_only                                     = var.https_only
  ftp_publish_basic_authentication_enabled       = var.ftp_publish_basic_authentication_enabled
  webdeploy_publish_basic_authentication_enabled = var.webdeploy_publish_basic_authentication_enabled

  site_config {
    always_on                = var.always_on
    minimum_tls_version      = var.minimum_tls_version
    scm_minimum_tls_version  = var.scm_minimum_tls_version
    ftps_state               = var.ftps_state
    remote_debugging_enabled = var.remote_debugging_enabled
    use_32_bit_worker        = var.use_32_bit_worker
    http2_enabled            = var.http2_enabled
    load_balancing_mode      = var.load_balancing_mode
    health_check_path        = var.health_check_path

    application_stack {
      docker_image_name   = var.docker_image_name
      docker_registry_url = var.docker_registry_url
    }
  }

  app_settings = var.app_settings
  tags         = var.tags
}

output "app_name" {
  value = azurerm_linux_web_app.this.name
}
