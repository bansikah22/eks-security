terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "cluster_name" {
  description = "The name of the existing EKS cluster"
  type        = string
  default     = "my-secure-cluster"
}

variable "aws_region" {
  description = "AWS region hosting the EKS cluster"
  type        = string
  default     = "eu-central-1"
}

variable "namespace" {
  description = "Kubernetes namespace that hosts the workload"
  type        = string
  default     = "development"
}

variable "service_account_name" {
  description = "ServiceAccount name used by the pod"
  type        = string
  default     = "s3-reader"
}

variable "test_bucket_name" {
  description = "Existing S3 bucket that the workload is allowed to read"
  type        = string
  default     = "eks-security-phase4-demo"
  default     = "eks-security-phase4-demo"
}

locals {
  pod_identity_role_name = "${var.cluster_name}-pod-identity-s3-reader"
}

data "aws_caller_identity" "current" {}

resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name                = var.cluster_name
  addon_name                  = "eks-pod-identity-agent"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

resource "aws_iam_role" "pod_identity_s3_reader" {
  name = local.pod_identity_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "pods.eks.amazonaws.com"
      }
      Action = [
        "sts:AssumeRole",
        "sts:TagSession"
      ]
    }]
  })
}

resource "aws_iam_policy" "s3_read_only" {
  name = "${local.pod_identity_role_name}-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ListBucket"
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.test_bucket_name}"
        ]
      },
      {
        Sid    = "ReadObjects"
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = [
          "arn:aws:s3:::${var.test_bucket_name}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "s3_read_only" {
  role       = aws_iam_role.pod_identity_s3_reader.name
  policy_arn = aws_iam_policy.s3_read_only.arn
}

resource "aws_eks_pod_identity_association" "s3_reader" {
  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = var.service_account_name
  role_arn        = aws_iam_role.pod_identity_s3_reader.arn

  depends_on = [aws_eks_addon.pod_identity_agent]
}

output "pod_identity_role_arn" {
  description = "IAM role assumed by pods using the ServiceAccount"
  value       = aws_iam_role.pod_identity_s3_reader.arn
}

output "test_commands" {
  description = "Commands to verify the Pod Identity permissions from inside the pod"
  value = [
    "aws sts get-caller-identity",
    "aws s3 ls s3://${var.test_bucket_name}",
    "aws ec2 describe-instances --region ${var.aws_region}"
  ]
}