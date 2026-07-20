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

variable "subnet_ids" {
  description = "Subnet IDs for the DB subnet group (public subnets, all-public design — see ADR-0001)"
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group ID attached to the RDS instance (from the vpc module — allows 3306 from EKS node SG only)"
  type        = string
}

variable "instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t4g.micro"
}

variable "engine_version" {
  description = "MySQL engine version"
  type        = string
  default     = "8.0"
}

variable "allocated_storage" {
  description = "Initial allocated storage, in GB"
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Maximum autoscaled storage, in GB"
  type        = number
  default     = 20
}

variable "multi_az" {
  description = "Whether to deploy a Multi-AZ standby replica"
  type        = bool
  default     = false
}

variable "backup_retention_period" {
  description = "Number of days to retain automated backups"
  type        = number
  default     = 7
}

variable "skip_final_snapshot" {
  description = "Skip taking a final snapshot when the instance is destroyed"
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "Enable deletion protection on the RDS instance"
  type        = bool
  default     = false
}

variable "master_username" {
  description = "Master username for the RDS instance"
  type        = string
  default     = "petclinic"
}

variable "tags" {
  description = "Additional tags to merge into every resource"
  type        = map(string)
  default     = {}
}
