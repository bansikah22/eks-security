terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

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

variable "log_retention_days" {
  description = "CloudWatch log retention in days for the EKS control plane log group"
  type        = number
  default     = 90
}

# ── CloudWatch log group ───────────────────────────────────────────────────────
# Pre-creating the log group sets a retention policy so logs do not accumulate
# indefinitely. EKS will auto-create this group if absent, but without retention.
resource "aws_cloudwatch_log_group" "eks_control_plane" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = var.log_retention_days

  tags = {
    Name    = "${var.cluster_name}-control-plane-logs"
    Phase   = "6"
    Purpose = "audit-and-authenticator-logs"
  }
}

# ── Enable all five EKS control plane log types ───────────────────────────────
# The transcript highlights audit (who did what when) and authenticator (IAM/RBAC)
# as the most useful for runtime security. All five are enabled here.
resource "null_resource" "eks_logging" {
  triggers = {
    cluster_name = var.cluster_name
    log_types    = "api,audit,authenticator,controllerManager,scheduler"
  }

  provisioner "local-exec" {
    command = <<-CMD
      aws eks update-cluster-config \
        --region ${var.aws_region} \
        --name ${var.cluster_name} \
        --logging '{"clusterLogging":[{"types":["api","audit","authenticator","controllerManager","scheduler"],"enabled":true}]}' \
        --no-cli-pager
    CMD
  }

  depends_on = [aws_cloudwatch_log_group.eks_control_plane]
}

output "control_plane_log_group" {
  description = "CloudWatch log group receiving EKS control plane logs"
  value       = aws_cloudwatch_log_group.eks_control_plane.name
}
