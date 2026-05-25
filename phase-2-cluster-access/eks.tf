# Create a VPC for the EKS Cluster
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.cluster_name}-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["${var.aws_region}a", "${var.aws_region}b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
}

# Provision the EKS Cluster using the official AWS module
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.20" # 2026 current stable module version

  cluster_name    = var.cluster_name
  cluster_version = "1.31" # Use a modern Kubernetes version

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.public_subnets

  cluster_endpoint_public_access = true

  # Modern Access Management (replaces aws-auth)
  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = true # We keep this true initially so YOU can access it, but in strict production it is false.

  eks_managed_node_groups = {
    default = {
      instance_types = ["t3.medium"]
      min_size       = 1
      max_size       = 2
      desired_size   = 1
    }
  }
}

# Ensure access entries are only created AFTER the cluster exists
resource "terraform_data" "wait_for_cluster" {
  depends_on = [module.eks]
}
