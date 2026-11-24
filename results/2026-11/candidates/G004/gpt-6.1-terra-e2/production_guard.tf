resource "terraform_data" "production_requirements" {
  input = var.environment
  lifecycle {
    precondition {
      condition     = var.environment != "prod" || (length(var.primary_client_security_group_ids) > 0 && length(var.secondary_client_security_group_ids) > 0)
      error_message = "Production requires at least one EKS client security group in each region."
    }
    precondition {
      condition     = var.environment != "prod" || length(var.secondary_alarm_actions) > 0
      error_message = "Production requires a secondary-region replication-lag alarm action."
    }
  }
}
