data "aws_caller_identity" "current" {}

# IAM Role for Developers
resource "aws_iam_role" "developer" {
  name = "eks-developer-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
      }
    }]
  })
}

# IAM Role for QA
resource "aws_iam_role" "qa" {
  name = "eks-qa-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
      }
    }]
  })
}
