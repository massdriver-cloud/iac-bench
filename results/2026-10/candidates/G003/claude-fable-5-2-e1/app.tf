# ---------------------------------------------------------------------------------------------
# Production app
#
# What is fixed for every service (not configurable on purpose):
#   - HTTPS only, TLS 1.2 minimum (also on the deployment site), HTTP/2 on
#   - FTP/FTPS off, basic-auth publishing credentials off (Entra ID only)
#   - user-assigned managed identity for registry pulls and Key Vault references
#   - always on, no ARR session affinity (stateless APIs behind a load balancer)
#   - health check with automatic eviction of failing instances
#
# The staging slot further down repeats this configuration verbatim: the two must stay identical,
# because a swap exchanges them.
# ---------------------------------------------------------------------------------------------

resource "azurerm_linux_web_app" "this" {
  name                = local.app_name
  resource_group_name = local.resource_group_name
  location            = var.location
  service_plan_id     = azurerm_service_plan.this.id
  tags                = local.tags

  https_only                                     = true
  client_affinity_enabled                        = false
  public_network_access_enabled                  = var.network.public_access_enabled
  virtual_network_subnet_id                      = var.network.integration_subnet_id
  vnet_image_pull_enabled                        = var.registry.pull_over_vnet
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  key_vault_reference_identity_id                = azurerm_user_assigned_identity.this.id

  # Initial release only. Afterwards the image and environment of production change exclusively by
  # swapping in a warmed-up staging slot (see "Rollouts" below), hence the ignore_changes.
  app_settings = local.app_settings

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.this.id]
  }

  site_config {
    always_on               = true
    http2_enabled           = true
    use_32_bit_worker       = false
    ftps_state              = "Disabled"
    minimum_tls_version     = "1.2"
    scm_minimum_tls_version = "1.2"
    vnet_route_all_enabled  = local.vnet_integrated

    health_check_path                 = var.health_check_path
    health_check_eviction_time_in_min = var.health_check_eviction_minutes

    container_registry_use_managed_identity       = local.use_acr
    container_registry_managed_identity_client_id = local.use_acr ? azurerm_user_assigned_identity.this.client_id : null

    ip_restriction_default_action = local.access_default_action
    scm_use_main_ip_restriction   = true

    application_stack {
      docker_registry_url = "https://${local.registry_host}"
      docker_image_name   = local.image_name
    }

    dynamic "ip_restriction" {
      for_each = local.access_rules

      content {
        name        = ip_restriction.value.name
        action      = "Allow"
        priority    = 100 + ip_restriction.key
        ip_address  = ip_restriction.value.ip_address
        service_tag = ip_restriction.value.service_tag
      }
    }
  }

  # Keeps `az webapp log tail` / log stream usable; durable logs go to Log Analytics (observability.tf).
  logs {
    http_logs {
      file_system {
        retention_in_days = 7
        retention_in_mb   = 100
      }
    }
  }

  lifecycle {
    ignore_changes = [
      app_settings,
      site_config[0].application_stack,
    ]

    precondition {
      condition     = !local.use_acr || startswith(local.registry_host, coalesce(local.acr_name, "-"))
      error_message = "image is not hosted on the registry given in registry.acr_id. Either point image at that registry's login server or fix registry.acr_id."
    }

    precondition {
      condition     = !var.registry.pull_over_vnet || local.vnet_integrated
      error_message = "registry.pull_over_vnet requires network.integration_subnet_id."
    }
  }

  # The first container pull / Key Vault lookup must not race the role assignments.
  depends_on = [
    azurerm_role_assignment.acr_pull,
    azurerm_role_assignment.key_vault_secrets,
  ]
}

# ---------------------------------------------------------------------------------------------
# Rollouts: health-gated blue/green on every change to the image or its environment.
#
#   1. `terraform_data.release` fingerprints the release (image + full set of app settings).
#   2. When the fingerprint changes, the staging slot is recreated from scratch with the new release.
#      Production is untouched and keeps serving.
#   3. `azurerm_web_app_active_slot` swaps staging into production. App Service first starts the new
#      release on every instance and waits for the health endpoint to answer with a success status;
#      only then is traffic switched, without cold start. If the release never becomes healthy the
#      swap - and the apply - fails, and production still runs the previous release.
#   4. After the swap the staging slot holds the previous release, warm, as the rollback target.
#
# Because both slots ignore image/settings drift, the plan is clean again right after a release.
# To force a re-release of the same configuration (e.g. to wipe out manual portal edits):
#   tofu apply -replace=terraform_data.release
#
# Platform configuration that is not part of a release (TLS, access restrictions, VNet, health check
# timing) is applied to both slots in place.
# ---------------------------------------------------------------------------------------------

