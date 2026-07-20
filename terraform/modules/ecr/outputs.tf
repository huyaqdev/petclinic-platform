output "repository_urls" {
  description = "Map of service_name → ECR repository URL"
  value       = { for name, repo in aws_ecr_repository.this : name => repo.repository_url }
}

output "repository_arns" {
  description = "Map of service_name → ECR repository ARN"
  value       = { for name, repo in aws_ecr_repository.this : name => repo.arn }
}

output "environment" {
  description = "Environment these repositories were created for"
  value       = var.environment
}

output "image_tag_mutability" {
  description = "Tag mutability applied to every repository in this environment"
  value       = var.image_tag_mutability
}
