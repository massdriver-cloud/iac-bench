name        = "checkout"
environment = "apps-prod"
alarm_email = "database-oncall@example.com"
client_security_group_ids = {
  primary   = ["sg-0123456789abcdef0"]
  secondary = ["sg-0fedcba9876543210"]
}
database_users = {
  checkout = {
    primary_role_name   = "checkout-prod-primary"
    secondary_role_name = "checkout-prod-secondary"
  }
}
