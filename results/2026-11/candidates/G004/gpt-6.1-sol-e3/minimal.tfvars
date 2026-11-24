name                   = "checkout"
environment            = "prod"
application_role_names = ["checkout-prod-us-east-1", "checkout-prod-us-west-2"]
eks_security_group_ids = {
  primary   = ["sg-0123456789abcdef0"]
  secondary = ["sg-0fedcba9876543210"]
}
alarm_email = "database-oncall@example.com"
