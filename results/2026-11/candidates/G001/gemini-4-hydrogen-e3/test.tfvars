app_name                     = "very-long-application-name-test"
environment                  = "production-eu"
purpose                      = "audit-logs-archive"
usage_profile                = "logs"
kms_key_arn                  = "arn:aws:kms:us-east-1:123456789012:key/1234abcd-12ab-34cd-56ef-1234567890ab"
cors_allowed_origins         = ["https://app.example.com"]
cloudfront_distribution_arns = ["arn:aws:cloudfront::123456789012:distribution/EDFDVBD6EXAMPLE"]
enable_eventbridge           = true
create_iam_policies          = true
tags = {
  Team       = "platform"
  CostCenter = "eng-101"
}
