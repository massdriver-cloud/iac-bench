variable "grant_instance_user_role" {
  description = "Grant roles/cloudsql.instanceUser to every identity in iam_users so IAM database authentication actually lets them connect. Granted at project scope (the provider has no instance-scoped Cloud SQL IAM resource). Set false if the security team manages these grants out of band."
  type        = bool
  default     = true
}
