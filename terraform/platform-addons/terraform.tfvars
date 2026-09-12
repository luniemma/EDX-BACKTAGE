# Every value this root runs with. variables.tf carries no defaults, so this
# file is the whole description of the deployment.
#
# Committed on purpose, like the platform root's: it holds no secrets. Never
# put secrets here.

project = "edx-backtage"

# The platform root's state. Must match ../state.s3.tfbackend.
tfstate_bucket = "edx-backtage-tfstate-724772096574"
tfstate_region = "us-east-1"

# Must match the key in ../platform/versions.tf.
platform_tfstate_key = "edx/platform/terraform.tfstate"

ingress_nginx_version = "4.11.3"
argocd_version        = "7.7.11"

# deploy/argocd's Application manifests and the RHDH chart's className both
# assume these; change them together.
argocd_namespace = "argocd"
ingress_class    = "nginx"

ingress_nginx_namespace        = "ingress-nginx"
ingress_nginx_chart_repository = "https://kubernetes.github.io/ingress-nginx"
argocd_chart_repository        = "https://argoproj.github.io/argo-helm"
helm_timeout_seconds           = 900

ingress_nginx_replicas = 2
ingress_nginx_resources = {
  requests = { cpu = "100m", memory = "128Mi" }
  limits   = { memory = "384Mi" }
}

argocd_replicas = {
  controller     = 1
  repoServer     = 1
  applicationSet = 1
  server         = 1
}

argocd_resources = {
  controller = {
    requests = { cpu = "100m", memory = "256Mi" }
    limits   = { memory = "1Gi" }
  }
  repoServer = {
    requests = { cpu = "50m", memory = "128Mi" }
    limits   = { memory = "512Mi" }
  }
  server = {
    requests = { cpu = "50m", memory = "128Mi" }
    limits   = { memory = "256Mi" }
  }
}
