data "oci_identity_availability_domains" "adz" {
  compartment_id = var.compartment_ocid
}
resource "oci_file_storage_mount_target" "kubeflow_mount_target" {
  count               = var.create_mount_target ? 1 : 0
  availability_domain = data.template_file.ad_names.*.rendered[0]
  compartment_id      = var.compartment_ocid
  subnet_id           = var.subnet_id
}
