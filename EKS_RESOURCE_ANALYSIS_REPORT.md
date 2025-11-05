# EKS Resource Analysis Report

**Cluster**: `gemini-game-prd`
**Region**: `ap-east-1`
**Date**: 2025-11-05
**Analysis By**: Claude Code

---

## 🚨 Executive Summary

**CRITICAL RESOURCE SHORTAGE DETECTED**

The EKS cluster is experiencing **severe memory resource constraints** with multiple services running out of memory. Immediate action required.

### Key Findings:
- ✅ **7 nodes** (c5a.xlarge) - all operational
- ⚠️ **142 pods** running across cluster
- 🔴 **Memory requests: 78-98%** (near capacity on most nodes)
- 🔴 **Memory limits over-committed: 182-256%**
- 🔴 **2 OOMKilled pods** detected
- 🔴 **11+ services exceeding HPA memory threshold** (>80%)
- 🔴 **Most HPAs configured with maxPods=1** (cannot scale)

---

## 📊 Current Cluster Status

### Node Overview

| Node | Instance Type | CPU Capacity | Memory Capacity | CPU Usage | Memory Usage |
|------|---------------|--------------|-----------------|-----------|--------------|
| ip-172-31-50-117 | c5a.xlarge | 4 cores | ~7.6GB | 4% (185m) | 40% (2742Mi) |
| ip-172-31-51-140 | c5a.xlarge | 4 cores | ~7.6GB | 4% (166m) | 40% (2734Mi) |
| ip-172-31-51-189 | c5a.xlarge | 4 cores | ~7.6GB | 3% (143m) | 42% (2890Mi) |
| ip-172-31-53-251 | c5a.xlarge | 4 cores | ~7.6GB | 13% (541m) | 45% (3093Mi) |
| ip-172-31-54-200 | c5a.xlarge | 4 cores | ~7.6GB | 8% (346m) | **57%** (3922Mi) |
| ip-172-31-55-42 | c5a.xlarge | 4 cores | ~7.6GB | 6% (245m) | 38% (2620Mi) |
| ip-172-31-55-85 | c5a.xlarge | 4 cores | ~7.6GB | 4% (168m) | 34% (2371Mi) |

**Total Cluster Resources:**
- **28 vCPUs** (4 cores × 7 nodes)
- **~56GB RAM** (8GB × 7 nodes)
- **142 pods** (~20 pods per node average)

---

## 🔴 Critical Issues

### 1. Memory Resource Allocation Crisis

**Memory Requests Saturation:**

| Node | Memory Requests | Memory Limits | Status |
|------|-----------------|---------------|--------|
| ip-172-31-51-140 | **98%** | 256% | 🔴 CRITICAL |
| ip-172-31-55-85 | **92%** | 210% | 🔴 CRITICAL |
| ip-172-31-55-42 | **91%** | 182% | 🔴 CRITICAL |
| ip-172-31-53-251 | **89%** | 236% | 🔴 WARNING |
| ip-172-31-50-117 | **88%** | 229% | 🔴 WARNING |
| ip-172-31-51-189 | 87% | 222% | ⚠️ WARNING |
| ip-172-31-54-200 | 78% | 222% | ⚠️ ELEVATED |

**Problem**: When memory requests reach 90%+, Kubernetes scheduler **cannot schedule new pods** on those nodes, even if actual usage is lower.

**Impact**:
- New pods will remain in `Pending` state
- Auto-scaling is blocked
- Service updates may fail
- Zero headroom for traffic spikes

---

### 2. OOMKilled Pods

**Confirmed Memory-Related Failures:**

| Namespace | Pod | Status | Impact |
|-----------|-----|--------|--------|
| `arcade-gate-prd` | `arcade-gate-0` | OOMKilled | Game service disruption |
| `mgmtapi-prd` | `mgmtapi-6ddccbb46b-47275` | OOMKilled | Management API disruption |

**Root Cause**: Memory limits too low or actual usage exceeds configured limits.

---

### 3. HPA Memory Threshold Violations

**Services Exceeding 80% Memory Threshold:**

