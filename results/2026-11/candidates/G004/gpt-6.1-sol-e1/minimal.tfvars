name                = "checkout"
application_db_user = "checkout_app"
alarm_email         = "database-oncall@example.com"

# PLAN-ONLY examples. Replace IDs with the network team's existing apps-prod
# VPCs, private tier=database subnets and EKS client security groups before apply.
# Keys must be the actual Availability Zones containing those subnets.
primary_network = {
  vpc_id = "vpc-0123456789abcdef0"
  database_subnets = {
    us-east-1a = "subnet-0123456789abcdef0"
    us-east-1b = "subnet-0123456789abcdef1"
  }
  client_security_group_ids = ["sg-0123456789abcdef0"]
}
secondary_network = {
  vpc_id = "vpc-1123456789abcdef0"
  database_subnets = {
    us-west-2a = "subnet-1123456789abcdef0"
    us-west-2b = "subnet-1123456789abcdef1"
  }
  client_security_group_ids = ["sg-1123456789abcdef0"]
}
