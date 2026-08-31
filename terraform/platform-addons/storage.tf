########################################
# Storage class
########################################
# This IS the cluster default, and it has to be. The original reasoning here
# was that EKS ships a gp2 class which might already be default, and two
# defaults make the winner undefined — true in general, false on this cluster:
# `kubectl get sc` shows gp2 present but NOT marked default, so leaving gp3
# unmarked left the cluster with no default at all.
#
# That is not a cosmetic gap. The RHDH chart mounts its dynamic-plugins-root
# as a generic ephemeral volume with no storageClassName, so with no default
# the PVC never binds and the portal sits Pending forever on
# "pod has unbound immediate PersistentVolumeClaims". Naming a class in values
# only covers the volumes whose class we control; this covers the rest.
#
# gp3 over gp2: same durability, ~20% cheaper per GiB, and baseline 3000 IOPS
# instead of 100 for a small volume — which matters when the volume is a
# database. gp2 also still uses the deprecated in-tree provisioner.

resource "kubernetes_storage_class" "gp3" {
  metadata {
    name = "gp3"

    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
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
