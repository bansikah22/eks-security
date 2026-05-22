provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

variable "aws_region" {
  description = "AWS region where the cluster runs"
  type        = string
  default     = "eu-central-1"
}

variable "cluster_name" {
  description = "Name of the existing EKS cluster"
  type        = string
  default     = "my-secure-cluster"
}

# ── Envelope-encryption key for Kubernetes Secrets ────────────────────────────
# The ARN from the output below is passed to:
#   aws eks associate-encryption-config --cluster-name <name> \
#     --encryption-config '[{"resources":["secrets"],"provider":{"keyArn":"<ARN>"}}]'
resource "aws_kms_key" "eks_secrets" {
  description             = "CMK for Kubernetes Secrets envelope encryption – ${var.cluster_name}"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name    = "${var.cluster_name}-secrets-encryption"
    Phase   = "5"
    Purpose = "envelope-encryption"
  }
}

resource "aws_kms_alias" "eks_secrets" {
  name          = "alias/${var.cluster_name}-secrets-encryption"
  target_key_id = aws_kms_key.eks_secrets.key_id
}

# ── EBS volume encryption key (used by the encrypted StorageClass) ─────────────
resource "aws_kms_key" "ebs" {
  description             = "CMK for EBS volume encryption via EBS CSI driver – ${var.cluster_name}"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name    = "${var.cluster_name}-ebs-encryption"
    Phase   = "5"
    Purpose = "ebs-encryption"
  }
}

resource "aws_kms_alias" "ebs" {
  name          = "alias/${var.cluster_name}-ebs-encryption"
  target_key_id = aws_kms_key.ebs.key_id
}

# ── Outputs ────────────────────────────────────────────────────────────────────
output "secrets_kms_key_arn" {
  description = "Pass this ARN to enable envelope encryption on the running cluster"
  value       = aws_kms_key.eks_secrets.arn
}

output "ebs_kms_key_arn" {
  description = "Use this ARN in the encrypted StorageClass kmsKeyId parameter"
  value       = aws_kms_key.ebs.arn
}
