name             = "checkout"
environment      = "apps-prod"
primary_region   = "us-east-1"
secondary_region = "us-west-2"
primary_vpc_id   = "vpc-0123456789abcdef0"
secondary_vpc_id = "vpc-0123456789abcdef1"
database_name    = "checkout"

primary_subnet_ids = [
  "subnet-0123456789abcdef0",
  "subnet-0123456789abcdef1",
]

secondary_subnet_ids = [
  "subnet-0123456789abcdef2",
  "subnet-0123456789abcdef3",
]

allowed_cidr_blocks = ["10.0.0.0/16"]