environment  = "prod"
service_name = "checkout"

primary_region   = "us-east-1"
secondary_region = "us-west-2"

primary_vpc_id   = "vpc-0123456789abcdef0"
secondary_vpc_id = "vpc-0123456789abcdef1"

primary_database_subnet_ids = [
  "subnet-0123456789abcdef0",
  "subnet-0123456789abcdef1",
]
secondary_database_subnet_ids = [
  "subnet-1123456789abcdef0",
  "subnet-1123456789abcdef1",
]

primary_eks_security_group_ids   = ["sg-0123456789abcdef0"]
secondary_eks_security_group_ids = ["sg-1123456789abcdef0"]
