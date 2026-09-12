# Every value this root runs with. variables.tf carries no defaults, so this
# file is the whole description of the deployment. Committed on purpose: it
# holds no secrets. Never put secrets here.

# Empty disables the whole root: no zone, no records, no cost. Set it, apply,
# then delegate the domain to the `nameservers` output at the registrar.
domain_name = ""

project    = "edx-backtage"
aws_region = "us-east-1"
