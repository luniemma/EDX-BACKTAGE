# Every value this root runs with. variables.tf carries no defaults, so this
# file is the whole description of the deployment.
#
# Committed on purpose, like the platform root's: it holds no secrets. Never
# put secrets here.

project = "edx-backtage"

# Matches name in ../platform/terraform.tfvars, so the two read as one stack.
name = "edx-rhdh"

# The platform root's state. Must match ../state.s3.tfbackend.
tfstate_bucket = "edx-backtage-tfstate-724772096574"
tfstate_region = "us-east-1"

# Must match the key in ../platform/versions.tf.
platform_tfstate_key = "edx/platform/terraform.tfstate"

engine_version        = "15"
instance_class        = "db.t4g.micro"
allocated_storage     = 20
backup_retention_days = 7
multi_az              = false
deletion_protection   = false

db_name     = "backstage"
db_username = "backstage"

db_port               = 5432
storage_type          = "gp3"
max_allocated_storage = 60

# UTC. Backups run ahead of the maintenance window; changes wait for it.
backup_window                = "07:00-08:00"
maintenance_window           = "Mon:08:30-Mon:09:30"
apply_immediately            = false
cloudwatch_logs_exports      = ["postgresql"]
performance_insights_enabled = false

# Where kubernetes_secret_command writes the password.
rhdh_namespace      = "rhdh-lean"
rhdh_db_secret_name = "rhdh-db"
