locals {
  name_prefix = "${var.project}-${var.environment}"

  tags = merge(var.tags, {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}

# ---------------------------------------------------------------------------
# Route 53 hosted zone (PETPLAT-28)
# ---------------------------------------------------------------------------

resource "aws_route53_zone" "this" {
  name    = var.domain_name
  comment = "Managed by Terraform — ${local.name_prefix}"

  tags = merge(local.tags, { Name = "${local.name_prefix}-zone" })
}

# ---------------------------------------------------------------------------
# ACM certificate — wildcard, DNS-validated against the zone above. Requested
# in us-east-1, the same region as the ALB (unlike CloudFront, ALB certs must
# live in the region the load balancer itself is created in).
# ---------------------------------------------------------------------------

resource "aws_acm_certificate" "this" {
  domain_name               = "*.${var.domain_name}"
  subject_alternative_names = [var.domain_name]
  validation_method         = "DNS"

  tags = merge(local.tags, { Name = "${local.name_prefix}-cert" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.this.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id         = aws_route53_zone.this.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "this" {
  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}
