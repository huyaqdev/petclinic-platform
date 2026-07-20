variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "prod"
}

variable "project" {
  description = "Project name, used for resource naming and tagging"
  type        = string
  default     = "petclinic"
}

variable "vpc_cidr" {
  description = "CIDR block for the prod VPC"
  type        = string
  default     = "10.1.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the prod public subnets, one per availability zone"
  type        = list(string)
  default     = ["10.1.1.0/24", "10.1.2.0/24"]
}

variable "availability_zones" {
  description = "Availability zones for the prod public subnets"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "ecr_service_names" {
  description = "Service names to create ECR repositories for"
  type        = list(string)
  default     = ["config-server", "discovery-server", "api-gateway", "customers-service", "visits-service", "vets-service", "genai-service", "admin-server"]
}

variable "ecr_image_tag_mutability" {
  description = "Tag mutability for prod ECR repositories"
  type        = string
  default     = "IMMUTABLE"
}

variable "rds_instance_class" {
  description = "RDS instance class for prod (same as dev — free tier, cost optimization for learning; a real prod would size up)"
  type        = string
  default     = "db.t4g.micro"
}

variable "rds_allocated_storage" {
  description = "Initial RDS allocated storage for prod, in GB"
  type        = number
  default     = 20
}

variable "rds_max_allocated_storage" {
  description = "Maximum RDS autoscaled storage for prod, in GB"
  type        = number
  default     = 20
}

variable "rds_multi_az" {
  description = "Multi-AZ deployment for prod RDS (false — single-AZ to save cost; a real prod would enable Multi-AZ)"
  type        = bool
  default     = false
}

# PETPLAT-27's acceptance criteria call for 30-day retention and a final
# snapshot on delete for prod, which is stricter than the summary table in
# docs/technical-spec.md#rds-database (7 days / skip=true for both envs).
# Following the story ACs here since they're the more specific, deliberate
# spec for the prod/dev split; the spec table appears to predate that split.
variable "rds_backup_retention_period" {
  description = "RDS automated backup retention for prod, in days"
  type        = number
  default     = 30
}

variable "rds_skip_final_snapshot" {
  description = "Skip final snapshot on prod RDS destroy (false — prod keeps a final snapshot)"
  type        = bool
  default     = false
}

variable "rds_deletion_protection" {
  # false for both envs per docs/technical-spec.md#rds-database and PETPLAT-27's
  # acceptance criteria (neither asks for it enabled) — deliberate, not an
  # oversight alongside the stricter backup/snapshot settings above. A real
  # production database would enable this.
  description = "Deletion protection for prod RDS"
  type        = bool
  default     = false
}
