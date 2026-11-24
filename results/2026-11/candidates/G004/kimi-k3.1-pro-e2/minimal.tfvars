name = "checkout-prod"

primary_region   = "us-east-1"
secondary_region = "us-west-2"
primary_vpc_id   = "vpc-0123456789abcdef0"
secondary_vpc_id = "vpc-0123456789abcdef1"

# Explicit IDs keep this smallest instantiation deterministic. Omit both subnet
# lists in a real environment to discover private subnets tagged tier=database.
primary_db_subnet_ids = [
  "subnet-0123456789abcdef0",
  "subnet-0123456789abcdef1",
]
secondary_db_subnet_ids = [
  "subnet-0123456789abcdef2",
  "subnet-0123456789abcdef3",
]

primary_application_security_group_ids   = ["sg-0123456789abcdef0"]
secondary_application_security_group_ids = ["sg-0123456789abcdef1"]

database_name = "checkout"
tags = {
  Environment = "apps-prod"
  Service     = "checkout"
}
