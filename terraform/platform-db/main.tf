########################################
# Cluster coordinates
########################################
# Read over remote state rather than data sources, so this root fails loudly
# if ../platform has not been applied instead of half-building a database with
# nowhere to attach it.

data "terraform_remote_state" "platform" {
  backend = "s3"

  config = {
    bucket = "edx-backtage-tfstate-724772096574"
    key    = "edx/platform/terraform.tfstate"
    region = "us-east-1"
  }
}

locals {
  region          = data.terraform_remote_state.platform.outputs.region
  vpc_id          = data.terraform_remote_state.platform.outputs.vpc_id
  private_subnets = data.terraform_remote_state.platform.outputs.private_subnet_ids
  node_sg_id      = data.terraform_remote_state.platform.outputs.node_security_group_id
}

provider "aws" {
  region = local.region

  default_tags {
    tags = {
      Project     = var.project
      ManagedBy   = "terraform"
      Application = "platform-db"
    }
  }
}

########################################
# Placement
########################################

resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-db"
  subnet_ids = local.private_subnets

  description = "No-egress private subnets; RDS needs no route to the internet"
}

# Ingress from the node security group only — not from a CIDR. Node addresses
# change every time the Spot group is replaced, and a CIDR rule would either
# go stale or have to be widened to the whole VPC. A security-group source
# keeps the rule correct across replacements and still excludes everything in
# the VPC that is not a cluster node.
resource "aws_security_group" "db" {
  name        = "${var.name}-db"
  description = "PostgreSQL access for ${var.name} cluster nodes"
  vpc_id      = local.vpc_id

  tags = { Name = "${var.name}-db" }
}

resource "aws_vpc_security_group_ingress_rule" "postgres_from_nodes" {
  security_group_id            = aws_security_group.db.id
  description                  = "PostgreSQL from cluster nodes"
  referenced_security_group_id = local.node_sg_id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

# Deliberately no egress rule. RDS initiates nothing outbound, and omitting it
# means the security group has no egress at all rather than the default
# allow-everything a bare aws_security_group would otherwise inherit.

########################################
# The instance
########################################

resource "aws_db_instance" "this" {
  identifier = "${var.name}-postgres"

  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  db_name  = var.db_name
  username = var.db_username

  # AWS generates the master password and stores it in Secrets Manager, so it
  # never enters Terraform state. The alternative — random_password — writes
  # the plaintext into state, and state is only as private as the bucket.
  # See outputs.tf for retrieving it.
  manage_master_user_password = true

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.allocated_storage * 3 # storage autoscaling ceiling
  storage_type          = "gp3"
  storage_encrypted     = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.db.id]

  # The subnets have no internet route, but this is the switch that actually
  # decides reachability — leaving it to the subnet alone would be relying on
  # a side effect.
  publicly_accessible = false

  multi_az            = var.multi_az
  deletion_protection = var.deletion_protection

  backup_retention_period = var.backup_retention_days
  backup_window           = "07:00-08:00" # UTC, ahead of the maintenance window
  maintenance_window      = "Mon:08:30-Mon:09:30"

  auto_minor_version_upgrade = true
  apply_immediately          = false # roll changes in the maintenance window

  # Postgres logs only. `upgrade` is not a valid export type for this engine
  # and RDS rejects the whole create if it is listed.
  enabled_cloudwatch_logs_exports = ["postgresql"]

  performance_insights_enabled = false # not free on burstable classes

  # A final snapshot on destroy is the safety net that makes tearing this down
  # reversible. Named with a timestamp because RDS rejects a duplicate
  # snapshot identifier, which would otherwise block the second teardown.
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.name}-postgres-final-${formatdate("YYYYMMDDhhmmss", timestamp())}"

  lifecycle {
    # timestamp() changes on every plan, so without this the instance shows a
    # perpetual diff and would be replaced on any apply.
    ignore_changes = [final_snapshot_identifier]
  }
}
