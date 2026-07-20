locals {
  name_prefix   = "${var.project}-${var.environment}"
  db_identifier = "${local.name_prefix}-mysql"

  # Single shared database for all 3 domain services (customers, visits, vets) —
  # confirmed by cross-service FK: visits.pet_id -> pets.id (PETPLAT-24).
  db_name = "petclinic"

  tags = merge(var.tags, {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}

# ---------------------------------------------------------------------------
# Master password — generated, never hardcoded. Excludes '/', '@', '"', and
# space from the special-character set: RDS rejects all four in a MySQL
# master password.
# ---------------------------------------------------------------------------

resource "random_password" "master" {
  length      = 20
  special     = true
  min_special = 2
  min_upper   = 2
  min_lower   = 2
  min_numeric = 2

  override_special = "!#$%&*()-_=+[]{}<>?"
}

# ---------------------------------------------------------------------------
# Secrets Manager — single JSON secret with username + password (PETPLAT-23).
# ---------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "rds_credentials" {
  name        = "petclinic/${var.environment}/rds-credentials"
  description = "RDS master credentials for ${local.db_identifier}"

  tags = merge(local.tags, { Name = "${local.name_prefix}-rds-credentials" })
}

resource "aws_secretsmanager_secret_version" "rds_credentials" {
  secret_id = aws_secretsmanager_secret.rds_credentials.id

  secret_string = jsonencode({
    username = var.master_username
    password = random_password.master.result
  })
}

# ---------------------------------------------------------------------------
# DB subnet group and parameter group
# ---------------------------------------------------------------------------

resource "aws_db_subnet_group" "this" {
  name       = "${local.name_prefix}-rds-subnet-group"
  subnet_ids = var.subnet_ids

  tags = merge(local.tags, { Name = "${local.name_prefix}-rds-subnet-group" })
}

resource "aws_db_parameter_group" "this" {
  name        = "${local.name_prefix}-mysql8"
  family      = "mysql8.0"
  description = "utf8mb4 parameter group for ${local.db_identifier}"

  parameter {
    name  = "character_set_server"
    value = "utf8mb4"
  }

  parameter {
    name  = "collation_server"
    value = "utf8mb4_unicode_ci"
  }

  tags = local.tags
}

# ---------------------------------------------------------------------------
# RDS MySQL instance — public subnets, all-public design (see ADR-0001); the
# security group passed in from the vpc module is the actual access boundary
# (3306 from EKS node SG only, never 0.0.0.0/0).
# ---------------------------------------------------------------------------

resource "aws_db_instance" "this" {
  identifier = local.db_identifier

  engine         = "mysql"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp2" # per docs/technical-spec.md#rds-database — gp3 (used for EKS node volumes) not specified here
  storage_encrypted     = true

  db_name  = local.db_name
  username = var.master_username
  password = random_password.master.result
  port     = 3306

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.security_group_id]
  parameter_group_name   = aws_db_parameter_group.this.name
  publicly_accessible    = false

  multi_az                  = var.multi_az
  backup_retention_period   = var.backup_retention_period
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${local.db_identifier}-final"
  deletion_protection       = var.deletion_protection

  auto_minor_version_upgrade = true
  copy_tags_to_snapshot      = true

  tags = merge(local.tags, { Name = local.db_identifier })

  # Once rotation (manual or Secrets-Manager-driven) changes the live DB
  # password out from under this resource, a plain `terraform apply` would
  # otherwise reset it back to random_password.master.result and undo the
  # rotation.
  lifecycle {
    ignore_changes = [password]
  }
}
