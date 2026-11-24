# -----------------------------------------------------------------------------
# Cross-Pillar Operational Guardrails
# -----------------------------------------------------------------------------

check "private_ingress_reachability" {
  assert {
    condition     = var.network.public_network_access_enabled || var.network.private_endpoint != null
    error_message = "network.public_network_access_enabled is false, but no network.private_endpoint is configured; the service will have no reachable ingress endpoint."
  }
}

check "key_vault_reference_identity_attached" {
  assert {
    condition     = var.key_vault_reference_identity_id == null || contains(var.user_assigned_identity_ids, var.key_vault_reference_identity_id)
    error_message = "key_vault_reference_identity_id must also be present in user_assigned_identity_ids so the Web App can assume that identity."
  }
}

check "per_site_scaling_worker_count" {
  assert {
    condition     = !var.capacity.per_site_scaling_enabled || var.capacity.app_worker_count == null || var.capacity.app_worker_count <= var.capacity.max_instances
    error_message = "When capacity.per_site_scaling_enabled is true, capacity.app_worker_count should not exceed capacity.max_instances."
  }
}
