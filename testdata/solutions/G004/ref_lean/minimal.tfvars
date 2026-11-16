name    = "orders"
regions = { primary = "us-east-1", secondary = "us-west-2" }
network = {
  primary = {
    vpc_id       = "vpc-0123456789abcdef0"
    subnet_ids   = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
    client_cidrs = ["10.20.0.0/16"]
    kms_key_arn  = "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"
  }
  secondary = {
    vpc_id       = "vpc-0fedcba9876543210"
    subnet_ids   = ["subnet-0fedcba9876543210", "subnet-0fedcba9876543211"]
    client_cidrs = ["10.20.0.0/16"]
    kms_key_arn  = "arn:aws:kms:us-west-2:123456789012:key/66666666-7777-8888-9999-000000000000"
  }
}
