provider "helm" {
  kubernetes {
    config_path    = pathexpand(var.kube_config_path)
    config_context = var.kube_context
  }
}

provider "kubernetes" {
  config_path    = pathexpand(var.kube_config_path)
  config_context = var.kube_context
}

provider "kubectl" {
  config_path      = pathexpand(var.kube_config_path)
  config_context   = var.kube_context
  load_config_file = true
}
