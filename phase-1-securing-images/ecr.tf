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

# Provision the ECR Repository
resource "aws_ecr_repository" "secure_app_repo" {
  name                 = "secure-app"
  image_tag_mutability = "IMMUTABLE" # Prevents overwriting of existing tags

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
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