resource "terraform_data" "release" {
  input = {
    image = var.image
    # A hash, so nothing sensitive leaks; nonsensitive() lets the plan show *that* the environment changed.
    settings_sha256 = nonsensitive(sha256(jsonencode(local.app_settings)))
  }
}

resource "azurerm_linux_web_app_slot" "staging" {
  name           = "staging"
  app_service_id = azurerm_linux_web_app.this.id
  tags           = local.tags

  https_only                                     = true
  client_affinity_enabled                        = false
  public_network_access_enabled                  = var.network.public_access_enabled
  virtual_network_subnet_id                      = var.network.integration_subnet_id
  vnet_image_pull_enabled                        = var.registry.pull_over_vnet
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  key_vault_reference_identity_id                = azurerm_user_assigned_identity.this.id

  app_settings = local.app_settings

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.this.id]
  }

  site_config {
    always_on               = true
    http2_enabled           = true
    use_32_bit_worker       = false
    ftps_state              = "Disabled"
    minimum_tls_version     = "1.2"
    scm_minimum_tls_version = "1.2"
    vnet_route_all_enabled  = local.vnet_integrated

    health_check_path                 = var.health_check_path
    health_check_eviction_time_in_min = var.health_check_eviction_minutes

    container_registry_use_managed_identity       = local.use_acr
    container_registry_managed_identity_client_id = local.use_acr ? azurerm_user_assigned_identity.this.client_id : null

    ip_restriction_default_action = local.access_default_action
    scm_use_main_ip_restriction   = true

    application_stack {
      docker_registry_url = "https://${local.registry_host}"
      docker_image_name   = local.image_name
    }

    dynamic "ip_restriction" {
      for_each = local.access_rules

      content {
        name        = ip_restriction.value.name
        action      = "Allow"
        priority    = 100 + ip_restriction.key
        ip_address  = ip_restriction.value.ip_address
        service_tag = ip_restriction.value.service_tag
      }
    }
  }

  logs {
    http_logs {
      file_system {
        retention_in_days = 7
        retention_in_mb   = 100
      }
    }
  }

  lifecycle {
    # After a swap this slot holds the *previous* release; that is intended, not drift.
    ignore_changes = [
      app_settings,
      site_config[0].application_stack,
    ]
    replace_triggered_by = [terraform_data.release]
  }

  depends_on = [
    azurerm_role_assignment.acr_pull,
    azurerm_role_assignment.key_vault_secrets,
  ]
}

resource "azurerm_web_app_active_slot" "release" {
  slot_id = azurerm_linux_web_app_slot.staging.id

  lifecycle {
    replace_triggered_by = [terraform_data.release]
  }
}

# ---------------------------------------------------------------------------------------------
# Private ingress (optional). Covers the production hostname; the staging slot is then only
# reachable by the platform's own warm-up probes, which is all the rollout needs.
# ---------------------------------------------------------------------------------------------

resource "azurerm_private_endpoint" "app" {
  count = var.network.private_endpoint != null ? 1 : 0

  name                = "pe-${var.name}"
  resource_group_name = local.resource_group_name
  location            = var.location
  subnet_id           = var.network.private_endpoint.subnet_id
  tags                = local.tags

  private_service_connection {
    name                           = "psc-${var.name}"
    private_connection_resource_id = azurerm_linux_web_app.this.id
    subresource_names              = ["sites"]
    is_manual_connection           = false
  }

  dynamic "private_dns_zone_group" {
    for_each = length(var.network.private_endpoint.private_dns_zone_ids) > 0 ? [1] : []

    content {
      name                 = "default"
      private_dns_zone_ids = var.network.private_endpoint.private_dns_zone_ids
    }
  }
}
