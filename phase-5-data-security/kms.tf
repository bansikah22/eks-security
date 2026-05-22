terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

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

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableIAMUserPermissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowEKSEnvelopeEncryption"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:CreateGrant",
        ]
        Resource = "*"
      }
    ]
  })

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

  # The EBS CSI driver is granted access via aws_kms_grant in ebs-csi.tf.
  # The root statement below enables IAM-based management of this key.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableIAMUserPermissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      }
    ]
  })

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

# ── Generate storageclass-generated.yaml with the real EBS KMS key ARN ─────────
# After terraform apply, run: kubectl apply -f storageclass-generated.yaml
resource "local_file" "storageclass" {
  content = <<-YAML
    apiVersion: storage.k8s.io/v1
    kind: StorageClass
    metadata:
      name: encrypted-gp3
      annotations:
        storageclass.kubernetes.io/is-default-class: "false"
    provisioner: ebs.csi.aws.com
    parameters:
      type: gp3
      encrypted: "true"
      kmsKeyId: ${aws_kms_key.ebs.arn}
    reclaimPolicy: Delete
    allowVolumeExpansion: true
    volumeBindingMode: WaitForFirstConsumer
  YAML
  filename        = "${path.module}/storageclass-generated.yaml"
  file_permission = "0644"
}
