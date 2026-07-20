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

variable "service_names" {
  description = "Service names to create ECR repositories for, one repo per name under petclinic-{env}/"
  type        = list(string)
}

variable "image_tag_mutability" {
  description = "Tag mutability for all repositories (MUTABLE for dev, IMMUTABLE for prod)"
  type        = string
  default     = "MUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be \"MUTABLE\" or \"IMMUTABLE\"."
  }
}

variable "max_image_count" {
  description = "Number of images to retain per repository before the oldest are expired"
  type        = number
  default     = 10
}

variable "untagged_image_expiry_days" {
  description = "Days after which untagged images are expired"
  type        = number
  default     = 7
}

variable "tags" {
  description = "Additional tags to merge into every resource"
  type        = map(string)
  default     = {}
}
