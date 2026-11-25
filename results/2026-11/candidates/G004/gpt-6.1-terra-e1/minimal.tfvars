service_name                        = "checkout"
environment                         = "staging"
primary_client_security_group_ids   = ["sg-0123456789abcdef0"]
secondary_client_security_group_ids = ["sg-0123456789abcdef1"]
primary_alarm_topic_arn             = "arn:aws:sns:us-east-1:123456789012:database-alerts"
secondary_alarm_topic_arn           = "arn:aws:sns:us-west-2:123456789012:database-alerts"
