name             = "checkout"
environment      = "apps-prod"
primary_region   = "us-east-1"
secondary_region = "us-west-2"

primary_vpc_id   = "vpc-0aaaaaaaaaaaaaaa0"
secondary_vpc_id = "vpc-0bbbbbbbbbbbbbbb0"

primary_subnet_ids = [
  "subnet-0aaaaaaaaaaaaaaa1",
  "subnet-0aaaaaaaaaaaaaaa2",
]

secondary_subnet_ids = [
  "subnet-0bbbbbbbbbbbbbbb1",
  "subnet-0bbbbbbbbbbbbbbb2",
]

primary_vpc_cidr   = "10.100.0.0/16"
secondary_vpc_cidr = "10.200.0.0/16"