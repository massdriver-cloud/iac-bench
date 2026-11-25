name        = "checkout"
environment = "prod"
clients = {
  primary = {
    security_group_ids = ["sg-0123456789abcdef0"]
    iam_role_names     = ["checkout-prod-us-east-1"]
  }
  secondary = {
    security_group_ids = ["sg-0fedcba9876543210"]
    iam_role_names     = ["checkout-prod-us-west-2"]
  }
}
