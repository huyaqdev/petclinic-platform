locals {
  name_prefix  = "${var.project}-${var.environment}"
  cluster_name = local.name_prefix

  tags = merge(var.tags, {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  })

  # EKS managed add-ons kept in Terraform (PETPLAT-84). Versions are pinned to
  # the EKS-recommended default for the cluster's K8s version unless overridden
  # via var.addon_versions — never "most recent".
  addon_names = ["coredns", "kube-proxy", "vpc-cni", "aws-ebs-csi-driver"]

  oidc_provider_url = replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")
}

data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# Cluster IAM role
# ---------------------------------------------------------------------------

resource "aws_iam_role" "cluster" {
  name = "${local.name_prefix}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "cluster_eks_cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ---------------------------------------------------------------------------
# EKS cluster — public subnets only (all-public design, see ADR-0001).
# The cluster SG is passed in from the vpc module so the control-plane
# ingress/egress rules defined there actually take effect.
# ---------------------------------------------------------------------------

resource "aws_eks_cluster" "main" {
  name     = local.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.cluster_version

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = [var.cluster_sg_id]
  }

  access_config {
    authentication_mode                         = var.authentication_mode
    bootstrap_cluster_creator_admin_permissions = false
  }

  enabled_cluster_log_types = var.cluster_log_types

  tags = merge(local.tags, { Name = local.cluster_name })

  depends_on = [
    aws_iam_role_policy_attachment.cluster_eks_cluster_policy,
  ]
}

# ---------------------------------------------------------------------------
# OIDC provider — required for IRSA (IAM Roles for Service Accounts)
# ---------------------------------------------------------------------------

data "tls_certificate" "cluster" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "cluster" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.cluster.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer

  tags = local.tags
}

# ---------------------------------------------------------------------------
# Cluster access for the deploying IAM principal (PETPLAT-14). Managed as an
# explicit access entry rather than bootstrap_cluster_creator_admin_permissions
# so it's reproducible from any principal running `terraform apply`, not just
# whichever one happened to create the cluster.
# ---------------------------------------------------------------------------

resource "aws_eks_access_entry" "deployer" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = data.aws_caller_identity.current.arn

  tags = local.tags
}

resource "aws_eks_access_policy_association" "deployer_admin" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = data.aws_caller_identity.current.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}

# ---------------------------------------------------------------------------
# Node IAM role
# ---------------------------------------------------------------------------

resource "aws_iam_role" "node" {
  name = "${local.name_prefix}-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "node_worker_node_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr_read_only" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# ---------------------------------------------------------------------------
# Managed node group — launch template attaches the vpc module's node SG
# (the automatic cluster SG alone doesn't carry the node-self/ALB-nodeport
# rules defined there) and enforces IMDSv2 + encrypted root volumes.
# ---------------------------------------------------------------------------

resource "aws_launch_template" "node" {
  name_prefix = "${local.name_prefix}-node-"

  vpc_security_group_ids = [var.node_sg_id]

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = var.node_disk_size
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.tags, { Name = "${local.name_prefix}-node" })
  }

  tags = local.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${local.name_prefix}-nodes"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.subnet_ids

  ami_type       = var.node_ami_type
  capacity_type  = var.node_capacity_type
  instance_types = var.node_instance_types

  scaling_config {
    min_size     = var.node_min_size
    max_size     = var.node_max_size
    desired_size = var.node_desired_size
  }

  launch_template {
    id      = aws_launch_template.node.id
    version = aws_launch_template.node.latest_version
  }

  labels = {
    environment  = var.environment
    "managed-by" = "terraform"
  }

  dynamic "taint" {
    for_each = var.node_taints
    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }

  tags = local.tags

  depends_on = [
    aws_iam_role_policy_attachment.node_worker_node_policy,
    aws_iam_role_policy_attachment.node_cni_policy,
    aws_iam_role_policy_attachment.node_ecr_read_only,
  ]
}

# ---------------------------------------------------------------------------
# EBS CSI Driver IRSA role — required for PersistentVolumes (Prometheus,
# Grafana). The other IRSA roles in docs/technical-spec.md#irsa-roles (ESO,
# LB controller, ArgoCD, Karpenter) belong to their own epics/modules.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "ebs_csi_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.cluster.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  name               = "${local.name_prefix}-ebs-csi-role"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume_role.json

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# ---------------------------------------------------------------------------
# EKS managed add-ons (PETPLAT-84) — pinned versions, OVERWRITE for initial
# setup. To upgrade: set the desired version in var.addon_versions (e.g.
# { "aws-ebs-csi-driver" = "v1.999.9-eksbuild.1" }) and re-apply; omit the key
# to track the current EKS-recommended default again.
# ---------------------------------------------------------------------------

data "aws_eks_addon_version" "this" {
  for_each = toset(local.addon_names)

  addon_name         = each.value
  kubernetes_version = aws_eks_cluster.main.version
  most_recent        = false
}

resource "aws_eks_addon" "this" {
  for_each = toset(local.addon_names)

  cluster_name  = aws_eks_cluster.main.name
  addon_name    = each.value
  addon_version = coalesce(lookup(var.addon_versions, each.value, null), data.aws_eks_addon_version.this[each.value].version)

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  service_account_role_arn = each.value == "aws-ebs-csi-driver" ? aws_iam_role.ebs_csi.arn : null

  tags = local.tags

  depends_on = [aws_eks_node_group.main]
}
