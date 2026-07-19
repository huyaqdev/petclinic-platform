output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_ca_certificate" {
  description = "EKS cluster CA certificate (base64)"
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN (for IRSA trust policies)"
  value       = aws_iam_openid_connect_provider.cluster.arn
}

output "oidc_provider_url" {
  description = "OIDC provider issuer URL (for IRSA trust policies)"
  value       = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

output "node_group_name" {
  description = "Managed node group name"
  value       = aws_eks_node_group.main.node_group_name
}

output "node_role_arn" {
  description = "Node IAM role ARN"
  value       = aws_iam_role.node.arn
}

output "cluster_security_group_id" {
  description = "Cluster security group automatically created by EKS (control-plane-to-data-plane communication)"
  value       = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}

output "ebs_csi_role_arn" {
  description = "IRSA role ARN for the EBS CSI Driver add-on"
  value       = aws_iam_role.ebs_csi.arn
}