| Service | Memory Usage | Threshold | Overage | MaxPods | Can Scale? |
|---------|--------------|-----------|---------|---------|------------|
| `wilddiggr-prd` | **183%** | 80% | +103% | 1 | ❌ NO |
| `arcade-gate-prd` | **154%** | 80% | +74% | 1 | ❌ NO |
| `forestteaparty-prd` | **111%** | 80% | +31% | 1 | ❌ NO |
| `exgameapi-prd` | 98% | 80% | +18% | 1 | ❌ NO |
| `lostruins-prd` | 91% | 80% | +11% | 1 | ❌ NO |
| `cavebingo-prd` | 89% | 80% | +9% | 1 | ❌ NO |
| `luckydropcoc2-prd` | 87% | 80% | +7% | 1 | ❌ NO |
| `caribbeanbingo-prd` | 85% | 80% | +5% | 1 | ❌ NO |
| `goldenclover-prd` | 84% | 80% | +4% | 1 | ❌ NO |
| `steampunk2-prd` | 74% | 80% | (safe) | 1 | ❌ NO |
| `partnerapi-prd` | 71% | 80% | (safe) | 1 | ❌ NO |

**Critical Problem**: Most HPAs are configured with `minPods=1` and `maxPods=1`, meaning **horizontal scaling is disabled** even when memory exceeds thresholds.

---

### 4. HPA Metrics Failures

**Services Unable to Retrieve Metrics:**

```
mgmtapi-prd: "no metrics returned from resource metrics API"
goldenclover-prd: "pods might be unready" / "no metrics returned"
```

**Impact**: HPA cannot make scaling decisions without metrics, leading to:
- No automatic scaling
- Service degradation
- Increased OOMKilled risk

---

## 📈 Resource Over-Commitment Analysis

### CPU Limits (Over-Committed)

All nodes have CPU limits exceeding 100%:
- Range: **94% - 250%**
- Worst: **250%** (2.5x over-committed)

**Risk**: If all pods hit their CPU limits simultaneously, severe throttling will occur.

### Memory Limits (Severely Over-Committed)

All nodes have memory limits exceeding 100%:
- Range: **182% - 256%**
- Worst: **256%** (2.56x over-committed)

**Risk**:
- If multiple pods hit memory limits, mass OOMKilled events
- Potential node instability
- Service cascading failures

---

## 🎯 Root Cause Analysis

### 1. **Insufficient Node Resources**
- **c5a.xlarge** instances only provide **8GB RAM** per node
- With 20+ pods per node, average available memory per pod: **~350MB**
- Many game services require **500MB-1GB+ memory**

### 2. **HPA Misconfiguration**
- Most HPAs set to `maxPods=1` (no horizontal scaling)
- Some HPAs unable to retrieve metrics (metrics-server issues)
- Memory threshold at 80% is appropriate, but pods cannot scale out

### 3. **Resource Request/Limit Mismatch**
- Some services have very low requests but high limits
- Causes over-commitment and scheduling issues
- Example: `arcade-gate-0` - Request: 528Mi, Limit: 1724Mi (3.2x difference)

### 4. **No Headroom for Growth**
- Memory requests at 78-98% leave **no room for**:
  - New deployments
  - Rolling updates (require 2x pods temporarily)
  - Traffic spikes
  - Service recovery after OOMKills

---

## ✅ Recommended Solutions

### 🚨 Immediate Actions (Within 24 Hours)

#### 1. **Scale Out EKS Node Group** ⭐ PRIORITY 1
```bash
# Increase node count to provide immediate relief
aws eks update-nodegroup-config \
  --cluster-name gemini-game-prd \
  --nodegroup-name <nodegroup-name> \
  --region ap-east-1 \
  --scaling-config minSize=10,maxSize=15,desiredSize=10
```

**Expected Impact**:
- Reduce memory request pressure from 90%+ to ~60%
- Provide headroom for scheduling new pods
- Allow rolling updates to proceed

**Cost**: +3 c5a.xlarge nodes (~$260/month at HK prices)

---

#### 2. **Fix Critical HPA Configurations** ⭐ PRIORITY 1

**Services requiring immediate HPA fixes:**

