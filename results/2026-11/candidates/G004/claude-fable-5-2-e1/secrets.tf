###############################################################################
# Break-glass administrator credentials.
#
# Services authenticate with IAM (iam.tf); this password exists for initial
# user setup and emergencies. It is generated at apply time, written straight
# to Secrets Manager and to the cluster through write-only arguments, and is
# never stored in OpenTofu state or shown in a plan.
#
# (RDS-managed master passwords are not used because Aurora does not support
# them for clusters that belong to a global database.)
#
# The secret is replicated to the DR region under that region's key, so the
# credentials are still readable when the primary region is not.
###############################################################################

ephemeral "random_password" "master" {
  length           = 32
  special          = true
  override_special = "!#$%^&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "master" {
  provider = aws.primary

  name        = "rds/${local.name}/master"
  description = "Break-glass administrator credentials for the ${local.name} Aurora global database"
  kms_key_id  = aws_kms_key.primary.arn

  replica {
    region     = var.secondary_region
    kms_key_id = aws_kms_key.secondary.arn
  }
}

resource "aws_secretsmanager_secret_version" "master" {
  provider = aws.primary

  secret_id = aws_secretsmanager_secret.master.id

  secret_string_wo = jsonencode({
    username = var.master_username
    password = ephemeral.random_password.master.result
    engine   = "postgres"
    port     = local.port
    dbname   = local.database_name
  })
  secret_string_wo_version = var.master_password_version
}

# Read the stored value back so the cluster is always given exactly what is in
# Secrets Manager, even if an earlier apply was interrupted half-way.
ephemeral "aws_secretsmanager_secret_version" "master" {
  provider = aws.primary

  secret_id  = aws_secretsmanager_secret_version.master.secret_id
  version_id = aws_secretsmanager_secret_version.master.version_id
}
