# ── GuardDuty detector ────────────────────────────────────────────────────────
# Enables GuardDuty for the account in this region and turns on the Kubernetes
# audit log data source so GuardDuty can analyse EKS API activity.
resource "aws_guardduty_detector" "this" {
  enable = true

  datasources {
    kubernetes {
      audit_logs {
        enable = true
      }
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          enable = true
        }
      }
    }
  }

  tags = {
    Name  = "${var.cluster_name}-guardduty"
    Phase = "6"
  }
}

# ── EKS Runtime Monitoring feature ────────────────────────────────────────────
# This is the runtime threat detection capability from the transcript — detects
# crypto mining, C2 callbacks, metadata service enumeration, etc. inside pods.
# EKS_ADDON_MANAGEMENT is disabled here so we install the agent explicitly below.
resource "aws_guardduty_detector_feature" "eks_runtime" {
  detector_id = aws_guardduty_detector.this.id
  name        = "EKS_RUNTIME_MONITORING"
  status      = "ENABLED"

  additional_configuration {
    name   = "EKS_ADDON_MANAGEMENT"
    status = "DISABLED"
  }
}

# ── GuardDuty security agent (EKS add-on) ─────────────────────────────────────
# Deploys the GuardDuty agent DaemonSet to the cluster via the managed add-on.
# The transcript: "Deploy the GuardDuty security agent to the cluster via EKS Add-ons."
resource "aws_eks_addon" "guardduty_agent" {
  cluster_name = var.cluster_name
  addon_name   = "aws-guardduty-agent"

  depends_on = [aws_guardduty_detector_feature.eks_runtime]

  tags = {
    Phase = "6"
  }
}

output "guardduty_detector_id" {
  description = "GuardDuty detector ID for this region"
  value       = aws_guardduty_detector.this.id
}