```yaml
# Example fix for wilddiggr-prd (183% memory usage!)
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: wilddiggr-hpa
  namespace: wilddiggr-prd
spec:
  maxReplicas: 3  # Change from 1 to 3
  minReplicas: 1
  metrics:
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
```

**Apply to these services:**
- `wilddiggr-prd` (183% - CRITICAL)
- `arcade-gate-prd` (154%)
- `forestteaparty-prd` (111%)
- `exgameapi-prd` (98%)
- `lostruins-prd` (91%)
- `cavebingo-prd` (89%)
- `luckydropcoc2-prd` (87%)

---

#### 3. **Increase Memory Limits for OOMKilled Pods** ⭐ PRIORITY 2

```yaml
# arcade-gate-prd (OOMKilled)
resources:
  requests:
    memory: 528Mi    # Keep request same
  limits:
    memory: 2500Mi   # Increase from 1724Mi to 2500Mi

# mgmtapi-prd (OOMKilled)
resources:
  requests:
    memory: <check current>
  limits:
    memory: <increase by 50%>
```

---

### 📅 Short-Term Actions (Within 1 Week)

#### 4. **Upgrade to Larger Instance Type**

Consider upgrading from **c5a.xlarge** to **c5a.2xlarge**:

| Spec | c5a.xlarge | c5a.2xlarge | Benefit |
|------|------------|-------------|---------|
| vCPU | 4 | 8 | +100% |
| Memory | 8 GB | 16 GB | **+100%** |
| Cost | ~$0.087/hr | ~$0.174/hr | 2x |

**With 7 nodes**:
- Total RAM: 56GB → **112GB** (+100%)
- Memory request headroom: 90%+ → ~45%
- Cost increase: ~$435/month

**Implementation**:
1. Create new node group with c5a.2xlarge
2. Cordon old nodes
3. Drain pods to new nodes
4. Delete old node group

---

#### 5. **Implement Cluster Autoscaler**

Install Cluster Autoscaler to automatically adjust node count:

```bash
helm repo add autoscaler https://kubernetes.github.io/autoscaler
helm install cluster-autoscaler autoscaler/cluster-autoscaler \
  --set autoDiscovery.clusterName=gemini-game-prd \
  --set awsRegion=ap-east-1 \
  --set rbac.create=true
```

**Benefits**:
- Automatically adds nodes when pods are pending
- Removes nodes when under-utilized
- Reduces manual intervention

---

#### 6. **Fix Metrics Server Issues**

Verify metrics-server is running correctly:

```bash
kubectl get deployment metrics-server -n kube-system
kubectl logs -n kube-system deployment/metrics-server
```

If missing or broken:
```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

---

### 🔧 Medium-Term Actions (Within 1 Month)

#### 7. **Resource Audit and Right-Sizing**

For each service, review and adjust resource requests/limits:

**Methodology**:
```bash
# Get actual usage over time
kubectl top pods -n <namespace> --sort-by=memory

# Compare with configured requests/limits
kubectl get pod <pod-name> -n <namespace> -o yaml | grep -A 5 resources:

# Adjust to:
# - Request = P90 actual usage
# - Limit = P99 actual usage + 20% buffer
```

**Example Services to Review**:
- `wilddiggr`: Currently using 183% of requested memory
- `arcade-gate`: Experiencing OOMKills
- `forestteaparty`: Using 111% of requested memory

---

#### 8. **Implement Resource Quotas per Namespace**

Prevent any single namespace from consuming all resources:

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: game-quota
  namespace: wilddiggr-prd
spec:
  hard:
    requests.cpu: "2"
    requests.memory: 4Gi
    limits.cpu: "4"
    limits.memory: 8Gi
    pods: "5"
```

---

#### 9. **Set Up Monitoring and Alerting**

Configure alerts for resource thresholds:

**Prometheus Alert Rules**:
```yaml
- alert: NodeMemoryPressure
  expr: (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) < 0.1
  for: 5m
  annotations:
    summary: "Node {{ $labels.node }} under memory pressure"

- alert: PodMemoryUsageHigh
  expr: (container_memory_usage_bytes / container_spec_memory_limit_bytes) > 0.9
  for: 5m
  annotations:
    summary: "Pod {{ $labels.pod }} using >90% memory"
```

