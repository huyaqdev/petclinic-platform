locals {
  name_prefix = "${var.project}-${var.environment}"

  tags = merge(var.tags, {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}

# ---------------------------------------------------------------------------
# VPC, Internet Gateway, public subnets, routing
# ---------------------------------------------------------------------------

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-vpc"
  })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-igw"
  })
}

resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.tags, {
    Name                                         = "${local.name_prefix}-public-${var.availability_zones[count.index]}"
    "kubernetes.io/cluster/${local.name_prefix}" = "shared"
    "kubernetes.io/role/elb"                     = "1"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  count = length(var.public_subnet_cidrs)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ---------------------------------------------------------------------------
# Security groups — the primary access control boundary (all-public design,
# see ADR-0001). Rules are defined as standalone rule resources rather than
# inline blocks so the cluster/node security groups can reference each other
# without a dependency cycle.
# ---------------------------------------------------------------------------

resource "aws_security_group" "eks_cluster" {
  name        = "${local.name_prefix}-eks-cluster-sg"
  description = "EKS control plane security group"
  vpc_id      = aws_vpc.main.id

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-eks-cluster-sg"
  })
}

resource "aws_security_group" "eks_node" {
  name        = "${local.name_prefix}-eks-node-sg"
  description = "EKS worker node security group"
  vpc_id      = aws_vpc.main.id

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-eks-node-sg"
  })
}

resource "aws_security_group" "rds" {
  name        = "${local.name_prefix}-rds-sg"
  description = "RDS MySQL security group"
  vpc_id      = aws_vpc.main.id

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-rds-sg"
  })
}

resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "ALB security group"
  vpc_id      = aws_vpc.main.id

  tags = merge(local.tags, {
    Name = "${local.name_prefix}-alb-sg"
  })
}

# --- EKS cluster SG rules ---------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "cluster_from_node_https" {
  security_group_id            = aws_security_group.eks_cluster.id
  description                  = "API server access from EKS nodes"
  referenced_security_group_id = aws_security_group.eks_node.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443

  tags = merge(local.tags, { Name = "${local.name_prefix}-eks-cluster-from-node-https" })
}

resource "aws_vpc_security_group_egress_rule" "cluster_egress_all" {
  security_group_id = aws_security_group.eks_cluster.id
  description       = "All outbound"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"

  tags = merge(local.tags, { Name = "${local.name_prefix}-eks-cluster-egress-all" })
}

# --- EKS node SG rules -------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "node_from_cluster_all" {
  security_group_id            = aws_security_group.eks_node.id
  description                  = "All traffic from EKS cluster SG"
  referenced_security_group_id = aws_security_group.eks_cluster.id
  ip_protocol                  = "-1"

  tags = merge(local.tags, { Name = "${local.name_prefix}-eks-node-from-cluster-all" })
}

resource "aws_vpc_security_group_ingress_rule" "node_self" {
  security_group_id            = aws_security_group.eks_node.id
  description                  = "Inter-node communication"
  referenced_security_group_id = aws_security_group.eks_node.id
  ip_protocol                  = "-1"

  tags = merge(local.tags, { Name = "${local.name_prefix}-eks-node-self" })
}

resource "aws_vpc_security_group_ingress_rule" "node_nodeport_from_alb" {
  security_group_id            = aws_security_group.eks_node.id
  description                  = "NodePort services from ALB"
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = 30000
  to_port                      = 32767

  tags = merge(local.tags, { Name = "${local.name_prefix}-eks-node-nodeport-from-alb" })
}

resource "aws_vpc_security_group_egress_rule" "node_egress_all" {
  security_group_id = aws_security_group.eks_node.id
  description       = "All outbound"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"

  tags = merge(local.tags, { Name = "${local.name_prefix}-eks-node-egress-all" })
}

# --- RDS SG rules -------------------------------------------------------------
# No egress rules — RDS never needs to initiate outbound connections here.

resource "aws_vpc_security_group_ingress_rule" "rds_from_node_mysql" {
  security_group_id            = aws_security_group.rds.id
  description                  = "MySQL from EKS nodes only"
  referenced_security_group_id = aws_security_group.eks_node.id
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306

  tags = merge(local.tags, { Name = "${local.name_prefix}-rds-from-node-mysql" })
}

# --- ALB SG rules ---------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from internet"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80

  tags = merge(local.tags, { Name = "${local.name_prefix}-alb-http" })
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS from internet"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443

  tags = merge(local.tags, { Name = "${local.name_prefix}-alb-https" })
}

resource "aws_vpc_security_group_egress_rule" "alb_to_nodeport" {
  security_group_id            = aws_security_group.alb.id
  description                  = "To EKS nodes target group (NodePort range)"
  referenced_security_group_id = aws_security_group.eks_node.id
  ip_protocol                  = "tcp"
  from_port                    = 30000
  to_port                      = 32767

  tags = merge(local.tags, { Name = "${local.name_prefix}-alb-to-nodeport" })
}

resource "aws_vpc_security_group_egress_rule" "alb_healthcheck" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Health checks to EKS nodes"
  referenced_security_group_id = aws_security_group.eks_node.id
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080

  tags = merge(local.tags, { Name = "${local.name_prefix}-alb-healthcheck" })
}
