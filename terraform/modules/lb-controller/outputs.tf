output "role_arn" {
  description = "IRSA role ARN for the aws-load-balancer-controller service account"
  value       = aws_iam_role.this.arn
}

output "policy_arn" {
  description = "IAM policy ARN granting AWS Load Balancer Controller permissions"
  value       = aws_iam_policy.this.arn
}
