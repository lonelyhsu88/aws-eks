# CLAUDE.md

This file provides guidance to Claude Code when working with AWS EKS infrastructure and deployments.

## Claude Best Practices

### Critical Thinking Habits

When designing solutions, ALWAYS consider these principles BEFORE proposing an approach:

#### 1. Identify Parallel Execution Opportunities
- **Ask**: Are these tasks independent? Can they run simultaneously?
- **Default to parallel**: If tasks have no dependencies, execute them concurrently
- **Example**: Testing 3 regions' website speed should run in parallel (~17 min), NOT sequentially (50 min)
- **Tool usage**: Use multiple tool calls in a single message for independent operations

#### 2. Optimize for Efficiency
- **Time**: What's the fastest approach that still meets requirements?
- **Resources**: Can we cache results, reuse computations, or use lighter tools?
- **Batch operations**: Process multiple items together when possible

#### 3. Proactive Solution Design
- **Don't wait for corrections**: Think through optimization from the start
- **Propose alternatives**: If multiple approaches exist, present trade-offs
  - Fast but resource-intensive vs. slow but efficient
  - Simple but limited vs. complex but flexible
- **Explain reasoning**: Share why you chose a particular approach

#### 4. Question Assumptions
- **Verify**: Does the obvious solution actually make sense here?
- **Consider edge cases**: What could go wrong?
- **Think holistically**: How does this fit into the larger system?

### Key Reminder
> "The first solution should be the optimized solution, not just a working solution that needs correction."

## Language Preferences

- **Communication**: Use Traditional Chinese (繁體中文) for all responses, explanations, analysis, and reports
- **Code Elements**: Use English for code, commit messages, comments, PR descriptions, and API documentation
- **Full development standards**: Refer to `~/.claude/instructions.md`

## Repository Structure

This repository contains AWS EKS (Elastic Kubernetes Service) infrastructure configurations and deployment manifests.

## Common Development Commands

### AWS CLI & kubectl
```bash
# Configure AWS credentials
aws configure

# Get EKS cluster info
aws eks describe-cluster --name <cluster-name> --region <region>

# Update kubeconfig
aws eks update-kubeconfig --name <cluster-name> --region <region>

# Check cluster context
kubectl config current-context

# Get cluster nodes
kubectl get nodes

# Get all pods
kubectl get pods --all-namespaces

# Get services
kubectl get svc --all-namespaces
```

### Kubernetes Operations
```bash
# Apply manifests
kubectl apply -f <manifest.yaml>

# Get pod logs
kubectl logs <pod-name> -n <namespace>

# Describe resources
kubectl describe pod <pod-name> -n <namespace>

# Execute commands in pod
kubectl exec -it <pod-name> -n <namespace> -- /bin/bash

# Port forwarding
kubectl port-forward <pod-name> <local-port>:<pod-port> -n <namespace>
```

## Architecture Overview

### AWS EKS Cluster
- **Orchestration**: Kubernetes on AWS EKS
- **Networking**: VPC with public/private subnets
- **Node Groups**: Managed node groups with auto-scaling
- **Storage**: EBS volumes via Storage Classes
- **Monitoring**: CloudWatch integration
- **Security**: IAM roles for service accounts (IRSA)

### Key Components
- **Control Plane**: Managed by AWS EKS
- **Worker Nodes**: EC2 instances in managed node groups
- **Load Balancing**: AWS ALB/NLB via ingress controllers
- **Service Mesh**: (If applicable - Istio, Linkerd, etc.)
- **CI/CD**: (If applicable - ArgoCD, Flux, Jenkins, etc.)

## Development Workflow

When working with this EKS infrastructure:
1. Ensure AWS credentials are properly configured
2. Update kubeconfig to point to the correct cluster
3. Verify cluster access with `kubectl get nodes`
4. Use kubectl for resource management
5. Follow GitOps practices for production deployments
6. Test changes in development/staging environments first

## Security Best Practices

- Use IAM roles for service accounts (IRSA) instead of hardcoded credentials
- Enable Pod Security Standards
- Use network policies to restrict pod-to-pod communication
- Regularly update cluster and node versions
- Enable audit logging for compliance
- Use AWS Secrets Manager or Kubernetes Secrets for sensitive data
- Implement least privilege access control

## Monitoring and Troubleshooting

- Check pod status: `kubectl get pods -n <namespace>`
- View logs: `kubectl logs <pod-name> -n <namespace>`
- Describe resources: `kubectl describe <resource> <name> -n <namespace>`
- Check events: `kubectl get events -n <namespace> --sort-by='.lastTimestamp'`
- Monitor cluster health via CloudWatch metrics
- Use kubectl top for resource usage: `kubectl top nodes` / `kubectl top pods`

## Notes

- All Kubernetes manifests should be version-controlled
- Use namespaces to organize resources
- Implement resource requests and limits for all pods
- Use ConfigMaps for configuration and Secrets for sensitive data
- Document any custom configurations or non-standard deployments
