output "zone_id" {
  description = "Route 53 hosted zone ID"
  value       = aws_route53_zone.this.zone_id
}

output "name_servers" {
  description = "Route 53 name servers — delegate the domain's registrar NS records to these"
  value       = aws_route53_zone.this.name_servers
}

output "certificate_arn" {
  description = "Validated ACM certificate ARN (wildcard, DNS-validated)"
  value       = aws_acm_certificate_validation.this.certificate_arn
}
