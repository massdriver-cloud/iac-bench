# One region, insecure knobs: what a single-region habit plus pass-through
# produces. No global database; encryption, public access and backup
# retention are inputs; the database port is open to the world by default;
# Aurora PostgreSQL 16 without rds.force_ssl; it builds its own VPC.

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

variable "name" {
  description = "Cluster name."
  type        = string
}

variable "master_password" {
  description = "Master password."
  type        = string
  sensitive   = true
}

variable "encrypted" {
  description = "Encrypt storage."
  type        = bool
  default     = true
}

variable "publicly_accessible" {
  description = "Give instances public addresses."
  type        = bool
  default     = false
}

variable "allowed_cidrs" {
  description = "CIDRs allowed to connect."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

resource "aws_vpc" "this" {
  cidr_block = "10.99.0.0/16"
}

resource "aws_subnet" "a" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = "10.99.1.0/24"
  availability_zone = "us-east-1a"
}

resource "aws_subnet" "b" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = "10.99.2.0/24"
  availability_zone = "us-east-1b"
}

resource "aws_db_subnet_group" "this" {
  name       = var.name
  subnet_ids = [aws_subnet.a.id, aws_subnet.b.id]
}

resource "aws_security_group" "this" {
  name   = "${var.name}-db"
  vpc_id = aws_vpc.this.id
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidrs
  }
}

resource "aws_rds_cluster" "this" {
  cluster_identifier     = var.name
  engine                 = "aurora-postgresql"
  engine_version         = "16.6"
  master_username        = "postgres"
  master_password        = var.master_password
  storage_encrypted      = var.encrypted
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.this.id]
  skip_final_snapshot    = true
}

resource "aws_rds_cluster_instance" "this" {
  count               = 2
  identifier          = "${var.name}-${count.index}"
  cluster_identifier  = aws_rds_cluster.this.id
  engine              = "aurora-postgresql"
  instance_class      = "db.r7g.large"
  publicly_accessible = var.publicly_accessible
}
