# Break-glass master credentials.
#
# Services do not use these: they authenticate with their IAM roles (see
# iam.tf). The master user exists for bootstrap (creating the IAM-enabled
# application users) and for emergencies.
#
# The password is generated ephemerally and passed through write-only
# attributes, so it is never written to the plan or the state file. The only
# place it is stored is Secrets Manager, encrypted with this database's key and
# replicated to the standby region so it is still readable when the primary
# region is not.
#
# (RDS-managed master passwords would be simpler, but RDS does not offer them
# for clusters that belong to an Aurora global database.)

ephemeral "random_password" "master" {
  length  = 40
  special = true
  # RDS rejects '/', '@', '"' and spaces in master passwords.
  override_special = "!#%^*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "master" {
  name                    = "${local.name}/aurora/master"
  description             = "Break-glass master credentials for the ${local.name} Aurora PostgreSQL global database"
  kms_key_id              = aws_kms_key.primary.arn
  recovery_window_in_days = 30

  replica {
    region     = var.secondary_region
    kms_key_id = aws_kms_key.secondary.arn
  }
}

resource "aws_secretsmanager_secret_version" "master" {
  secret_id = aws_secretsmanager_secret.master.id

  secret_string_wo = jsonencode({
    engine   = "postgres"
    username = local.master_username
    password = ephemeral.random_password.master.result
    port     = local.port
    dbname   = local.database_name
  })
  secret_string_wo_version = var.master_password_version
}

# The cluster reads the password back from Secrets Manager rather than from the
# generator, so the database and the secret can never disagree, even if an
# apply is interrupted half-way.
ephemeral "aws_secretsmanager_secret_version" "master" {
  secret_id = aws_secretsmanager_secret_version.master.secret_id
}
