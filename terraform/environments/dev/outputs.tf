# Root outputs for the dev environment — populated as modules are wired in.

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnet_ids
}

output "eks_cluster_sg_id" {
  description = "EKS cluster (control plane) security group ID"
  value       = module.vpc.eks_cluster_sg_id
}

output "eks_node_sg_id" {
  description = "EKS worker node security group ID"
  value       = module.vpc.eks_node_sg_id
}

output "rds_sg_id" {
  description = "RDS security group ID"
  value       = module.vpc.rds_sg_id
}

output "alb_sg_id" {
  description = "ALB security group ID"
  value       = module.vpc.alb_sg_id
}

output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = module.eks.cluster_endpoint
}

output "eks_cluster_ca_certificate" {
  description = "EKS cluster CA certificate (base64)"
  value       = module.eks.cluster_ca_certificate
  sensitive   = true
}

output "eks_cluster_security_group_id" {
  description = "EKS cluster auto-created security group (control-plane-to-data-plane)"
  value       = module.eks.cluster_security_group_id
}

output "eks_ebs_csi_role_arn" {
  description = "IRSA role ARN for the EBS CSI Driver add-on"
  value       = module.eks.ebs_csi_role_arn
}

output "eks_oidc_provider_arn" {
  description = "OIDC provider ARN (for IRSA trust policies)"
  value       = module.eks.oidc_provider_arn
}

output "eks_oidc_provider_url" {
  description = "OIDC provider issuer URL (for IRSA trust policies)"
  value       = module.eks.oidc_provider_url
}

output "eks_node_group_name" {
  description = "Managed node group name"
  value       = module.eks.node_group_name
}

output "eks_node_role_arn" {
  description = "Node IAM role ARN"
  value       = module.eks.node_role_arn
}

output "eks_kubeconfig_command" {
  description = "Command to configure kubectl for this cluster"
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.aws_region}"
}

output "ecr_repository_urls" {
  description = "Map of service_name → ECR repository URL"
  value       = module.ecr.repository_urls
}

output "ecr_repository_arns" {
  description = "Map of service_name → ECR repository ARN"
  value       = module.ecr.repository_arns
}

output "ecr_image_tag_mutability" {
  description = "Tag mutability applied to all dev ECR repositories"
  value       = module.ecr.image_tag_mutability
}

output "rds_endpoint" {
  description = "RDS endpoint hostname"
  value       = module.rds.endpoint
}

output "rds_port" {
  description = "RDS port"
  value       = module.rds.port
}

output "rds_instance_id" {
  description = "RDS instance ID"
  value       = module.rds.db_instance_id
}

output "rds_secret_arn" {
  description = "Secrets Manager secret ARN for RDS credentials"
  value       = module.rds.secret_arn
}
