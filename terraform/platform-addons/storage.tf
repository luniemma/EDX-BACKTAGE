########################################
# Storage class
########################################
# Deliberately NOT marked as the cluster default. EKS ships its own gp2 class
# and, depending on version, may or may not mark it default; adding a second
# default makes which one wins undefined. The RHDH values name this class
# explicitly instead, so binding is deterministic either way.
#
# gp3 over gp2: same durability, ~20% cheaper per GiB, and baseline 3000 IOPS
# instead of 100 for a small volume — which matters when the volume is a
# database.

resource "kubernetes_storage_class" "gp3" {
  metadata {
    name = "gp3"
  }

  storage_provisioner = "ebs.csi.aws.com"

  # Retain would leave orphaned EBS volumes billing after a namespace is
  # deleted. Nothing here is a system of record.
  reclaim_policy = "Delete"

  # EBS volumes are zonal. Binding at first consumer lets the scheduler place
  # the pod first and then create the volume in whatever AZ it landed in;
  # Immediate would risk creating the volume where no node can attach it.
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    type      = "gp3"
    encrypted = "true"
    fsType    = "ext4"
  }
}
