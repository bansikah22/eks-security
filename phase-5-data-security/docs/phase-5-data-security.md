# Phase 5: Data Security & Secrets Management

> This walkthrough uses the live demo values from this repo and cluster setup:
> `cluster_name=my-secure-cluster`, `region=eu-central-1`.
> No account IDs are hardcoded — all IAM ARNs are derived at runtime via Terraform data sources.
> If you are reusing this guide in another environment, update the variable defaults in `kms.tf`.

## Overview
Data must be protected both at rest and in transit. On Amazon EKS this means three concrete things:

1. **Volume Encryption** — EBS and EFS volumes use AWS KMS so data on disk is always encrypted.
2. **Envelope Encryption for `etcd`** — Kubernetes Secrets are only base64-encoded by default. Enabling envelope encryption wraps every secret with a unique data key that is itself encrypted by a customer-managed KMS key (CMK).
3. **Secure Secret Consumption** — Secrets must be mounted as volumes inside pods, never injected as environment variables which can leak into logs.

Following the course transcript and `Todo.md`, this phase provisions two KMS keys, installs the EBS CSI driver with a dedicated IRSA role, applies envelope encryption to the running cluster, and demonstrates safe secret consumption.

---

## Step 1: Understand the Default State

On EKS, the EBS volumes backing `etcd` are already encrypted using the default AWS-managed EBS key. This happens transparently — you do not configure it.

However, Kubernetes Secrets inside `etcd` are stored as **base64-encoded strings**, which is encoding not encryption. Anyone with direct access to `etcd` can read them. Envelope encryption fixes this by adding a second layer: every secret is encrypted with a unique data key, and that data key is encrypted by your CMK.

Verify the current cluster encryption config (should be empty before this phase):

```bash
aws eks describe-cluster \
  --name my-secure-cluster \
  --region eu-central-1 \
  --query 'cluster.encryptionConfig' \
  --output json \
  --no-cli-pager
```

---

## Step 2: Provision KMS Keys

`kms.tf` creates two customer-managed keys (CMKs), both with **annual automatic key rotation** enabled as required by the course:

| Key | Alias | Purpose |
|-----|-------|---------|
| `aws_kms_key.eks_secrets` | `alias/my-secure-cluster-secrets-encryption` | Envelope encryption for Kubernetes Secrets |
| `aws_kms_key.ebs` | `alias/my-secure-cluster-ebs-encryption` | EBS volume encryption via EBS CSI driver |

```bash
cd phase-5-data-security
terraform init
terraform apply \
  -var="aws_region=eu-central-1" \
  -var="cluster_name=my-secure-cluster"
```

Note the two ARN outputs:

```bash
terraform output secrets_kms_key_arn
terraform output ebs_kms_key_arn
```

---

## Step 3: Enable Envelope Encryption on the Running Cluster

Use the `secrets_kms_key_arn` output from Step 2. The `associate-encryption-config` command can be applied to an existing cluster:

```bash
SECRETS_KEY_ARN=$(terraform output -raw secrets_kms_key_arn)

aws eks associate-encryption-config \
  --cluster-name my-secure-cluster \
  --region eu-central-1 \
  --encryption-config "[{\"resources\":[\"secrets\"],\"provider\":{\"keyArn\":\"${SECRETS_KEY_ARN}\"}}]" \
  --no-cli-pager
```

Wait for the update to complete (this re-encrypts all existing secrets in etcd):

```bash
aws eks describe-cluster \
  --name my-secure-cluster \
  --region eu-central-1 \
  --query 'cluster.encryptionConfig' \
  --output json \
  --no-cli-pager
```

You should see the key ARN appear in the output with `"resources": ["secrets"]`.

---

## Step 4: Install the EBS CSI Driver with Encrypted StorageClass

`ebs-csi.tf` does four things:
1. Creates an IAM role for the EBS CSI driver using IRSA (bound to the `ebs-csi-controller-sa` service account in `kube-system`).
2. Attaches the AWS-managed `AmazonEBSCSIDriverPolicy`.
3. Creates a KMS grant so the driver can use the EBS CMK to encrypt volumes.
4. Installs the `aws-ebs-csi-driver` managed add-on with the IRSA role.

