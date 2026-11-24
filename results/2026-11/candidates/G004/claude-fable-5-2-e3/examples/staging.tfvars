# A fuller example: a staging database with the regions the other way round,
# an explicit IAM login user and a tighter replication-lag alarm.
service          = "orders"
environment      = "staging"
primary_region   = "us-west-2"
secondary_region = "us-east-1"

app_database_users            = ["orders_app"]
instance_class                = "db.r6g.large"
replication_lag_alarm_seconds = 3
