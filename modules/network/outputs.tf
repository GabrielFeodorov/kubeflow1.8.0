output "vcn-id" {
  value = var.useExistingVcn ? var.myVcn : oci_core_vcn.kubeflow_vcn.0.id
}

output "private-id" {
  value = var.useExistingVcn ? var.privateSubnet : oci_core_subnet.private.0.id
}

output "edge-id" {
  value = var.useExistingVcn ? var.edgeSubnet : oci_core_subnet.edge.0.id
}

output "fss-id" {
  value = var.useExistingVcn ? var.FssSubnet : oci_core_subnet.file_system.0.id
}
