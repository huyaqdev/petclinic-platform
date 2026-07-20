variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
}

variable "project" {
  description = "Project name, used for resource naming and tagging"
  type        = string
  default     = "petclinic"
}

variable "vpc_cidr" {
  description = "CIDR block for the dev VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the dev public subnets, one per availability zone"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "availability_zones" {
  description = "Availability zones for the dev public subnets"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "ecr_service_names" {
  description = "Service names to create ECR repositories for"
  type        = list(string)
  default     = ["config-server", "discovery-server", "api-gateway", "customers-service", "visits-service", "vets-service", "genai-service", "admin-server"]
}

variable "ecr_image_tag_mutability" {
  description = "Tag mutability for dev ECR repositories"
  type        = string
  default     = "MUTABLE"
}

variable "rds_instance_class" {
  description = "RDS instance class for dev"
  type        = string
  default     = "db.t4g.micro"
}

variable "rds_allocated_storage" {
  description = "Initial RDS allocated storage for dev, in GB"
  type        = number
  default     = 20
}

variable "rds_max_allocated_storage" {
  description = "Maximum RDS autoscaled storage for dev, in GB"
  type        = number
  default     = 20
}

variable "rds_multi_az" {
  description = "Multi-AZ deployment for dev RDS (false — cost optimization for learning)"
  type        = bool
  default     = false
}

variable "rds_backup_retention_period" {
  description = "RDS automated backup retention for dev, in days"
  type        = number
  default     = 7
}

variable "rds_skip_final_snapshot" {
  description = "Skip final snapshot on dev RDS destroy"
  type        = bool
  default     = true
}

variable "rds_deletion_protection" {
  description = "Deletion protection for dev RDS"
  type        = bool
  default     = false
}
