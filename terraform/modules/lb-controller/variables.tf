variable "project" {
  description = "Project name, used for resource naming and tagging"
  type        = string
  default     = "petclinic"
}

variable "environment" {
  description = "Deployment environment"
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be \"dev\" or \"prod\"."
  }
}

variable "oidc_provider_arn" {
  description = "EKS cluster OIDC provider ARN (from the eks module), used in the IRSA trust policy"
  type        = string
}

variable "oidc_provider_url" {
  description = "EKS cluster OIDC provider issuer URL (from the eks module), used in the IRSA trust policy"
  type        = string
}

variable "tags" {
  description = "Additional tags to merge into every resource"
  type        = map(string)
  default     = {}
}
