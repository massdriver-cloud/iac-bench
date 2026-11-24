variable "secondary_alarm_actions" {
  description = "SNS topic ARNs or other CloudWatch alarm action ARNs in the secondary region; configure an on-call destination for production."
  type        = list(string)
  default     = []
}
