# eks-security

A hands-on security baseline for Amazon EKS, built phase by phase with Terraform and Kubernetes manifests. Each phase tackles one layer of the stack — from container images to runtime monitoring — and ships working code plus a walkthrough.

## Phases

| # | Focus | Path |
|---|---|---|
| 1 | Securing container images (hardened Dockerfile, ECR with scan-on-push, KMS) | [phase-1-securing-images/](phase-1-securing-images/) |
| 2 | Cluster access management (EKS Access Entries, IAM, RBAC scoping) | [phase-2-cluster-access/](phase-2-cluster-access/) |
| 3 | Network security (default-deny `NetworkPolicy`, tiered allow rules) | [phase-3-network-security/](phase-3-network-security/) |
| 4 | Application permissions (EKS Pod Identity / IRSA, least-privilege IAM) | [phase-4-application-permissions/](phase-4-application-permissions/) |
| 5 | Data security (KMS for EBS/EFS, envelope encryption for Secrets, mounted secrets) | [phase-5-data-security/](phase-5-data-security/) |
| 6 | Runtime security (control plane logs, GuardDuty Runtime Monitoring, CloudWatch alarms) | [phase-6-runtime-security/](phase-6-runtime-security/) |

Every phase has its own `docs/` folder with a step-by-step walkthrough and screenshots.

## Article

A prose write-up of the full baseline lives at [docs/article/amazon-eks-security-baseline.md](docs/article/amazon-eks-security-baseline.md).

## Prerequisites

- AWS account with permissions to manage EKS, IAM, VPC, KMS, ECR, GuardDuty, and CloudWatch
- Terraform `>= 1.5` and AWS provider `~> 5.0`
- `kubectl`, `aws` CLI v2, and Docker
- Region used in the examples: `eu-central-1`

## Usage

Each phase directory is self-contained Terraform. Apply them in order:

```bash
cd phase-1-securing-images && terraform init && terraform apply
cd ../phase-2-cluster-access && terraform init && terraform apply
# ... continue through phase-6
```

Kubernetes manifests in phases 3, 4, and 5 are applied with `kubectl apply -f <file>` once the cluster from phase 2 is reachable.

## Teardown

Destroy in reverse order to avoid dependency errors:

```bash
cd phase-6-runtime-security && terraform destroy
cd ../phase-5-data-security    && terraform destroy
cd ../phase-4-application-permissions && terraform destroy
cd ../phase-3-network-security && terraform destroy   # if Terraform-managed
cd ../phase-2-cluster-access   && terraform destroy
cd ../phase-1-securing-images  && terraform destroy
```

Remove any manually created Kubernetes resources (`kubectl delete -f ...`) and S3/demo buckets before destroying their parent stack.

## License

See [LICENSE](LICENSE).
