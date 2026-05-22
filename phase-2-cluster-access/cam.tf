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

# Example Variables
variable "cluster_name" {
  description = "The name of the EKS cluster"
  type        = string
  default     = "my-secure-cluster"
}

variable "aws_region" {
  description = "The AWS region to use"
  type        = string
  default     = "eu-central-1"
}



# Access Entry for Developers
resource "aws_eks_access_entry" "developer" {
  cluster_name      = module.eks.cluster_name
  principal_arn     = aws_iam_role.developer.arn
  kubernetes_groups = []
  type              = "STANDARD"

  depends_on = [terraform_data.wait_for_cluster]
}

# Access Policy Association for Developers (Edit access in development namespace)
resource "aws_eks_access_policy_association" "developer_policy" {
  cluster_name  = module.eks.cluster_name
  principal_arn = aws_eks_access_entry.developer.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"

  access_scope {
    type       = "namespace"
    namespaces = ["development"]
  }
}

# Access Entry for QA
resource "aws_eks_access_entry" "qa" {
  cluster_name      = module.eks.cluster_name
  principal_arn     = aws_iam_role.qa.arn
  kubernetes_groups = []
  type              = "STANDARD"

  depends_on = [terraform_data.wait_for_cluster]
}

# Access Policy Association for QA (View access in development namespace)
resource "aws_eks_access_policy_association" "qa_policy" {
  cluster_name  = module.eks.cluster_name
  principal_arn = aws_eks_access_entry.qa.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"

  access_scope {
    type       = "namespace"
    namespaces = ["development"]
  }
}
