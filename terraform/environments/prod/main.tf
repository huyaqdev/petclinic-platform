# Module composition for the prod environment — populated in E-2 onward (PETPLAT-10, PETPLAT-17, PETPLAT-27).

module "vpc" {
  source = "../../modules/vpc"

  project             = var.project
  environment         = var.environment
  vpc_cidr            = var.vpc_cidr
  public_subnet_cidrs = var.public_subnet_cidrs
  availability_zones  = var.availability_zones
}
