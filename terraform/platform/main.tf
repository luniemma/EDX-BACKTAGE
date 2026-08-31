########################################
# Networking
########################################
# Public subnets only, and no NAT gateway. A NAT gateway is ~$33/month per AZ
# before data processing, which is a third of this profile's entire budget, so
# nodes sit in public subnets and reach the internet through the IGW directly.
#
# The trade: nodes carry public IPs. Their security group still allows no
# inbound from the internet — only the cluster security group and the node
# group's own rules — so exposure is the API surface of the kubelet, not the
# workloads. Moving to private subnets + NAT is the first thing to change if
# this ever holds anything sensitive.

data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # /20 per AZ out of a /16 — 4091 usable addresses each. The VPC CNI hands a
  # VPC address to every pod, so subnets need to be generous relative to pod
  # count, not node count.
  public_subnets = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 4, i)]

  # Offset by 8 so public and private never collide as az_count grows.
  #
  # These carry no NAT gateway and no route to the internet, and that costs
  # nothing: a subnet is free, only the NAT is not. RDS needs no outbound
  # internet access, so the database gets proper private isolation without
  # reintroducing the $33/month this profile was built to avoid.
  private_subnets = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 4, i + 8)]
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = var.name
  cidr = var.vpc_cidr

  azs             = local.azs
  public_subnets  = local.public_subnets
  private_subnets = local.private_subnets

  # Nodes need a routable address on launch; there is no NAT to fall back to.
  map_public_ip_on_launch = true

  enable_nat_gateway = false
  enable_vpn_gateway = false

  # Required for EKS: pods resolve the cluster endpoint and each other by name.
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Lets the AWS load balancer controller and the in-tree service controller
  # find these subnets when a Service of type LoadBalancer asks for one.
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
}

########################################
# EKS
########################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.name
  kubernetes_version = var.kubernetes_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnets

  # There is no private path into this VPC — no NAT, no bastion, no VPN — so a
  # private-only endpoint would lock everyone out, including this Terraform.
  # Restrict by CIDR instead; see var.public_access_cidrs.
  endpoint_public_access       = true
  endpoint_public_access_cidrs = var.public_access_cidrs
  endpoint_private_access      = true

  # Grants the identity running this apply cluster-admin via an access entry,
  # so the addons root can authenticate immediately afterwards without a
  # separate aws-auth ConfigMap dance.
  #
  # It is also a drift generator, which is why var.cluster_admin_principals
  # exists below. "Cluster creator" is resolved at apply time from whoever is
  # running Terraform, so the entry moves: apply locally and it is your user,
  # apply from CI and it becomes edx-rhdh-tf-apply, and the previous holder
  # silently loses access. That happened here — a CI apply from main revoked a
  # developer's access mid-session and kubectl started returning Unauthorized
  # with nothing in the diff to explain it.
  enable_cluster_creator_admin_permissions = true

  # Admin that does NOT depend on who ran the last apply. Anything listed here
  # keeps cluster-admin no matter which identity applies, so restoring access
  # by hand — which is itself drift the next apply reverts — stops being
  # necessary.
  access_entries = {
    for arn in var.cluster_admin_principals : trimprefix(
      replace(arn, ":", "-"), "arn-aws-iam--"
      ) => {
      principal_arn = arn
      policy_associations = {
        admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }

  # Control plane logs go to CloudWatch and are billed twice over: once on
  # ingestion, then again on storage for as long as they are retained. The
  # module defaults to 90 days of retention and includes the audit log, which
  # is the expensive half of the ingestion — see var.enabled_cluster_log_types.
  # A week of retention is enough to debug a bad rollout.
  enabled_log_types                      = var.enabled_cluster_log_types
  cloudwatch_log_group_retention_in_days = 7

  # Managed addons. All four are free; coredns and kube-proxy are required for
  # a functioning cluster and vpc-cni is what gives pods VPC addresses.
  #
  # `before_compute` is load-bearing, not a tuning knob. The module creates
  # after-compute addons only once the node group reports ACTIVE, and a node
  # cannot become Ready without a CNI ("cni plugin not initialized"), so
  # leaving vpc-cni until after compute deadlocks: the node group waits the
  # full hour for nodes that are waiting for the addon that is waiting for the
  # node group. kube-proxy joins it because a node with no kube-proxy has no
  # Service networking.
  #
  # coredns stays after compute deliberately — it is a Deployment, not a
  # DaemonSet, so it needs a schedulable node to exist first.
  addons = {
    vpc-cni = {
      before_compute = true
    }
    kube-proxy = {
      before_compute = true
    }
    coredns                = {}
    eks-pod-identity-agent = {}
  }

  eks_managed_node_groups = {
    default = {
      # Spot at roughly a third of on-demand. RHDH tolerates a node going away
      # — it is a stateless Deployment behind a Service — and ArgoCD will
      # re-place anything evicted. Do not move a database onto this node group.
      capacity_type  = "SPOT"
      instance_types = var.node_instance_types

      # Named explicitly, and this is load-bearing rather than cosmetic. Left
      # to the module the role is named from the node group KEY, giving
      # "default-eks-node-group-<hash>" — which does not match the
      # "edx-rhdh-*" prefix the CI roles are scoped to. The first CI teardown
      # failed on exactly that:
      #
      #   AccessDenied: edx-rhdh-tf-apply is not authorized to perform:
      #   iam:DetachRolePolicy on role default-eks-node-group-125f437...
      #
      # and left the role orphaned. Creation never hit it because the cluster
      # was first built from a broadly privileged developer identity.
      iam_role_name            = "${var.name}-node"
      iam_role_use_name_prefix = false

      min_size     = var.node_min_size
      max_size     = var.node_max_size
      desired_size = var.node_desired_size

      # NOT `disk_size`. This module builds a custom launch template by
      # default, and the node group's disk_size is silently ignored when it
      # does — nodes would come up on the AMI default of 20 GiB. The root
      # volume has to be set on the launch template instead.
      block_device_mappings = {
        root = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = var.node_disk_size
            volume_type           = "gp3"
            encrypted             = true
            delete_on_termination = true
          }
        }
      }

      labels = {
        "workload" = "general"
      }
    }
  }
}
