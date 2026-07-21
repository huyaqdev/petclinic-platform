locals {
  name_prefix       = "${var.project}-${var.environment}"
  oidc_provider_url = replace(var.oidc_provider_url, "https://", "")

  tags = merge(var.tags, {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  })
}

# ---------------------------------------------------------------------------
# IAM policy — the official AWS Load Balancer Controller policy (PETPLAT-29),
# vendored from
# https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json
# Re-check upstream for changes when bumping the Helm chart's app version.
# ---------------------------------------------------------------------------

resource "aws_iam_policy" "this" {
  name        = "${local.name_prefix}-lb-controller-policy"
  description = "Permissions required by the AWS Load Balancer Controller to manage ALBs/NLBs on behalf of Ingress/Service resources"
  policy      = file("${path.module}/iam-policy.json")

  tags = local.tags
}

# ---------------------------------------------------------------------------
# IRSA role — trusts the EKS OIDC provider, scoped to the
# aws-load-balancer-controller service account in kube-system (see
# docs/technical-spec.md#irsa-roles).
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "${local.name_prefix}-lb-controller-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "this" {
  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.this.arn
}
