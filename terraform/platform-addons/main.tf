########################################
# ingress-nginx
########################################
# One NLB for the whole cluster (~$16/month), shared by every Ingress. An ALB
# per Ingress via the AWS load balancer controller would be more idiomatic on
# EKS and several times the price, which is the wrong trade at this budget.

resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = var.ingress_nginx_version
  namespace        = "ingress-nginx"
  create_namespace = true

  # The NLB takes a few minutes to become active and the chart's readiness
  # gate does not wait for it; without this, dependent resources race it.
  wait    = true
  timeout = 900

  values = [yamlencode({
    controller = {
      ingressClassResource = {
        name    = var.ingress_class
        enabled = true
        default = true
      }

      service = {
        type = "LoadBalancer"
        annotations = {
          # NLB, not the legacy Classic ELB the chart would otherwise get.
          "service.beta.kubernetes.io/aws-load-balancer-type"            = "external"
          "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "instance"
          "service.beta.kubernetes.io/aws-load-balancer-scheme"          = "internet-facing"
        }
      }

      # Two nodes, and the controller is the only path in — one replica per
      # node so a Spot reclamation cannot take the entire ingress with it.
      replicaCount = 2

      # Spot nodes get reclaimed; spread rather than stack.
      topologySpreadConstraints = [{
        maxSkew           = 1
        topologyKey       = "kubernetes.io/hostname"
        whenUnsatisfiable = "ScheduleAnyway"
        labelSelector = {
          matchLabels = {
            "app.kubernetes.io/name"      = "ingress-nginx"
            "app.kubernetes.io/component" = "controller"
          }
        }
      }]

      resources = {
        requests = {
          cpu    = "100m"
          memory = "128Mi"
        }
        limits = {
          memory = "384Mi"
        }
      }
    }
  })]
}

########################################
# ArgoCD
########################################
# The RHDH chart is deployed BY ArgoCD, not by Terraform. Terraform's job ends
# at installing the thing that does continuous delivery; putting the app here
# too would give it two owners that fight over the same objects.

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_version
  namespace        = var.argocd_namespace
  create_namespace = true

  wait    = true
  timeout = 900

  values = [yamlencode({
    # Single-instance, non-HA. HA mode wants three Redis replicas and more
    # controller memory than a two-node t3.medium cluster has to spare.
    redis-ha = { enabled = false }
    controller = {
      replicas = 1
      resources = {
        requests = { cpu = "100m", memory = "256Mi" }
        limits   = { memory = "1Gi" }
      }
    }
    repoServer = {
      replicas = 1
      resources = {
        requests = { cpu = "50m", memory = "128Mi" }
        limits   = { memory = "512Mi" }
      }
    }
    applicationSet = {
      replicas = 1
    }
    server = {
      replicas = 1
      resources = {
        requests = { cpu = "50m", memory = "128Mi" }
        limits   = { memory = "256Mi" }
      }
      # No Ingress for the ArgoCD UI. It would need its own hostname and a
      # certificate, and the admin password is a Secret in the cluster —
      # reach it with `kubectl port-forward` instead. See outputs.tf.
      ingress = { enabled = false }
    }
    configs = {
      params = {
        # Terminate TLS at the NLB/ingress, not in argocd-server. Without this
        # the server redirects to HTTPS behind a proxy that already did TLS
        # and you get a redirect loop.
        "server.insecure" = true
      }
    }
  })]

  # ArgoCD's CRDs and the ingress controller are independent, but installing
  # them concurrently on a two-node cluster tends to make both slow and one
  # of them time out. Serialise.
  depends_on = [helm_release.ingress_nginx]
}
