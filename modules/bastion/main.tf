data "oci_identity_availability_domains" "adz" {
  compartment_id = var.compartment_ocid
}

resource "oci_core_instance" "bastion" {
  #availability_domain = data.oci_identity_availability_domains.adz.availability_domains[var.availability_domain].name
  availability_domain = data.template_file.ad_names.*.rendered[0]
  compartment_id      = var.compartment_ocid
  shape               = var.instance_shape
  display_name        = var.instance_name

  dynamic "shape_config" {
    for_each = var.is_flex_bastion_shape ? [1] : []
    content {
      ocpus         = var.bastion_shape_config_ocpus
      memory_in_gbs = var.bastion_shape_config_memory_in_gbs
    }
  }
  source_details {
    source_id   = var.image_id
    source_type = "image"
  }

  create_vnic_details {
    subnet_id        = var.subnet_id
    assign_public_ip = var.public_edge_node
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data           = var.user_data
  }

  extended_metadata = {
    oke_cluster_id      = var.oke_cluster_id
    nodepool_id         = var.nodepool_id
    tenancy_ocid        = var.tenancy_ocid
    namespace           = var.namespace
    kube_label          = var.kube_label
    kubeflow_password   = var.kubeflow_password
    availability_domain = data.template_file.ad_names.*.rendered[0]
    mount_target        = var.create_mount_target ? var.mount_target_id : "not_using"
    kustomize_version   = var.kustomize_version
    kubeflow_version    = var.kubeflow_version
    load_balancer_ip    = var.reserved_public_ip
    configure_oracle_auth = var.configure_oracle_auth
    oci_domain = var.oci_domain
    client_id = var.oci_client_id
    client_secret = var.oci_client_secret
  }
}
