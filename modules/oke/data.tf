# Gets a list of Availability Domains
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}
data "oci_containerengine_node_pool_option" "np_option" {
  node_pool_option_id = var.create_new_oke_cluster ? oci_containerengine_cluster.oke_kubeflow_cluster[0].id : var.existing_oke_cluster_id
}
