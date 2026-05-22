# Phase 1: Securing Container Images

## Overview
This document outlines the best practices for securing container images before they are deployed to an Amazon EKS cluster. The focus is on minimizing the attack surface, enforcing static code analysis on Dockerfiles, checking for known vulnerabilities locally and in continuous integration, and relying on AWS-native scanning via Amazon Inspector in Amazon ECR. 

These steps follow current DevOps and security best practices for 2026, ensuring immutability, least privilege, and early vulnerability detection (shift-left security).

---

## Step 1: Base Image Selection and Least Privilege

Using minimal base images reduces the attack surface by excluding unnecessary operating system packages, shells, and package managers. For compiled languages like Go, utilizing a "distroless" base or a scratch image is highly recommended.

Furthermore, applications must never run as the root user. A dedicated, non-privileged user must be specified.

### Implementation: Optimized Dockerfile for Go

Create a standard `Dockerfile` that uses a multi-stage build. The first stage builds the application, and the second stage contains only the compiled binary running as a non-root user.

```dockerfile
# Build stage
FROM golang:1.22-alpine AS builder

# Set the working directory
WORKDIR /app

# Copy dependency manifests and install them
COPY go.mod go.sum ./
RUN go mod download

# Copy application source code
COPY . .

# Build a statically linked binary
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags="-w -s" -o server .

# Final stage - using distroless for minimal attack surface
FROM gcr.io/distroless/static-debian12:nonroot

# The distroless image provides a nonroot user by default
USER nonroot:nonroot

# Copy the binary from the builder stage
COPY --from=builder --chown=nonroot:nonroot /app/server /server

# Expose the application port
EXPOSE 8080

# Define the entrypoint
ENTRYPOINT ["/server"]
```

---

## Step 2: Enforcing Best Practices with Hadolint

Hadolint is a static analysis tool for Dockerfiles that enforces rules based on Docker best practices. It prevents common mistakes, such as forgetting to pin versions or using `sudo` inside a container.

### Implementation: Running Hadolint

You can run Hadolint locally during development and integrate it into your CI pipeline.

**Local Execution (via Docker):**
```bash
docker run --rm -i hadolint/hadolint < Dockerfile
```

**CI/CD Pipeline Integration (Example using GitHub Actions):**
```yaml
name: Lint Dockerfile
on: [push, pull_request]

jobs:
  hadolint:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4
      
      - name: Run Hadolint
        uses: hadolint/hadolint-action@v3.1.0
        with:
          dockerfile: Dockerfile
          failure-threshold: warning
```

---

## Step 3: Local and CI/CD Image Scanning with Trivy

Before pushing an image to a registry, it should be scanned for Known Vulnerabilities and Exposures (CVEs). Trivy is the industry standard open-source scanner for this purpose.

### Implementation: Scanning Images

**1. Build the image locally:**
```bash
docker build -t my-secure-app:latest .
```

**2. Scan the image locally with Trivy:**
```bash
trivy image --severity HIGH,CRITICAL --exit-code 1 my-secure-app:latest
```
*Note: The `--exit-code 1` flag ensures that the command fails if high or critical vulnerabilities are found. This is crucial for breaking the CI build.*

---

## Step 4: Securing the Image Registry (Amazon ECR)

Once the image passes local and CI validation, it is pushed to Amazon Elastic Container Registry (ECR). Amazon Inspector integrates directly with ECR to provide continuous vulnerability scanning.

### Implementation: Infrastructure as Code (Terraform)

Use Terraform to provision an ECR repository with scan-on-push enabled. In modern AWS environments, Amazon Inspector should be enabled at the organization or account level to continuously scan ECR repositories.

Create a file named `ecr.tf`:

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "eu-central-1" # Update to your target region
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
```

### Applying the Infrastructure:
```bash
terraform init
terraform plan -out=tfplan
terraform apply "tfplan"
```

---

## Step 5: Pushing the Image to Amazon ECR

Once the ECR repository is created, you must authenticate your local Docker client and push your securely built image to AWS.

**1. Retrieve an authentication token and authenticate your Docker client:**
*(Replace `<AWS_ACCOUNT_ID>` with your actual 12-digit AWS account ID)*
```bash
aws ecr get-login-password --region eu-central-1 | docker login --username AWS --password-stdin <AWS_ACCOUNT_ID>.dkr.ecr.eu-central-1.amazonaws.com
```

**2. Tag your local image with the ECR repository URI:**
```bash
docker tag my-secure-app:latest <AWS_ACCOUNT_ID>.dkr.ecr.eu-central-1.amazonaws.com/secure-app:latest
```

**3. Push the image to ECR:**
```bash
docker push <AWS_ACCOUNT_ID>.dkr.ecr.eu-central-1.amazonaws.com/secure-app:latest
```

Once pushed, you can navigate to the ECR console in `eu-central-1`. Because we enabled `scan_on_push`, Amazon Inspector will automatically perform a vulnerability scan on the newly pushed image, acting as the final line of defense before the image runs on EKS.

## Summary
By completing this phase, you have:
1. Implemented a minimal, least-privilege Dockerfile.
2. Enforced static code analysis using Hadolint.
3. Integrated Trivy for local and CI/CD vulnerability scanning.
4. Provisioned a secure, immutable, and continuously scanned ECR repository using Terraform.
5. Pushed your verified image to your secure ECR registry.

---

## Clean Up

To avoid incurring unnecessary AWS costs, you should always clean up resources when you are done testing. Because we set `force_delete = true` on the ECR repository in Terraform, we can destroy it even if it contains images.

**1. Destroy Terraform infrastructure:**
```bash
terraform destroy
```

**2. Remove local Docker images:**
```bash
docker rmi my-secure-app:latest
docker rmi <AWS_ACCOUNT_ID>.dkr.ecr.eu-central-1.amazonaws.com/secure-app:latest
```