---

## 📊 Cost-Benefit Analysis

### Option A: Scale Out (Add 3 Nodes)
- **Cost**: ~$260/month
- **Implementation**: 1 hour
- **Benefit**: Immediate relief, 30% more capacity
- **Risk**: Low

### Option B: Scale Up (Upgrade to c5a.2xlarge)
- **Cost**: ~$435/month
- **Implementation**: 2-4 hours (requires node migration)
- **Benefit**: 100% more capacity, better pod density
- **Risk**: Medium (requires pod migration)

### Option C: Hybrid Approach (Add 3 nodes + Fix HPAs)
- **Cost**: ~$260/month
- **Implementation**: 2-3 hours
- **Benefit**: Immediate relief + better resource distribution
- **Risk**: Low
- **⭐ RECOMMENDED**

---

## 🎯 Implementation Plan

### Phase 1: Emergency Relief (Day 1)
1. ✅ Scale node group from 7 to 10 nodes
2. ✅ Update HPA maxPods for critical services (wilddiggr, arcade-gate, forestteaparty)
3. ✅ Increase memory limits for OOMKilled pods
4. ✅ Verify metrics-server is functioning

**Expected Outcome**: Cluster stable, no more OOMKills

---

### Phase 2: Optimization (Week 1)
1. ✅ Install Cluster Autoscaler
2. ✅ Audit top 20 memory-consuming services
3. ✅ Right-size resource requests/limits
4. ✅ Set up resource quotas for game namespaces

**Expected Outcome**: Efficient resource utilization

---

### Phase 3: Long-Term Stability (Week 2-4)
1. ✅ Set up comprehensive monitoring dashboards
2. ✅ Configure alerting rules
3. ✅ Document resource management runbooks
4. ✅ Consider upgrading to c5a.2xlarge if needed

**Expected Outcome**: Proactive resource management

---

## 📝 Monitoring Recommendations

### Key Metrics to Watch

1. **Node Memory Requests**: Should stay below **75%**
2. **Pod Memory Usage**: Should stay below **80%** of limits
3. **OOMKilled Events**: Should be **zero**
4. **HPA Memory Metrics**: All services should report metrics
5. **Pending Pods**: Should be **zero** (except during scale-up)

### Recommended Dashboards

1. **Cluster Overview Dashboard**
   - Node resource usage (CPU/Memory)
   - Pod distribution per node
   - HPA status

2. **Service Health Dashboard**
   - Memory usage per service
   - OOMKilled events
   - HPA scaling events

3. **Capacity Planning Dashboard**
   - Resource request trends
   - Node capacity forecast
   - Cost projection

---

## 🚀 Next Steps

### Immediate (Do Now)
1. [ ] Scale node group to 10 nodes
2. [ ] Update HPAs for critical services
3. [ ] Fix OOMKilled pods

### This Week
1. [ ] Install Cluster Autoscaler
2. [ ] Audit and right-size resources
3. [ ] Verify metrics-server

### This Month
1. [ ] Implement monitoring/alerting
2. [ ] Set up resource quotas
3. [ ] Evaluate instance type upgrade

---

## 📞 Appendix

### Useful Commands

```bash
# Check node resource allocation
kubectl describe nodes | grep -A 5 "Allocated resources"

# Find pods with high memory usage
kubectl top pods --all-namespaces --sort-by=memory | head -20

# Check for OOMKilled pods
kubectl get pods --all-namespaces -o json | \
  jq -r '.items[] | select(.status.containerStatuses[]?.lastState.terminated.reason == "OOMKilled") | "\(.metadata.namespace) \(.metadata.name)"'

# Check HPA status
kubectl get hpa --all-namespaces

# View resource requests/limits for a namespace
kubectl describe ns <namespace>
```

### References

- [EKS Best Practices - Resource Management](https://aws.github.io/aws-eks-best-practices/scalability/docs/control-plane/)
- [Kubernetes Resource Management](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)
- [HPA Walkthrough](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale-walkthrough/)

---

**Report Generated**: 2025-11-05
**Analysis Tool**: Claude Code
**Cluster**: gemini-game-prd (ap-east-1)
