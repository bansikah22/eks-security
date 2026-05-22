# Phase 2: Cluster Access Management (CAM)

## Overview
Amazon EKS traditionally relied on the `aws-auth` ConfigMap to map IAM users and roles to Kubernetes RBAC groups. AWS has introduced **Cluster Access Management (CAM) Access Entries** as the modern, recommended way to handle authentication and authorization.

This phase implements CAM by creating standard access entries for different teams and attaching AWS-managed EKS Access Policies (like `AmazonEKSEditPolicy` and `AmazonEKSViewPolicy`) scoped specifically to individual namespaces.

---

## Step 1: Remove Cluster Creator Admin
By default, the IAM entity that creates the EKS cluster automatically receives `system:masters` permissions. This creates a single point of failure and violates the principle of least privilege.

When provisioning your cluster with Terraform, ensure you update the authentication mode and disable the creator admin:
```hcl
resource "aws_eks_cluster" "example" {
  name     = "my-secure-cluster"
  # ... other config

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = false
  }
}
```
*(If the cluster already exists, you can safely remove the initial creator access entry manually or via IaC, provided another administrator role has been securely established.)*

---

## Step 2: Provision Infrastructure and Access Entries (Terraform)
Instead of manually editing the messy `aws-auth` ConfigMap, we use the `aws_eks_access_entry` and `aws_eks_access_policy_association` resources. Because the Access Entries depend on the cluster existing, we first provision the cluster using the official EKS module.

### Implementation
1. **`eks.tf`**: Provisions the underlying VPC and Amazon EKS Cluster.
2. **`cam.tf`**: Sets up the Access Entries:
   - A **Developer** entry with the `AmazonEKSEditPolicy` restricted to the `development` namespace.
   - A **QA/Tester** entry with the `AmazonEKSViewPolicy` restricted to the `development` namespace.

**Apply the Terraform:**
```bash
terraform apply \
  -var="aws_region=eu-central-1" \
  -var="cluster_name=my-secure-cluster"
```

---

## Step 3: Testing the Access Boundaries

To verify the role-based access control works as intended, follow these steps:

**1. Create the `development` namespace as Admin**
First, log in as your regular Admin user to create the namespace (since Developers don't have cluster-wide permission to create namespaces).
```bash
aws eks update-kubeconfig --region eu-central-1 --name my-secure-cluster
kubectl create namespace development
```

**2. Switch to the Developer Role**
AWS CLI allows you to pass `--role-arn` to `update-kubeconfig`. This modifies your kubeconfig so that every time you run a `kubectl` command, it will automatically assume the Developer role.
*(Replace `<AWS_ACCOUNT_ID>` with your 12-digit AWS Account ID)*
```bash
aws eks update-kubeconfig --region eu-central-1 --name my-secure-cluster --role-arn arn:aws:iam::<AWS_ACCOUNT_ID>:role/eks-developer-role
```

**3. Test the RBAC Isolation**
Now that you are acting as the Developer, test the access boundaries.

This command should **SUCCEED** (it might say "No resources found", which means you authenticated and were authorized successfully!):
```bash
kubectl get pods -n development
```

This command should **FAIL** (giving a `Forbidden` error, proving that the Developer cannot access the system namespace):
```bash
kubectl get pods -n kube-system
```

---

## Clean Up
When you're finished testing the access entries and the EKS cluster, securely destroy all resources so you don't incur unnecessary AWS charges (an idle EKS cluster costs ~$73/month).

```bash
terraform destroy \
  -var="aws_region=eu-central-1" \
  -var="cluster_name=my-secure-cluster"
```
