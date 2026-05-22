# Building an Amazon EKS Security Baseline

Amazon EKS makes it easy to start a Kubernetes cluster on AWS, but the real work begins after the control plane is running. Security in EKS is not a single feature or a one-time checklist. It is a layered posture that spans image hygiene, identity, network boundaries, data protection, and runtime monitoring.

This article walks through a practical security baseline for EKS, the reasoning behind each control, and the lessons that tend to matter most in production. Every section is grounded in working infrastructure: real AWS resources, real Kubernetes manifests, and real verification steps that were exercised against a live cluster.

## Secure the Container Images

Every Kubernetes workload begins with an image, which makes image security the natural starting point. If the image is vulnerable or overly privileged, the rest of the stack inherits that weakness before the pod even starts. The fundamentals are straightforward: use minimal base images, run as a non-root user, never set the `privileged` flag on a container, scan images before they are pushed, and enforce repository scanning in Amazon ECR. A Dockerfile linter such as Hadolint, run locally or in CI, adds a cheap second line of defense by catching bad patterns before the image is even built.

The broader lesson is that a secure deployment pipeline starts well before a pod ever reaches the cluster. When the image is small, hardened, and scanned, the attack surface is already much smaller by the time Kubernetes is involved.

## Control Who Can Access the Cluster

Once the image layer is under control, the next question is identity. EKS uses AWS IAM for authentication and Kubernetes RBAC for authorization, which means access spans two systems at once. EKS Cluster Access Management offers a cleaner way to map IAM principals to Kubernetes permissions and is the preferred path over the older `aws-auth` workflow.

The goal is access that is explicit, scoped, and reversible. Developers and testers should only get the permissions they need, namespace scoping should be preferred over broad cluster access, and cluster-admin style privileges should remain tightly controlled. One detail that is easy to miss: the IAM principal that creates the cluster is automatically a full cluster admin, and that principal should be removed (or replaced) once a proper set of access entries is in place. This is not only about blocking attackers. It also makes internal access easier to understand and audit as teams change.

## Build Network Boundaries

Kubernetes namespaces are helpful, but namespaces alone are not isolation. Pods can still talk to each other unless the network layer is controlled. A solid baseline establishes a default-deny posture and then opens only the traffic that is actually required. That is the difference between a flat pod network and a controlled application boundary.

In practice, network policy is what stops a compromised pod from moving laterally through the namespace. The model is simple: deny all pod-to-pod traffic by default, allow only the exact paths that are required, and keep frontend, backend, and unknown workloads separated. For workloads that need finer-grained isolation than a node-level security group can provide, EKS also supports security groups for pods, which attach an ENI and its own security group directly to the pod. Network segmentation should be paired with encryption in transit, whether through TLS on a load balancer, end-to-end TLS to the pod, or a service mesh handling mTLS between workloads.

## Remove Application Permissions from the Node Role

One of the most common EKS mistakes is letting workloads inherit permissions from the worker node IAM role. That pattern works until it becomes a privilege escalation problem. Pods should not rely on the node instance profile for application access. Application permissions belong on the workload identity itself.

Both modern EKS Pod Identity and the older IRSA model can achieve this, and the right choice depends on the workload. The security value is least privilege at the pod level: give the pod only the AWS actions it actually needs, avoid attaching application policies to the node group, and use a service account as the identity boundary. That shift moves AWS permissions away from infrastructure and onto the application that genuinely needs them.

## Protect Data at Rest and in Use

Data security is more than encrypting a disk. It also includes secrets, key management, and the way applications consume sensitive values. A complete baseline uses KMS-backed encryption for EBS and EFS volumes (and for RDS, when a database sits behind the cluster), envelope encryption for Kubernetes Secrets in `etcd`, and secret consumption through mounted volumes instead of environment variables. KMS keys should have automatic rotation enabled so that key material is refreshed on a regular cadence without breaking access to existing ciphertext.

A distinction worth making early is that Kubernetes Secrets are base64-encoded by default, not encrypted. They have to be protected at the storage layer and, ideally, encrypted again through envelope encryption. Mounted volumes are also a safer way to consume secrets inside pods than environment variables. Environment variables are convenient, but they are far more likely to leak into logs or debugging output. Volume mounts are temporary, isolated, and easier to clean up.

## Monitor Runtime Behavior and Audit Everything

This is where the cluster finally becomes observable, and it is the part that should never be skipped. Static controls are essential, but they cannot catch every threat. A pod can pass every build-time check and still become suspicious after it starts running, which is exactly why runtime security matters.

A strong runtime layer combines EKS control plane logging for audit and authenticator visibility, GuardDuty Runtime Monitoring for threat detection inside running workloads, and CloudWatch alarms for unusual authentication or authorization patterns. CloudTrail Insights complements this on the AWS API side by flagging unusual call patterns originating from inside the VPC, including from pods. The runtime threats that matter most are crypto mining behavior, command-and-control callbacks, metadata service enumeration, and unauthorized access attempts that show up as repeated 401 or 403 responses. The value here is not only detection. It is also accountability. Audit logs make it possible to reconstruct who did what and when, and runtime monitoring surfaces behavior that was never visible during deployment.

## What This Approach Shows in Practice

The main lesson from a full build is that EKS security is cumulative. Image hardening reduces software supply-chain exposure, access management limits who can reach the cluster, network policy limits lateral movement, pod identity limits AWS privilege, encryption limits data exposure, and runtime monitoring limits dwell time and detection gaps.

That layered approach is what makes the cluster resilient. No single control solves the problem, but together they create a much stronger baseline than any of them on their own.

## A Practical Security Mindset for EKS

The goal on EKS is not perfection. The goal is to make compromise harder, detection faster, and blast radius smaller. A hardened image, intentional IAM and RBAC boundaries, namespace-aware network policy, workload-bound AWS permissions, encryption at rest, protected secret usage, and early logging together turn a working cluster into a defensible one.

## Closing Thoughts

EKS makes it easy to run Kubernetes, but secure Kubernetes still requires deliberate design decisions. The controls are available, and when they are used together they form a strong operational baseline. The path that usually works best starts with image hardening and ends with runtime monitoring, which mirrors how a real security posture should evolve: from build time to deploy time to run time.

The right question for any EKS environment is not just whether it runs. The more important question is what happens when it is attacked.

---

## Let's Connect

If this was useful, or if you are working on something similar and want to compare notes, feel free to reach out.

- GitHub: [bansikah22](https://github.com/bansikah22)
- LinkedIn: [Tandap Noel Bansikah](https://www.linkedin.com/in/tandap-noel-bansikah/)
- Source code for this baseline: [bansikah22/eks-security](https://github.com/bansikah22/eks-security)
