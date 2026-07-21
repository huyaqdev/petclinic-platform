# Module composition for the dev environment — populated in E-2 onward (PETPLAT-9, PETPLAT-15, PETPLAT-20, PETPLAT-25, PETPLAT-32).

module "vpc" {
  source = "../../modules/vpc"

  project             = var.project
  environment         = var.environment
  vpc_cidr            = var.vpc_cidr
  public_subnet_cidrs = var.public_subnet_cidrs
  availability_zones  = var.availability_zones
}

module "eks" {
  source = "../../modules/eks"

  project     = var.project
  environment = var.environment

  subnet_ids    = module.vpc.public_subnet_ids
  cluster_sg_id = module.vpc.eks_cluster_sg_id
  node_sg_id    = module.vpc.eks_node_sg_id
}

module "ecr" {
  source = "../../modules/ecr"

  project     = var.project
  environment = var.environment

  service_names        = var.ecr_service_names
  image_tag_mutability = var.ecr_image_tag_mutability
}

module "rds" {
  source = "../../modules/rds"

  project     = var.project
  environment = var.environment

  subnet_ids        = module.vpc.public_subnet_ids
  security_group_id = module.vpc.rds_sg_id

  instance_class          = var.rds_instance_class
  allocated_storage       = var.rds_allocated_storage
  max_allocated_storage   = var.rds_max_allocated_storage
  multi_az                = var.rds_multi_az
  backup_retention_period = var.rds_backup_retention_period
  skip_final_snapshot     = var.rds_skip_final_snapshot
  deletion_protection     = var.rds_deletion_protection
}

# Hosted zone + ACM cert (PETPLAT-28/32). Only wired into dev for now — the
# spec's Route 53 table has both the dev and prod records living in the same
# zone, and there is no "wire DNS module into prod" story yet.
module "dns" {
  source = "../../modules/dns"

  project     = var.project
  environment = var.environment
  domain_name = var.domain_name
}

module "lb_controller" {
  source = "../../modules/lb-controller"

  project     = var.project
  environment = var.environment

  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
}
