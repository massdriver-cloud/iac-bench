name = "checkout"
regions = {
  primary   = "us-east-1"
  secondary = "us-west-2"
}
eks_client_security_groups = {
  primary   = ["sg-0123456789abcdef0"]
  secondary = ["sg-0123456789abcdef1"]
}
application_iam_role_names = ["checkout-prod-us-east-1", "checkout-prod-us-west-2"]
