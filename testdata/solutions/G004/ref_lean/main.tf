# A lean global database: the network arrives as IDs, client access as CIDRs,
# both regions' KMS keys as ARNs. TLS comes from Aurora PostgreSQL 17's
# default rds.force_ssl; no custom parameter groups.

variable "name" {
  description = "Database name, used for the global cluster and both regional clusters."
  type        = string
}

variable "regions" {
  description = "Primary (writer) and secondary (standby) regions."
  type        = object({ primary = string, secondary = string })
}

variable "network" {
  description = "Per-region database subnets, VPC, client CIDRs and KMS key ARN."
  type = map(object({
    vpc_id       = string
    subnet_ids   = list(string)
    client_cidrs = list(string)
    kms_key_arn  = string
  }))
  validation {
    condition     = alltrue([for k in ["primary", "secondary"] : contains(keys(var.network), k)])
    error_message = "Provide network settings for primary and secondary."
  }
}

variable "instance_class" {
  description = "Instance class for every instance."
  type        = string
  default     = "db.r7g.large"
}


variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}

provider "aws" {
  region = var.regions.primary
  default_tags {
    tags = var.tags
  }
}

provider "aws" {
  alias  = "secondary"
  region = var.regions.secondary
  default_tags {
    tags = var.tags
  }
}

resource "random_password" "master" {
  length  = 32
  special = false
}

resource "aws_rds_global_cluster" "this" {
  global_cluster_identifier = var.name
  engine                    = "aurora-postgresql"
  engine_version            = "17.5"
  storage_encrypted         = true
  deletion_protection       = true
}

resource "aws_db_subnet_group" "primary" {
  name       = "${var.name}-primary"
  subnet_ids = var.network["primary"].subnet_ids
}

resource "aws_db_subnet_group" "secondary" {
  provider   = aws.secondary
  name       = "${var.name}-secondary"
  subnet_ids = var.network["secondary"].subnet_ids
}

resource "aws_security_group" "primary" {
  name        = "${var.name}-db"
  description = "PostgreSQL from approved client networks"
  vpc_id      = var.network["primary"].vpc_id
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = var.network["primary"].client_cidrs
  }
}

resource "aws_security_group" "secondary" {
  provider    = aws.secondary
  name        = "${var.name}-db"
  description = "PostgreSQL from approved client networks"
  vpc_id      = var.network["secondary"].vpc_id
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = var.network["secondary"].client_cidrs
  }
}

resource "aws_rds_cluster" "primary" {
  cluster_identifier                  = "${var.name}-primary"
  global_cluster_identifier           = aws_rds_global_cluster.this.id
  engine                              = "aurora-postgresql"
  engine_version                      = "17.5"
  master_username                     = "postgres_admin"
  master_password                     = random_password.master.result
  iam_database_authentication_enabled = true
  storage_encrypted                   = true
  kms_key_id                          = var.network["primary"].kms_key_arn
  db_subnet_group_name                = aws_db_subnet_group.primary.name
  vpc_security_group_ids              = [aws_security_group.primary.id]
  backup_retention_period             = 14
  deletion_protection                 = true
  skip_final_snapshot                 = false
  final_snapshot_identifier           = "${var.name}-primary-final"
  enabled_cloudwatch_logs_exports     = ["postgresql"]
}

resource "aws_rds_cluster" "secondary" {
  provider                            = aws.secondary
  cluster_identifier                  = "${var.name}-secondary"
  global_cluster_identifier           = aws_rds_global_cluster.this.id
  engine                              = "aurora-postgresql"
  engine_version                      = "17.5"
  iam_database_authentication_enabled = true
  storage_encrypted                   = true
  kms_key_id                          = var.network["secondary"].kms_key_arn
  db_subnet_group_name                = aws_db_subnet_group.secondary.name
  vpc_security_group_ids              = [aws_security_group.secondary.id]
  backup_retention_period             = 14
  deletion_protection                 = true
  skip_final_snapshot                 = false
  final_snapshot_identifier           = "${var.name}-secondary-final"
  enabled_cloudwatch_logs_exports     = ["postgresql"]
  depends_on                          = [aws_rds_cluster_instance.primary]
}

resource "aws_rds_cluster_instance" "primary" {
  count              = 2
  identifier         = "${var.name}-primary-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.primary.id
  engine             = "aurora-postgresql"
  instance_class     = var.instance_class

  publicly_accessible = false
}

resource "aws_rds_cluster_instance" "secondary" {
  provider           = aws.secondary
  count              = 1
  identifier         = "${var.name}-secondary-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.secondary.id
  engine             = "aurora-postgresql"
  instance_class     = var.instance_class

  publicly_accessible = false
}

output "global_cluster_id" {
  description = "Global cluster identifier, for managed failover."
  value       = aws_rds_global_cluster.this.id
}
