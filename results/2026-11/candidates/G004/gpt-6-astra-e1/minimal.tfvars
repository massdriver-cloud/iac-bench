name                                = "checkout"
database_name                       = "checkout"
application_db_user                 = "checkout_app"
application_iam_role_names          = ["checkout-prod"]
primary_client_security_group_ids   = ["sg-0123456789abcdef0"]
secondary_client_security_group_ids = ["sg-0fedcba9876543210"]
alert_email                         = "database-oncall@example.com"
