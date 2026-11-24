# Example: the smallest useful option set on top of the defaults - the same
# minimal bucket, but encrypted with a customer-managed KMS key that the
# module creates, aliases and rotates for you.
#
#   tofu plan -var-file=kms-test.tfvars

name        = "app-assets"
environment = "dev"

encryption = "aws:kms"
