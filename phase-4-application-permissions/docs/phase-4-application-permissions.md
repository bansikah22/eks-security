# Phase 4: Application Permissions with EKS Pod Identity and IRSA

> This walkthrough uses the live demo values from this repo and cluster setup:
> `cluster_name=my-secure-cluster`, `region=eu-central-1`, `nodegroup_name=default-20260522144033202200000013`, `node_role_name=default-eks-node-group-20260522141505413500000001`, `aws_account_id=<ACCOUNT_ID>`, and `s3_bucket=eks-security-phase4-demo-<ACCOUNT_ID>`.
> If you are reusing this guide in another environment, search and replace these values with your own.

## Overview
Pods should never inherit broad AWS permissions from the worker node IAM role. In a secure Amazon EKS environment, application permissions must be scoped directly to the workload identity so each pod receives only the AWS actions it actually needs.

Following the course transcript and the roadmap in `Todo.md`, this phase implements both approaches covered in the lesson:
1. **EKS Pod Identity** as the preferred modern option.
2. **IAM Roles for Service Accounts (IRSA)** as the older but still common pattern.

In both flows, the workload gets read-only access to one S3 bucket while unrelated AWS APIs such as EC2 remain blocked.

---

## Step 1: Remove Application Permissions from the Node Role
Before introducing Pod Identity, make sure the node group IAM role only contains the permissions needed for cluster operation. The node role should keep policies such as `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`, and `AmazonEC2ContainerRegistryPullOnly`, but it should NOT carry application-specific policies like S3, DynamoDB, or Secrets Manager access.

**Check the node role currently attached to your managed node group:**
```bash
aws eks describe-nodegroup \
  --cluster-name my-secure-cluster \
  --nodegroup-name default-20260522144033202200000013 \
  --region eu-central-1 \
  --query 'nodegroup.nodeRole' \
  --output text
```

**List the policies attached to that role:**
```bash
aws iam list-attached-role-policies \
  --role-name default-eks-node-group-20260522141505413500000001
```

If you find application permissions on the node role, move them to dedicated workload roles first, then detach them from the node role.

---

## Step 2: Provision EKS Pod Identity for the Running Cluster
Because your cluster is already running, this phase does not recreate the cluster. Instead, the Terraform in `pod-identity.tf` installs the `eks-pod-identity-agent` add-on, creates a dedicated IAM role for the workload, attaches a strict S3 read policy, and associates that role to the Kubernetes `ServiceAccount` named `s3-reader` in the `development` namespace.

### Files in This Phase
1. `pod-identity.tf`: Creates the add-on, IAM role, IAM policy, and Pod Identity association.
2. `service-account.yaml`: Defines the `s3-reader` Kubernetes `ServiceAccount`.
3. `test-pod.yaml`: Deploys an AWS CLI pod that uses the `s3-reader` ServiceAccount.
4. `s3-read-policy.json`: Reusable least-privilege S3 read policy for the IRSA flow.
5. `irsa-test-pod.yaml`: Deploys an AWS CLI pod that uses the IRSA-backed ServiceAccount.

### Apply the Terraform
Use an existing S3 bucket name that contains at least one object so the read-only test is obvious.

```bash
terraform init
terraform apply \
  -var="aws_region=eu-central-1" \
  -var="cluster_name=my-secure-cluster" \
  -var="test_bucket_name=eks-security-phase4-demo-<ACCOUNT_ID>"
```

### Verify the Pod Identity agent is present
This matches the transcript flow where the add-on results in a new daemon set on the cluster.

```bash
kubectl get daemonset -n kube-system
```

---

## Step 3: Deploy the Kubernetes Service Account and Test Pod
Once the AWS-side Pod Identity association exists, deploy the Kubernetes objects into the same namespace that was used in earlier phases.

```bash
kubectl apply -f service-account.yaml
kubectl apply -f test-pod.yaml
kubectl rollout status deployment/s3-reader -n development
```

---

