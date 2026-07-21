# ---------------------------------------------------------------------------
# Route 53 alias record for the ALB provisioned by the AWS Load Balancer
# Controller from the Ingress in k8s/base/ingress/ingress.yaml (PETPLAT-31).
#
# The ALB itself is NOT a Terraform resource — it's created by the in-cluster
# controller when the Ingress is applied. This data source finds it by the
# deterministic name set via the Ingress's
# alb.ingress.kubernetes.io/load-balancer-name annotation, so it can only
# resolve once that Ingress has actually been applied and the ALB exists.
# Gated behind var.create_app_dns_record (default false) so a normal
# `terraform apply` doesn't fail before that point.
#
# Apply order:
#   1. terraform apply                          (VPC/EKS/DNS/LB-controller IAM role)
#   2. scripts/install-lb-controller.sh dev      (installs the controller)
#   3. kubectl apply -f k8s/base/ingress/        (creates the ALB)
#   4. set create_app_dns_record = true, terraform apply again (this record is created)
# ---------------------------------------------------------------------------

data "aws_lb" "ingress" {
  count = var.create_app_dns_record ? 1 : 0
  name  = "petclinic-${var.environment}-alb"
}

resource "aws_route53_record" "app" {
  count = var.create_app_dns_record ? 1 : 0

  zone_id = module.dns.zone_id
  name    = "petclinic-${var.environment}.${var.domain_name}"
  type    = "A"

  alias {
    name                   = data.aws_lb.ingress[0].dns_name
    zone_id                = data.aws_lb.ingress[0].zone_id
    evaluate_target_health = true
  }
}
