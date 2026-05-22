# Phase 3: Network Security and Isolation

## Overview
By default, Kubernetes allows all pods in a cluster to communicate with each other freely. In a secure Amazon EKS environment, this flat network model must be strictly controlled to prevent lateral movement during a breach.

This phase focuses on **East-West Traffic Isolation** (pod-to-pod communication) using Kubernetes `NetworkPolicy`, which is now natively supported by the default AWS VPC CNI plugin in modern EKS clusters!

---

## Step 1: Implement a Default Deny Policy
A core best practice in Kubernetes security is to implement a "Default Deny" network policy for sensitive namespaces. This policy drops all incoming traffic by default, forcing developers to explicitly whitelist required communication.

We have provided a default deny policy in `network-policy.yaml`.

---

## Step 2: Implement Explicit Allow Policies
Once traffic is denied by default, we selectively allow specific pods to communicate based on their labels.

In our example, we will deploy three pods: a `frontend`, a `backend`, and an unauthorized `rogue` pod. We will create a Network Policy that strictly allows only the `frontend` to communicate with the `backend` over port 80.

### Implementation
1. **Apply the Sample Application Pods:**
   Deploy the `frontend`, `backend`, and `rogue` pods to the `development` namespace.
   ```bash
   kubectl apply -f test-pods.yaml
   ```

2. **Apply the Network Policies:**
   Apply the default deny policy, and the specific allow policy.
   ```bash
   kubectl apply -f network-policy.yaml
   ```

---

## Step 3: Verify Network Isolation
Test that the network policies are successfully blocking lateral movement.

**1. Test Authorized Traffic (Frontend -> Backend)**
This should succeed immediately because our `NetworkPolicy` explicitly allows pods labeled `app: frontend` to access pods labeled `app: backend` on port 80.
```bash
kubectl exec -n development deploy/frontend -- wget -qO- --timeout=3 http://backend
```

**2. Test Unauthorized Traffic (Rogue -> Backend)**
This should **FAIL / TIMEOUT** because the `rogue` pod does not have the `app: frontend` label. It hits the default deny policy, proving that an attacker compromising the rogue pod cannot move laterally to the backend!
```bash
kubectl exec -n development deploy/rogue -- wget -qO- --timeout=3 http://backend
```

---

## (Optional) Security Groups for Pods
For strict integration with AWS services (like RDS databases or ElastiCache), EKS supports attaching actual AWS Security Groups directly to Kubernetes Pods via the `SecurityGroupPolicy` CRD. This moves the network boundary from the Kubernetes Software Defined Network directly to the AWS EC2 hypervisor level. *(We cover standard Kubernetes NetworkPolicies here, as they are universally applicable across clusters without needing extra CRDs).*
