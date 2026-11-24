output "primary_cluster_arn" {
  value = aws_rds_cluster.primary.arn
}
output "secondary_cluster_arn" {
  value = aws_rds_cluster.secondary.arn
}
output "replication_lag_alarm_arn" {
  value = aws_cloudwatch_metric_alarm.replication_lag.arn
}
