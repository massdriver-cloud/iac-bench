# A fuller instantiation showing every commonly used knob. IDs and ARNs are
# placeholders; replace them with your own.

service     = "order-history"
environment = "staging"

instance_class       = "db.r6g.xlarge"
instances_per_region = 3

database_name      = "orders"
iam_database_users = ["orders_api", "orders_worker"]

# Pod roles that should be able to log in with IAM tokens.
iam_auth_role_names = ["order-history-api", "order-history-worker"]

allowed_security_group_ids = {
  primary = ["sg-0123456789abcdef0"]
}

allowed_cidr_blocks = {
  secondary = ["10.20.16.0/20"]
}

alarm_topic_arns = {
  primary   = ["arn:aws:sns:us-east-1:111122223333:platform-database-alerts"]
  secondary = ["arn:aws:sns:us-west-2:111122223333:platform-database-alerts"]
}

enforced_rpo_seconds = 20

tags = {
  team        = "orders"
  cost-center = "cc-1234"
}
