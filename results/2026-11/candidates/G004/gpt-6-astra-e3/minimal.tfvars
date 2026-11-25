name                                = "checkout-prod"
primary_client_security_group_ids   = ["sg-0123456789abcdef0"]
secondary_client_security_group_ids = ["sg-0fedcba9876543210"]
application_role_names              = ["checkout-prod-eks"]
alarm_email                         = "database-oncall@example.com"
