locals {
  mt_ocid = var.create_mount_target ? oci_file_storage_mount_target.kubeflow_mount_target[0].id : var.create_mount_target
}



output "mt_ocid" {
  value = local.mt_ocid
}


