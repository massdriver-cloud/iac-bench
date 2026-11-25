name        = "checkout"
environment = "staging"

allowed_security_group_ids = {
  primary   = ["sg-0123456789abcdef0"]
  secondary = ["sg-0123456789abcdef1"]
}
