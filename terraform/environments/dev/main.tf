# Module composition for the dev environment — populated in E-2 onward (PETPLAT-9, PETPLAT-15, PETPLAT-20, PETPLAT-25, PETPLAT-32).

module "vpc" {
  source = "../../modules/vpc"

  project             = var.project
  environment         = var.environment
  vpc_cidr            = var.vpc_cidr
  public_subnet_cidrs = var.public_subnet_cidrs
  availability_zones  = var.availability_zones
}
