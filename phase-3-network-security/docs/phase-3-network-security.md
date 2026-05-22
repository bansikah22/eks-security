# Phase 3: Network Security and Isolation

## Overview
By default, Kubernetes allows all pods in a cluster to communicate with each other freely. In a secure Amazon EKS environment, this flat network model must be strictly controlled to prevent lateral movement during a breach.

This phase focuses on **East-West Traffic Isolation** (pod-to-pod communication) using Kubernetes `NetworkPolicy`, which is natively supported by the AWS VPC CNI plugin when explicitly enabled.

---

## Prerequisites: Enable NetworkPolicy Enforcement on VPC CNI

By default, the AWS VPC CNI plugin does **NOT** enforce Kubernetes NetworkPolicies. You must explicitly enable the network policy agent via the EKS managed add-on API. Without this step, all NetworkPolicy resources will be silently ignored.

**1. Register VPC CNI as a managed add-on with network policy enabled:**
```bash
aws eks create-addon \
  --cluster-name <CLUSTER_NAME> \
  --addon-name vpc-cni \
  --configuration-values '{"enableNetworkPolicy": "true"}' \
  --resolve-conflicts OVERWRITE \
  --region <REGION>
```

**2. Wait for the add-on to become active:**
```bash
aws eks wait addon-active \
  --cluster-name <CLUSTER_NAME> \
  --addon-name vpc-cni \
  --region <REGION>
```

**3. Verify the network policy agent is running:**
```bash
kubectl logs -n kube-system -l k8s-app=aws-node -c aws-eks-nodeagent --tail=10
```

**Important:** Any pods that were running before the add-on was enabled will NOT be subject to network policy enforcement. You must restart them after enabling the add-on so the eBPF hooks can attach to their network interfaces.

---

## Step 1: Implement a Default Deny Policy
A core best practice in Kubernetes security is to implement a "Default Deny" network policy for sensitive namespaces. This policy drops all incoming traffic by default, forcing developers to explicitly whitelist required communication.

The `network-policy.yaml` file contains a default deny policy that selects ALL pods in the `development` namespace and blocks all ingress traffic.

---

## Step 2: Implement Explicit Allow Policies
Once traffic is denied by default, we selectively allow specific pods to communicate based on their labels.

In our example, we deploy three pods: a `frontend`, a `backend`, and an unauthorized `rogue` pod. We create a NetworkPolicy that strictly allows only the `frontend` to communicate with the `backend` over port 80.

### Implementation
**1. Deploy the sample application pods:**
```bash
kubectl apply -f test-pods.yaml
```

**2. Apply the network policies:**
```bash
kubectl apply -f network-policy.yaml
```

**3. Restart pods to ensure eBPF hooks are attached:**
```bash
kubectl rollout restart deployment frontend backend rogue -n development
kubectl rollout status deployment/frontend deployment/backend deployment/rogue -n development
```

---

## Step 3: Verify Network Isolation
Test that the network policies are successfully blocking lateral movement.

**1. Test Authorized Traffic (Frontend -> Backend)**
This should succeed because our NetworkPolicy explicitly allows pods labeled `app: frontend` to access pods labeled `app: backend` on port 80.
```bash
kubectl exec -n development deploy/frontend -- wget -qO- --timeout=3 http://backend
```

**2. Test Unauthorized Traffic (Rogue -> Backend)**
This should **TIMEOUT** because the `rogue` pod does not have the `app: frontend` label. It hits the default deny policy, proving that an attacker compromising the rogue pod cannot move laterally to the backend.
```bash
kubectl exec -n development deploy/rogue -- wget -qO- --timeout=3 http://backend
```
Expected output: `wget: download timed out`

---

## (Optional) Security Groups for Pods
For strict integration with AWS services (like RDS databases or ElastiCache), EKS supports attaching actual AWS Security Groups directly to Kubernetes Pods via the `SecurityGroupPolicy` CRD. This moves the network boundary from the Kubernetes Software Defined Network directly to the AWS EC2 hypervisor level. *(We cover standard Kubernetes NetworkPolicies here, as they are universally applicable across clusters without needing extra CRDs.)*

---

## Clean Up
Remove the test pods and network policies when finished testing.

```bash
kubectl delete -f test-pods.yaml
kubectl delete -f network-policy.yaml
```