## Step 4: Verify Least-Privilege AWS Access
Exec into the pod and verify the permissions.

**1. Confirm the pod received AWS credentials via Pod Identity:**
```bash
kubectl exec -n development deploy/s3-reader -- aws sts get-caller-identity
```

**2. Verify the pod can read only the approved S3 bucket:**
```bash
kubectl exec -n development deploy/s3-reader -- aws s3 ls s3://eks-security-phase4-demo-<ACCOUNT_ID>
```

**3. Verify unrelated AWS APIs are denied:**
```bash
kubectl exec -n development deploy/s3-reader -- aws ec2 describe-instances --region eu-central-1
```

The EC2 call should fail with an `AccessDenied` style error. That failure is the proof that your pod is no longer relying on broad node credentials and is constrained to only the S3 actions you granted.

---

## Step 5: Implement IRSA the Same Way as the Course Demo
The transcript also walks through **IAM Roles for Service Accounts (IRSA)** as the second method. IRSA relies on the cluster OIDC provider and a trust policy bound to a specific Kubernetes service account.

### 1. Associate the cluster OIDC provider
Check the issuer first:

```bash
aws eks describe-cluster \
  --name my-secure-cluster \
  --region eu-central-1 \
  --query "cluster.identity.oidc.issuer" \
  --output text
```

Associate it with the cluster using `eksctl`:

```bash
eksctl utils associate-iam-oidc-provider \
  --cluster my-secure-cluster \
  --region eu-central-1 \
  --approve
```

### 2. Create the S3 read policy
The transcript assumes a policy already exists. In this repo, create it explicitly from `s3-read-policy.json`.

```bash
aws iam create-policy \
  --policy-name eks-irsa-s3-read \
  --policy-document file://s3-read-policy.json
```

### 3. Create the IRSA-backed ServiceAccount with `eksctl`
This follows the transcript closely: `eksctl` creates the IAM role, wires in the trust relationship, and creates the Kubernetes service account.

```bash
eksctl create iamserviceaccount \
  --cluster my-secure-cluster \
  --region eu-central-1 \
  --namespace development \
  --name s3-reader-irsa \
  --attach-policy-arn arn:aws:iam::<ACCOUNT_ID>:policy/eks-irsa-s3-read \
  --approve
```

### 4. Deploy the IRSA test pod

```bash
kubectl apply -f irsa-test-pod.yaml
kubectl rollout status deployment/s3-reader-irsa -n development
```

### 5. Verify the IRSA permissions

```bash
kubectl exec -n development deploy/s3-reader-irsa -- aws s3 ls s3://eks-security-phase4-demo-<ACCOUNT_ID>
kubectl exec -n development deploy/s3-reader-irsa -- aws ec2 describe-instances --region eu-central-1
```

The S3 command should succeed and the EC2 command should fail with `AccessDenied`, just like in the transcript demo.

---

## Pod Identity vs IRSA
EKS Pod Identity is generally simpler for new EKS workloads because:
1. You do not have to manage OIDC trust conditions manually for each role.
2. The managed add-on centralizes the credential delivery mechanism.
3. The IAM trust policy is simpler and purpose-built for EKS workloads.

IRSA remains useful when:
1. Your tooling already standardizes on `eksctl` and OIDC-based roles.
2. You are maintaining older clusters or existing workloads that already depend on IRSA.
3. A third-party chart or integration documents IRSA specifically.

---

## Clean Up
Delete the Kubernetes resources first, then remove the AWS-side associations and IAM roles.

```bash
kubectl delete -f test-pod.yaml
kubectl delete -f service-account.yaml
kubectl delete -f irsa-test-pod.yaml

terraform destroy \
  -var="aws_region=eu-central-1" \
  -var="cluster_name=my-secure-cluster" \
  -var="test_bucket_name=eks-security-phase4-demo-<ACCOUNT_ID>"

eksctl delete iamserviceaccount \
  --cluster my-secure-cluster \
  --region eu-central-1 \
  --namespace development \
  --name s3-reader-irsa
```