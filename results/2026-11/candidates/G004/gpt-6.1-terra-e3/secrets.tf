resource "aws_secretsmanager_secret" "admin" {
  name                    = "${local.name}/database-admin"
  description             = "Aurora administrator credentials; replicated for disaster recovery"
  recovery_window_in_days = 30
  replica {
    region = var.secondary_region
  }
  tags = local.tags
}

resource "aws_secretsmanager_secret_version" "admin" {
  secret_id = aws_secretsmanager_secret.admin.id
  secret_string = jsonencode({
    username = var.master_username
    password = var.master_password
  })
}

variable "master_password" {
  description = "Strong, unique administrator password. Pass securely, never use the example password. Stored in OpenTofu state and Secrets Manager."
  type        = string
  sensitive   = true
  validation {
    condition     = length(var.master_password) >= 24 && length(var.master_password) <= 99 && can(regex("^[a-zA-Z0-9!#$%&()*+,:;<=>?\\[\\]^_{|}~.-]+$", var.master_password))
    error_message = "Use 24-99 printable password characters, excluding spaces, slash, at-sign, double quote, backslash and apostrophe."
  }
}
