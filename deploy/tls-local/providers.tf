# All three providers talk to the local minikube cluster via kubeconfig.
# A guard in main.tf refuses to apply if the context is not minikube, so this
# stack can never touch a real cluster by accident.

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
