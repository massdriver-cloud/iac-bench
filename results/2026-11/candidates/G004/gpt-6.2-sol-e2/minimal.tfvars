name        = "checkout"
environment = "prod"

eks_source_security_group_ids = {
  primary   = ["sg-0123456789abcdef0"]
  secondary = ["sg-0fedcba9876543210"]
}

alarm_topic_arns = {
  primary   = "arn:aws:sns:us-east-1:123456789012:database-oncall"
  secondary = "arn:aws:sns:us-west-2:123456789012:database-oncall"
}
