# Phase 6: Runtime Security & Auditing

> This walkthrough uses the live demo values from this repo and cluster setup:
> `cluster_name=my-secure-cluster`, `region=eu-central-1`.
> No account IDs are hardcoded — all values are derived at runtime via Terraform variables and data sources.
> If you are reusing this guide in another environment, update the variable defaults in `logging.tf`.

## Overview
A container image that passes every static and policy check can still become a threat once it is running. Malware embedded in a container may only activate at runtime, a zero-day can be exploited after deployment, or a misconfigured workload may run with more privilege than intended.

Following the course transcript and `Todo.md`, this phase implements three layers of runtime visibility:

1. **EKS Control Plane Logging** — audit and authenticator logs routed to CloudWatch so every API call is traceable.
2. **GuardDuty Runtime Monitoring** — a runtime agent on every node that detects crypto mining, command-and-control callbacks, metadata service enumeration, and more.
3. **CloudWatch Alarms** — metric filters on the audit log stream that fire when 403 Forbidden or 401 Unauthorized responses spike above a threshold.

---

## Step 1: Understand What Each Log Type Provides

EKS exposes five control plane log types. The transcript highlights two as most valuable for security:

| Log type | What it captures |
|----------|-----------------|
| `audit` | Every API request — **who did what when** |
| `authenticator` | IAM-to-Kubernetes RBAC mappings — **who was granted what access** |
| `api` | kube-apiserver operational logs |
| `controllerManager` | Controller reconciliation activity |
| `scheduler` | Pod scheduling decisions |

Before enabling logging, verify the current state:

```bash
aws eks describe-cluster \
  --name my-secure-cluster \
  --region eu-central-1 \
  --query 'cluster.logging' \
  --output json \
  --no-cli-pager
```

---

## Step 2: Enable Control Plane Logging and Create the Log Group

`logging.tf` creates the `/aws/eks/my-secure-cluster/cluster` CloudWatch log group with a 90-day retention policy, then calls `aws eks update-cluster-config` via a `null_resource` to enable all five log types.

> **Why pre-create the log group?** EKS will auto-create it if absent, but with no retention policy — logs accumulate indefinitely and incur unbounded storage costs.

```bash
cd phase-6-runtime-security
terraform init
terraform apply \
  -var="aws_region=eu-central-1" \
  -var="cluster_name=my-secure-cluster"
```

Verify logging was enabled:

```bash
aws eks describe-cluster \
  --name my-secure-cluster \
  --region eu-central-1 \
  --query 'cluster.logging.clusterLogging' \
  --output json \
  --no-cli-pager
```

You should see `"enabled": true` for all five log types.

---

## Step 3: Enable GuardDuty Runtime Monitoring

`guardduty.tf` does three things:
1. Creates a GuardDuty detector with Kubernetes audit log analysis and EBS malware scanning enabled.
2. Enables the `EKS_RUNTIME_MONITORING` feature — this is the runtime agent capability that detects threats like crypto mining, C2 callbacks, and metadata enumeration at the process level inside pods.
3. Installs the `aws-guardduty-agent` managed add-on to the cluster, which deploys the GuardDuty security agent as a DaemonSet.

The `terraform apply` from Step 2 handles all of this in one run.

### Verify the GuardDuty agent is running

```bash
kubectl get daemonset -n amazon-guardduty
```

You should see the `aws-guardduty-agent` DaemonSet with one pod per node.

### Verify GuardDuty is active in the console

```bash
aws guardduty list-detectors \
  --region eu-central-1 \
  --no-cli-pager

aws guardduty get-detector \
  --detector-id $(aws guardduty list-detectors --region eu-central-1 --query 'DetectorIds[0]' --output text) \
  --region eu-central-1 \
  --no-cli-pager
```

---

## Step 4: CloudWatch Alarms for Suspicious API Activity

`cloudwatch.tf` creates two metric filters on the audit log stream and a CloudWatch alarm for each:

| Alarm | Filter pattern | Threshold |
|-------|---------------|-----------|
| `my-secure-cluster-403-spike` | `$.responseStatus.code = 403` | ≥ 10 in 5 min |
| `my-secure-cluster-401-spike` | `$.responseStatus.code = 401` | ≥ 10 in 5 min |

The transcript: *"you suddenly have an increase in the number of HTTP forbidden or unauthorized responses"* — these alarms cover exactly that scenario.

### Verify the metric filters and alarms

```bash
aws cloudwatch describe-metric-filters \
  --log-group-name /aws/eks/my-secure-cluster/cluster \
  --region eu-central-1 \
  --no-cli-pager

aws cloudwatch describe-alarms \
  --alarm-name-prefix my-secure-cluster \
  --region eu-central-1 \
  --no-cli-pager
```

### Query audit logs with CloudWatch Logs Insights

Once audit logs are flowing, use Logs Insights to investigate suspicious activity:

```bash
# List recent 403 Forbidden events
aws logs start-query \
  --log-group-name /aws/eks/my-secure-cluster/cluster \
  --start-time $(date -d '1 hour ago' +%s) \
  --end-time $(date +%s) \
  --query-string 'fields @timestamp, user.username, requestURI, responseStatus.code
    | filter responseStatus.code = 403
    | sort @timestamp desc
    | limit 20' \
  --region eu-central-1 \
  --no-cli-pager
```

---

## What GuardDuty Runtime Monitoring Detects

The transcript lists these attack vectors as examples the runtime agent can catch:

| Threat | How GuardDuty detects it |
|--------|--------------------------|
| Crypto mining | Outbound connection to known cryptocurrency mining IPs/domains |
| Botnet / C2 | Connection to known command-and-control host IPs |
| Metadata enumeration | HTTP call to `169.254.169.254` (EC2 IMDS) from inside a container |
| Privilege escalation | Container attempting syscalls or file operations outside its expected profile |

GuardDuty findings appear in the GuardDuty console and can be forwarded to EventBridge for automated remediation.

---

## Recap from the Transcript

> "Even though a deployment may meet all of your security requirements when it's initially deployed, there are attack vectors that mean you should be checking for suspicious behavior continuously."

| Component | What it gives you |
|-----------|------------------|
| EKS audit logs | Immutable record of every API call — who, what, when |
| EKS authenticator logs | IAM authentication and RBAC authorization decisions |
| GuardDuty Runtime Monitoring | Real-time threat detection inside running pods |
| CloudWatch metric filters + alarms | Proactive alerting on suspicious API response patterns |
| CloudTrail Insights | Anomalous AWS API call volume from within the VPC |

---

## Clean Up

```bash
# Disable EKS control plane logging
aws eks update-cluster-config \
  --region eu-central-1 \
  --name my-secure-cluster \
  --logging '{"clusterLogging":[{"types":["api","audit","authenticator","controllerManager","scheduler"],"enabled":false}]}' \
  --no-cli-pager

# Destroy CloudWatch log group, GuardDuty, and alarms
terraform destroy \
  -var="aws_region=eu-central-1" \
  -var="cluster_name=my-secure-cluster"
```
