# ── Fetch cluster OIDC provider (needed for IRSA trust policy) ─────────────────
data "aws_eks_cluster" "this" {
  name = var.cluster_name
}

data "aws_iam_openid_connect_provider" "this" {
  url = data.aws_eks_cluster.this.identity[0].oidc[0].issuer
}

locals {
  oidc_provider_arn = data.aws_iam_openid_connect_provider.this.arn
  oidc_provider_id  = replace(data.aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")
}

# ── IAM role for the EBS CSI driver (IRSA) ────────────────────────────────────
resource "aws_iam_role" "ebs_csi" {
  name = "${var.cluster_name}-ebs-csi-driver"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = local.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_provider_id}:aud" = "sts.amazonaws.com"
          "${local.oidc_provider_id}:sub" = "system:serviceaccount:kube-system:ebs-csi-controller-sa"
        }
      }
    }]
  })

  tags = {
    Name  = "${var.cluster_name}-ebs-csi-driver"
    Phase = "5"
  }
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# Grant the EBS CSI driver permission to use the EBS KMS key to encrypt volumes
resource "aws_kms_grant" "ebs_csi" {
  name              = "${var.cluster_name}-ebs-csi-kms-grant"
  key_id            = aws_kms_key.ebs.key_id
  grantee_principal = aws_iam_role.ebs_csi.arn
  operations = [
    "Encrypt",
    "Decrypt",
    "ReEncryptFrom",
    "ReEncryptTo",
    "GenerateDataKey",
    "GenerateDataKeyWithoutPlaintext",
    "DescribeKey",
    "CreateGrant",
  ]
}

# ── EBS CSI driver managed add-on ─────────────────────────────────────────────
resource "aws_eks_addon" "ebs_csi" {
  cluster_name             = var.cluster_name
  addon_name               = "aws-ebs-csi-driver"
  service_account_role_arn = aws_iam_role.ebs_csi.arn

  depends_on = [
    aws_iam_role_policy_attachment.ebs_csi,
    aws_kms_grant.ebs_csi,
  ]

  tags = {
    Phase = "5"
  }
}

output "ebs_csi_role_arn" {
  description = "IAM role ARN used by the EBS CSI driver service account"
  value       = aws_iam_role.ebs_csi.arn
}
