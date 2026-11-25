# Smallest complete instantiation. Explicit subnet IDs keep this example
# self-contained; omit both *_db_subnet_ids settings in a real environment to
# discover the network team's available subnets tagged tier=database.
name             = "payments-minimal"
database_name    = "payments"
primary_vpc_id   = "vpc-0123456789abcdef0"
secondary_vpc_id = "vpc-0123456789abcdef1"
primary_region   = "us-east-1"
secondary_region = "us-west-2"

primary_db_subnet_ids = [
  "subnet-0123456789abcdef0",
  "subnet-0123456789abcdef1",
]

secondary_db_subnet_ids = [
  "subnet-0123456789abcdef2",
  "subnet-0123456789abcdef3",
]

tags = {
  Environment = "apps-prod"
  Owner       = "platform"
}
