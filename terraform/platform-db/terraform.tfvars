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

# IAM token logins, in addition to the password. See the variable for the
# GRANT and rds-db:connect permission a login also needs.
iam_database_authentication_enabled = true

# UTC. Backups run ahead of the maintenance window; changes wait for it.
backup_window                = "07:00-08:00"
maintenance_window           = "Mon:08:30-Mon:09:30"
apply_immediately            = false
cloudwatch_logs_exports      = ["postgresql"]
performance_insights_enabled = false

# Where kubernetes_secret_command writes the password.
rhdh_namespace      = "rhdh-lean"
rhdh_db_secret_name = "rhdh-db"

# Alarms, published to the platform root's alerts topic. Thresholds are in each
# metric's CloudWatch unit: FreeStorageSpace and FreeableMemory are bytes.
notify_on_recovery = true

db_alarms = {
  cpu_high = {
    namespace           = "AWS/RDS"
    metric_name         = "CPUUtilization"
    statistic           = "Average"
    comparison_operator = "GreaterThanThreshold"
    threshold           = 80 # percent
    period              = 300
    evaluation_periods  = 3
    treat_missing_data  = "missing"
    description         = "Database CPU has been above 80% for 15 minutes."
  }
  free_storage_low = {
    namespace           = "AWS/RDS"
    metric_name         = "FreeStorageSpace"
    statistic           = "Minimum"
    comparison_operator = "LessThanThreshold"
    threshold           = 2147483648 # 2 GiB, of 20 allocated
    period              = 300
    evaluation_periods  = 2
    treat_missing_data  = "missing"
    description         = "Less than 2 GiB of database storage left, even with storage autoscaling."
  }
  freeable_memory_low = {
    namespace           = "AWS/RDS"
    metric_name         = "FreeableMemory"
    statistic           = "Average"
    comparison_operator = "LessThanThreshold"
    threshold           = 104857600 # 100 MiB, of db.t4g.micro's 1 GiB
    period              = 300
    evaluation_periods  = 3
    treat_missing_data  = "missing"
    description         = "Less than 100 MiB of database memory available for 15 minutes."
  }
}
