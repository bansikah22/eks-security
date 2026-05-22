terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "eu-central-1" # Can be updated later
}

# Create a KMS Key for ECR
resource "aws_kms_key" "ecr_key" {
  description             = "KMS key for ECR encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 7
}

resource "aws_kms_alias" "ecr_key_alias" {
  name          = "alias/secure-app-ecr-key"
  target_key_id = aws_kms_key.ecr_key.key_id
}

# Provision the ECR Repository
resource "aws_ecr_repository" "secure_app_repo" {
  name                 = "secure-app"
  image_tag_mutability = "IMMUTABLE" # Prevents overwriting of existing tags

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = aws_kms_key.ecr_key.arn
  }

  force_delete = true
}

# Apply a lifecycle policy to remove untagged or old images
resource "aws_ecr_lifecycle_policy" "secure_app_lifecycle" {
  repository = aws_ecr_repository.secure_app_repo.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Expire untagged images older than 14 days"
      selection = {
        tagStatus   = "untagged"
        countType   = "sinceImagePushed"
        countUnit   = "days"
        countNumber = 14
      }
      action = {
        type = "expire"
      }
    }]
  })
}
