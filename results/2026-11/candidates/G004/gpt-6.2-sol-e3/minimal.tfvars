# Sandbox plan fixture. Replace the SGs with dedicated workload SGs and
# configure the service IAM roles and notification address before production.
service_name                       = "checkout"
primary_client_security_group_id   = "sg-04f232ff989751cdf"
secondary_client_security_group_id = "sg-0cb8a65f0babcca70"
alarm_email                        = "database-oncall@example.com"
