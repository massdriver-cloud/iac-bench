service = "checkout"
locations = {
  primary   = { region = "us-east-1", client_sg = "sg-0123456789abcdef0", alarm_topic = "arn:aws:sns:us-east-1:123456789012:database-oncall" }
  secondary = { region = "us-west-2", client_sg = "sg-0fedcba9876543210", alarm_topic = "arn:aws:sns:us-west-2:123456789012:database-oncall" }
}
client_roles = { checkout-api = "checkout" }
