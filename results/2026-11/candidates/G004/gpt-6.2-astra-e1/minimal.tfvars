service            = "checkout"
clients            = { primary = "sg-0123456789abcdef0", secondary = "sg-0123456789abcdef1" }
application_role   = "checkout-prod"
bootstrap_password = "ExampleOnly-ReplaceBeforeDeploy42"
alarm_topic_arn    = "arn:aws:sns:us-west-2:123456789012:database-oncall"