Apply it together with Step 2 or separately:

```bash
terraform apply \
  -var="aws_region=eu-central-1" \
  -var="cluster_name=my-secure-cluster"
```

### Apply the encrypted StorageClass

After `terraform apply`, Terraform generates `storageclass-generated.yaml` with the real KMS key ARN already substituted (via the `local_file` resource in `kms.tf`). Apply it directly:

```bash
kubectl apply -f storageclass-generated.yaml
```

Verify the StorageClass was created:

```bash
kubectl get storageclass encrypted-gp3
```

### Verify the EBS CSI add-on is running

```bash
kubectl get daemonset ebs-csi-node -n kube-system
kubectl get deployment ebs-csi-controller -n kube-system
```

---

## Step 5: Secure Secret Consumption

The transcript says:
> "Using volume mounts is a better practice because when a secret is mounted in a volume, it's done through a temporary file system, which is then automatically removed whenever the pod is deleted from the node."
> "Using secrets as environment variables is not actually seen as a good practice because they can be exposed in logs."

### What to avoid — env var exposure

```yaml
# BAD: secret value appears in env, can leak into crash logs, kubectl describe, etc.
env:
  - name: DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: app-credentials
        key: db-password
```

### What to do — volume mount (tmpfs)

`secret-pod.yaml` mounts the secret as a read-only volume. The kubelet delivers secret data to the pod through a `tmpfs` in-memory filesystem.

First create the secret securely via `kubectl` (not from a YAML file with hardcoded values):

```bash
kubectl create secret generic app-credentials \
  --namespace secrets-demo \
  --from-literal=db-password='my-db-password' \
  --from-literal=api-key='my-api-key'
```

Then apply the namespace and pod:

```bash
kubectl apply -f namespace.yaml
kubectl apply -f secret-pod.yaml
```

---

## Step 6: Verify Secure Secret Consumption

**Confirm the pod is running:**

```bash
kubectl get pod secret-consumer -n secrets-demo
```

**Read the mounted secret values from inside the pod:**

```bash
kubectl exec -n secrets-demo secret-consumer -- cat /etc/secrets/db-password
kubectl exec -n secrets-demo secret-consumer -- cat /etc/secrets/api-key
```

Both files should return the values from `secret.yaml`. They are delivered over `tmpfs` — they never touch persistent disk on the node.

**Confirm the secret is NOT exposed as an environment variable:**

```bash
kubectl exec -n secrets-demo secret-consumer -- env | grep -i password
kubectl exec -n secrets-demo secret-consumer -- env | grep -i api
```

Both commands should return no output, confirming that secret values are not accessible from environment variables.

**Verify namespace isolation — confirm the secret is not accessible from outside its namespace:**

```bash
# This should fail: secrets are namespaced objects
kubectl get secret app-credentials -n development
```

---

## Key Takeaways from the Transcript

| Topic | Default | Secure Approach |
|-------|---------|-----------------|
| EBS volumes (worker nodes & etcd) | Encrypted by default with AWS-managed key | Use a CMK with `enable_key_rotation = true` |
| Kubernetes Secrets in etcd | Base64-encoded only — **not encrypted** | Enable envelope encryption with a KMS CMK |
| Secret delivery to pods | `env` or `volume` | Always use **volume mounts** (tmpfs) |
| KMS key rotation | Manual | Configure `enable_key_rotation = true` — rotates annually, old keys retained |
| Secret namespace isolation | Secrets are namespaced | Run apps that need secrets in **dedicated namespaces** |

---

## Clean Up

```bash
# Delete Kubernetes resources
kubectl delete -f secret-pod.yaml
kubectl delete secret app-credentials -n secrets-demo
kubectl delete -f namespace.yaml
kubectl delete storageclass encrypted-gp3

# Destroy AWS resources (KMS keys, EBS CSI role, add-on)
terraform destroy \
  -var="aws_region=eu-central-1" \
  -var="cluster_name=my-secure-cluster"
```

> **Note:** KMS keys are scheduled for deletion with a 7-day waiting period (`deletion_window_in_days = 7`). Data encrypted with the key (including secrets in etcd) cannot be decrypted after deletion. Disable the key first if you want to retain the encrypted data.
