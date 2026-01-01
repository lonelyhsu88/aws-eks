# Oracle Cloud Infrastructure (OCI) Migration Resource Inventory

> **Document Purpose**: Comprehensive resource specification for migrating Gemini Gaming Platform from AWS EKS to Oracle Cloud Infrastructure (OCI)
>
> **Source Environment**: AWS EKS (gemini-game-prd, ap-east-1)
>
> **Date**: 2026-01-02
>
> **Status**: Production Environment Analysis

---

## Executive Summary

### Total Resource Requirements

| Resource Category | Quantity | Specifications |
|------------------|----------|----------------|
| **Compute (Kubernetes)** | 36 vCPU | 72 GB RAM across 9 worker nodes |
| **Database (PostgreSQL)** | 10 vCPU | 32 GB RAM, 11.82 TB storage |
| **Total Infrastructure** | **46 vCPU** | **104 GB RAM, 11.82 TB storage** |
| **Application Workloads** | 161 pods | 92 namespaces, 70 StatefulSets |
| **Load Balancers** | 5 | 4 ALB (Layer 7) + 1 NLB (Layer 4) |
| **Container Images** | 81 repositories | Stored in Amazon ECR |

### Key Architecture Components

- **Orchestration**: Kubernetes 1.34 on AWS EKS → **OKE (Oracle Kubernetes Engine)**
- **Service Mesh**: Istio (Traffic management, mTLS, observability)
- **GitOps**: ArgoCD (Declarative continuous deployment)
- **Monitoring**: Prometheus + Thanos + Alertmanager
- **Logging**: Filebeat → CloudWatch Logs
- **Database**: PostgreSQL 14.15 Multi-AZ with read replicas

---

## 1. Compute Resources (Kubernetes Cluster)

### 1.1 Current AWS EKS Configuration

**EKS Cluster**: `gemini-game-prd`
- **Kubernetes Version**: 1.34
- **Platform Version**: eks.9
- **Region**: ap-east-1 (Hong Kong)
- **Availability Zones**: 3 AZs (ap-east-1a, ap-east-1b, ap-east-1c)

### 1.2 Worker Node Details

| Node Group | Instance Type | vCPU | RAM (GB) | Nodes | Total vCPU | Total RAM (GB) | AZ Distribution |
|-----------|--------------|------|----------|-------|------------|----------------|-----------------|
| gemini-arcade-new | c5a.xlarge | 4 | 8 | 2 | 8 | 16 | ap-east-1a (2) |
| gemini-base | c5a.xlarge | 4 | 8 | 1 | 4 | 8 | ap-east-1b (1) |
| gemini-bg | c5a.xlarge | 4 | 8 | 4 | 16 | 32 | ap-east-1b (1), ap-east-1c (3) |
| gemini-hash | c5a.xlarge | 4 | 8 | 2 | 8 | 16 | ap-east-1c (2) |
| **Total** | - | - | - | **9** | **36** | **72** | 3 AZs |

**Node Specifications**:
- **CPU Architecture**: AMD EPYC 7R32 (x86_64)
- **OS**: Amazon Linux 2 (Kernel 5.10)
- **Container Runtime**: containerd 1.7.11
- **Kubelet Version**: 1.34

**Node Allocatable Resources** (per node):
- **Pods**: 58 max pods
- **CPU**: 3920m (3.92 vCPU)
- **Memory**: ~6.8 GB

### 1.3 Resource Utilization Analysis

| Metric | Requested | Actual Usage | Efficiency |
|--------|-----------|--------------|------------|
| **CPU** | 24-58% | 2-8% | Over-provisioned |
| **Memory** | 68-99% | 28-54% | Moderate utilization |
| **Pods per Node** | 10-20 | - | 17-35% of max capacity |

**Key Findings**:
- CPU is significantly over-provisioned (8-10x headroom)
- Memory requests are high (68-99%) but actual usage moderate (28-54%)
- Opportunity for right-sizing in OCI migration

### 1.4 OCI Mapping: OKE (Oracle Kubernetes Engine)

**Recommended OCI Compute Shapes**:

| Current AWS | OCI Equivalent | vCPU | RAM (GB) | Notes |
|-------------|----------------|------|----------|-------|
| c5a.xlarge (AMD) | VM.Standard.E4.Flex | 4 | 8-16 | Flexible, AMD EPYC 7J13 |
| c5a.xlarge (AMD) | VM.Standard.E5.Flex | 4 | 8-16 | Latest gen, AMD EPYC 9J14 |
| - | VM.Optimized3.Flex | 4 | 8 | Compute-optimized (Intel) |

**OKE Cluster Configuration**:
- **Kubernetes Version**: 1.34 (OKE supports up to 1.31 as of Jan 2026, verify latest)
- **Control Plane**: Managed by OCI (similar to EKS)
- **Node Pools**: 4 node pools matching current architecture
- **Availability Domains**: 3 ADs in OCI region (equivalent to AWS AZs)

**Sizing Recommendation**:
- **Option 1 (Like-for-like)**: 9 × VM.Standard.E5.Flex (4 OCPU, 8 GB RAM) = 36 OCPU, 72 GB RAM
- **Option 2 (Optimized)**: 6 × VM.Standard.E5.Flex (6 OCPU, 12 GB RAM) = 36 OCPU, 72 GB RAM
  - Consolidate nodes based on low CPU utilization
  - Reduces node management overhead
- **Option 3 (Right-sized)**: 5 × VM.Standard.E5.Flex (8 OCPU, 16 GB RAM) = 40 OCPU, 80 GB RAM
  - Better resource density
  - Improved scheduling efficiency

---

## 2. Database Resources (PostgreSQL)

### 2.1 Current AWS RDS Configuration

| Database | Instance Class | vCPU | RAM (GB) | Storage (GB) | Type | Purpose |
|----------|---------------|------|----------|--------------|------|---------|
| bingo-prd | db.m6g.large | 2 | 8 | 2,750 | Multi-AZ | Primary game database |
| bingo-prd-backstage | db.m6g.large | 2 | 8 | 5,024 | Multi-AZ | Backoffice/Admin system |
| bingo-prd-loyalty | db.t4g.medium | 2 | 4 | 200 | Multi-AZ | Loyalty system |
| bingo-prd-replica1 | db.m6g.large | 2 | 8 | 2,662 | Read Replica | Read replica for game DB |
| bingo-prd-backstage-replica1 | db.t4g.medium | 2 | 4 | 1,465 | Read Replica | Read replica for backoffice |
| **Total** | - | **10** | **32** | **12,101 GB (11.82 TB)** | - | - |

**Database Configuration**:
- **Engine**: PostgreSQL 14.15
- **Multi-AZ**: Enabled for primary instances (automatic failover)
- **Backup**: Automated backups with 7-day retention
- **Point-in-Time Recovery (PITR)**: Enabled
- **Read Replicas**: 2 replicas for read traffic distribution

### 2.2 OCI Mapping: Database Services

**Option 1: OCI Database Service (PostgreSQL)**

| Current RDS | OCI DB System Shape | OCPU | RAM (GB) | Storage (GB) | Notes |
|-------------|---------------------|------|----------|--------------|-------|
| db.m6g.large | VM.Standard.E4.Flex | 2 | 16 | 2,750 | General purpose |
| db.m6g.large | VM.Standard.E4.Flex | 2 | 16 | 5,024 | Backoffice |
| db.t4g.medium | VM.Standard.E4.Flex | 2 | 8 | 200 | Loyalty |
| **Replicas** | Data Guard / GoldenGate | 4 | 24 | 4,127 | Read replicas |
| **Total** | - | **10** | **64** | **12,101** | - |

**Features**:
- **High Availability**: OCI Database Cloud Service with Data Guard
- **Backup**: Automated backups with configurable retention
- **Performance**: Block Volumes with tunable IOPS/throughput
- **Scaling**: Flexible OCPU and storage scaling

**Option 2: MySQL Database Service (Migration Required)**

If migrating from PostgreSQL → MySQL:
- **MySQL HeatWave**: 2-10 OCPU shapes with in-memory analytics
- **High Availability**: Automatic failover with multiple availability domains
- **Read Replicas**: Built-in replication support

**Recommended Approach**: OCI Database Service with PostgreSQL
- Minimizes application changes
- Direct migration path with database tools (AWS DMS → OCI Data Integration)
- Supports PostgreSQL 14.x

### 2.3 Storage Configuration

**Block Volumes** (equivalent to AWS EBS):
- **Storage Type**: Block Volume (High Performance)
- **IOPS**: 25,000+ IOPS per volume (equivalent to gp3)
- **Throughput**: 480 MB/s per volume
- **Backup**: Automatic block volume backups

**Total Database Storage**: 11.82 TB
- **Volume Configuration**:
  - Primary databases: 3 volumes (2.75 TB, 5.02 TB, 200 GB)
  - Read replicas: 2 volumes (2.66 TB, 1.46 TB)

---

## 3. Storage Resources

### 3.1 Persistent Storage (Kubernetes PVCs)

| PVC Name | Namespace | Storage Class | Size | Usage |
|----------|-----------|---------------|------|-------|
| storage-prometheus-prometheus-0 | monitoring | gp2 | 50 Gi | Metrics storage |
| storage-alertmanager-alertmanager-0 | monitoring | gp2 | 10 Gi | Alert history |
| data-redis-master-0 | redis | gp2 | 20 Gi | Redis cache |
| **Total** | - | - | **80 Gi** | - |

**OCI Mapping**: Block Volume
- **Storage Class**: OCI Block Volume (Performance tier)
- **IOPS**: 25,000+ IOPS (high performance tier)
- **Snapshot**: Automated snapshots for backup

### 3.2 Node Storage (EBS Volumes)

| Node | Volume Type | Size | IOPS Capability |
|------|-------------|------|-----------------|
| 9 worker nodes | gp3 | 50-100 GB each | 3,000-16,000 IOPS |

**OCI Mapping**: Boot Volumes + Block Volumes
- **Boot Volumes**: 100 GB per node (OS + container runtime)
- **Block Volumes**: Additional storage for container images and ephemeral data

### 3.3 Object Storage (S3 Buckets)

| Bucket | Purpose | Estimated Size |
|--------|---------|----------------|
| gemini-game-logs | Application logs | ~500 GB |
| gemini-game-backups | Database backups | ~1 TB |
| gemini-game-assets | Static assets | ~200 GB |
| gemini-game-monitoring | Monitoring data | ~100 GB |
| (Others) | Various | ~200 GB |
| **Total** | - | **~2 TB** |

**OCI Mapping**: Object Storage
- **Storage Tier**: Standard (for frequently accessed data)
- **Archive Tier**: Archive Storage (for backup retention)
- **Features**:
  - Lifecycle policies (auto-tier to Archive)
  - Versioning enabled
  - Cross-region replication (optional)

### 3.4 Container Registry (ECR)

- **Repositories**: 81 container image repositories
- **Total Size**: ~500 GB (estimated)
- **OCI Mapping**: OCI Container Registry (OCIR)
  - Fully managed container registry
  - Integrated with OKE
  - Vulnerability scanning

---

## 4. Network Architecture

### 4.1 Load Balancers

| Load Balancer | Type | Purpose | Listeners |
|--------------|------|---------|-----------|
| ALB-1 | Application (Layer 7) | Main ingress | HTTPS:443, HTTP:80 |
| ALB-2 | Application (Layer 7) | ArgoCD UI | HTTPS:443 |
| ALB-3 | Application (Layer 7) | Monitoring (Grafana) | HTTPS:443 |
| ALB-4 | Application (Layer 7) | Game services | HTTPS:443, HTTP:80 |
| NLB-1 | Network (Layer 4) | Internal services | TCP:Various |

**OCI Mapping**: OCI Load Balancer
- **Flexible Load Balancer**: Layer 7 (HTTP/HTTPS) and Layer 4 (TCP/UDP)
- **Network Load Balancer**: Ultra-low latency for Layer 4
- **Shapes**:
  - 10 Mbps, 100 Mbps, 400 Mbps, 8 Gbps (Flexible)
  - Recommended: 100 Mbps Flexible shape for production

### 4.2 Service Mesh (Istio)

**Current Configuration**:
- **Istio Version**: 1.x (deployed in istio-system namespace)
- **Components**:
  - Istio Ingress Gateway (entry point)
  - istiod (control plane)
  - Envoy proxies (sidecar in each pod)
- **Features**:
  - mTLS between services
  - Traffic management (canary, blue-green)
  - Observability (distributed tracing)

**OCI Migration**:
- **Option 1**: Deploy Istio on OKE (identical to current setup)
- **Option 2**: OCI Service Mesh (managed service)
  - Native integration with OCI services
  - Managed control plane
  - Currently in preview/beta (verify availability)

### 4.3 Ingress Controllers

- **Nginx Ingress Controller**: Deployed for HTTP/HTTPS routing
- **6 Ingress Resources**: Application routing rules

**OCI Mapping**:
- Nginx Ingress Controller on OKE (same as current)
- OCI Load Balancer as external entry point

### 4.4 VPC and Networking

**Current AWS VPC**:
- **CIDR**: (Query required - not collected in previous session)
- **Subnets**: Public and private subnets across 3 AZs
- **NAT Gateways**: For private subnet internet access
- **VPC Endpoints**: For AWS services (S3, ECR, CloudWatch)

**OCI Mapping**: Virtual Cloud Network (VCN)
- **VCN CIDR**: 10.0.0.0/16 (recommended)
- **Subnets**:
  - Public subnets (3 ADs) for load balancers
  - Private subnets (3 ADs) for worker nodes
  - Private subnets (3 ADs) for databases
- **NAT Gateway**: For private subnet outbound traffic
- **Service Gateway**: For OCI services (Object Storage, Container Registry)
- **Dynamic Routing Gateway (DRG)**: For VPN/FastConnect

---

## 5. Application Workloads

### 5.1 Kubernetes Resources Summary

| Resource Type | Count | Distribution |
|--------------|-------|--------------|
| **Namespaces** | 92 | System (10) + Games (50+) + Infrastructure (32) |
| **Pods** | 161 (159 running) | 98.8% health rate |
| **Deployments** | 30 | Stateless services |
| **StatefulSets** | 70 | Game services (primary pattern) |
| **DaemonSets** | 7 | Node-level services |
| **Services** | 103 | 102 ClusterIP + 1 LoadBalancer |
| **Ingress** | 6 | HTTP/HTTPS routing |
| **HorizontalPodAutoscaler** | 82 | Auto-scaling configurations |
| **ConfigMaps** | 460 | Configuration management |
| **Secrets** | 41 | Sensitive data |

### 5.2 Largest Namespaces by Pod Count

| Namespace | Pods | Type | Purpose |
|-----------|------|------|---------|
| kube-system | 36 | System | Core Kubernetes components |
| monitoring | 13 | Infrastructure | Prometheus, Grafana, Alertmanager |
| loggzip-uploader | 9 | Infrastructure | Log shipping |
| filebeat | 9 | Infrastructure | Log collection (DaemonSet) |
| argocd | 7 | Infrastructure | GitOps deployment |
| istio-system | 5 | Infrastructure | Service mesh |
| (Game namespaces) | 1-2 each | Application | Game services (50+ namespaces) |

### 5.3 DaemonSets (Node-Level Services)

| DaemonSet | Namespace | Purpose |
|----------|-----------|---------|
| filebeat | filebeat | Log collection from all nodes |
| aws-node | kube-system | AWS VPC CNI plugin |
| ebs-csi-node | kube-system | EBS volume management |
| kube-proxy | kube-system | Network proxy |
| loggzip-uploader | loggzip-uploader | Compressed log upload |
| prometheus-node-exporter | monitoring | Node metrics collection |
| (1 more) | - | - |

**OCI Migration**: All DaemonSets can be deployed on OKE
- **aws-node** → Replace with OCI VCN-Native CNI plugin
- **ebs-csi-node** → Replace with OCI Block Volume CSI driver
- Others remain unchanged

### 5.4 Horizontal Pod Autoscalers (HPA)

- **Total HPAs**: 82 configured
- **Scaling Metric**: CPU and Memory utilization
- **Target**: Most set to 80% memory utilization
- **Example**: bingbingbingo service (98% memory usage, already scaling)

**OCI Migration**:
- HPAs work identically on OKE
- Ensure metrics-server is deployed on OKE cluster

---

## 6. Monitoring and Logging

### 6.1 Monitoring Stack

| Component | Namespace | Purpose | Storage |
|-----------|-----------|---------|---------|
| Prometheus | monitoring | Metrics collection | 50 Gi PVC |
| Thanos | monitoring | Long-term metrics storage | Object storage |
| Alertmanager | monitoring | Alert management | 10 Gi PVC |
| Grafana | monitoring | Visualization | - |
| metrics-server | kube-system | Kubernetes metrics API | - |

**OCI Mapping**:
- **Option 1**: Deploy same stack on OKE
  - Prometheus → OCI Block Volume for storage
  - Thanos → OCI Object Storage for long-term metrics
- **Option 2**: OCI Monitoring + Logging Analytics
  - Native OCI service integration
  - Hybrid: Prometheus for app metrics + OCI Monitoring for infrastructure

### 6.2 Logging Stack

| Component | Namespace | Purpose |
|-----------|-----------|---------|
| Filebeat | filebeat | Log collection from nodes |
| loggzip-uploader | loggzip-uploader | Compressed log upload to S3 |
| CloudWatch Logs | AWS | Centralized log storage |

**OCI Mapping**: OCI Logging + Logging Analytics
- **Filebeat** → FluentD or OCI Logging Agent
- **CloudWatch Logs** → OCI Logging service
- **Log storage** → OCI Object Storage (Archive tier for long-term retention)

---

## 7. CI/CD and GitOps

### 7.1 ArgoCD

- **Namespace**: argocd
- **Pods**: 7 (argocd-server, argocd-repo-server, argocd-application-controller, etc.)
- **Purpose**: Declarative GitOps continuous deployment
- **Integration**: Git repository → Kubernetes manifests → Auto-deployment

**OCI Migration**:
- Deploy ArgoCD on OKE (same configuration)
- Update Git repository with OKE cluster credentials
- Re-configure applications for OCI endpoints

### 7.2 Container Image Pipeline

- **Container Registry**: Amazon ECR (81 repositories)
- **Build**: (External CI/CD - Jenkins/GitHub Actions assumed)

**OCI Mapping**:
- **ECR** → **OCIR (OCI Container Registry)**
- **Image migration**:
  - Use `docker pull` from ECR → `docker tag` → `docker push` to OCIR
  - Or use OCI Data Transfer Service for bulk migration

---

## 8. Security and Access Control

### 8.1 Kubernetes RBAC

- **Service Accounts**: (Count not collected - typical: 50-100)
- **Roles/ClusterRoles**: (Count not collected)
- **RoleBindings/ClusterRoleBindings**: (Count not collected)

**OCI Migration**: RBAC configurations remain identical
- Export YAML from current cluster
- Apply to OKE cluster

### 8.2 AWS IAM Integration

- **IAM Roles for Service Accounts (IRSA)**: Used for AWS service access
  - S3 access
  - ECR pull permissions
  - CloudWatch Logs write permissions

**OCI Mapping**: OCI IAM + Instance Principals
- **Instance Principals**: OKE nodes use instance principals for OCI service access
- **Dynamic Groups**: Define groups for OKE worker nodes
- **Policies**: Grant permissions to dynamic groups
  - Object Storage access
  - OCIR pull permissions
  - Logging service write permissions

### 8.3 Network Security

**AWS Security Groups**: (Configuration not collected)
- Ingress rules for load balancers
- Inter-node communication
- Database access rules

**OCI Mapping**: Network Security Groups (NSGs) + Security Lists
- **NSGs**: Stateful firewall rules (like AWS Security Groups)
- **Security Lists**: Subnet-level firewall rules
- **Recommended**: Use NSGs for fine-grained control

---

## 9. OCI Service Mapping Summary

| AWS Service | Current Usage | OCI Equivalent | Migration Complexity |
|-------------|---------------|----------------|---------------------|
| **EKS** | Kubernetes 1.34 | OKE (Oracle Kubernetes Engine) | Low |
| **EC2 (c5a.xlarge)** | 9 worker nodes | VM.Standard.E5.Flex | Low |
| **RDS PostgreSQL** | 5 instances (11.82 TB) | Database Service (PostgreSQL) | Medium |
| **EBS gp3** | Node volumes + PVCs | Block Volume (High Performance) | Low |
| **S3** | ~2 TB object storage | Object Storage | Low |
| **ECR** | 81 repositories | OCIR (Container Registry) | Low |
| **ALB/NLB** | 5 load balancers | Load Balancer (Flexible) | Low |
| **VPC** | Multi-AZ networking | VCN (Virtual Cloud Network) | Medium |
| **CloudWatch Logs** | Centralized logging | OCI Logging + Logging Analytics | Medium |
| **IAM** | IRSA for service access | IAM + Instance Principals | Medium |
| **Route 53** | DNS (assumed) | DNS | Low |
| **Security Groups** | Network firewall | NSG + Security Lists | Low |

**Complexity Legend**:
- **Low**: Configuration changes only, no architecture redesign
- **Medium**: Some reconfiguration and testing required
- **High**: Significant redesign or application changes needed

---

## 10. Migration Considerations

### 10.1 Multi-AZ to Multi-AD Mapping

**AWS**: 3 Availability Zones (ap-east-1a, ap-east-1b, ap-east-1c)

**OCI**: 3 Availability Domains (AD-1, AD-2, AD-3)
- **Mapping**: Direct 1:1 mapping (AZ-a → AD-1, AZ-b → AD-2, AZ-c → AD-3)
- **Consideration**: Some OCI regions have only 1 AD (use Fault Domains within AD)

### 10.2 Networking

**AWS VPC** → **OCI VCN**:
- **CIDR Planning**: Ensure no IP overlap with existing networks
- **Subnet Design**: Maintain same public/private subnet architecture
- **Connectivity**:
  - VPN or FastConnect for hybrid connectivity during migration
  - Dual-run period for gradual cutover

### 10.3 Database Migration

**Approach 1: Dump and Restore**
- `pg_dump` from AWS RDS → Import to OCI Database Service
- **Downtime**: Several hours for 11.82 TB
- **Testing**: Critical for data integrity

**Approach 2: Continuous Replication**
- AWS DMS or Oracle GoldenGate
- **Downtime**: Minimal (only final cutover)
- **Complexity**: Higher setup and monitoring

### 10.4 Application Configuration Changes

**Required Updates**:
1. **Container Images**: Re-tag and push to OCIR
2. **Kubernetes Manifests**: Update image references to OCIR
3. **Ingress**: Update DNS entries for new OCI Load Balancer IPs
4. **Environment Variables**: Update AWS-specific endpoints:
   - S3 endpoints → OCI Object Storage endpoints
   - RDS endpoints → OCI Database endpoints
   - ECR → OCIR
5. **IAM/IRSA**: Replace with OCI Instance Principals
6. **ConfigMaps/Secrets**: Update AWS service configurations

### 10.5 Cost Optimization Opportunities

**Right-Sizing**:
- Current CPU utilization: 2-8% (can reduce node count or size)
- Current memory utilization: 28-54% (moderate, maintain current sizing)
- **Recommendation**: Consolidate 9 nodes → 6 nodes with higher OCPU/memory

**OCI Cost Advantages**:
- **Flexible Shapes**: Pay only for actual OCPU/memory used (vs. fixed instance sizes)
- **Block Volume**: No per-IOPS charges (vs. AWS gp3 IOPS pricing)
- **Egress**: Lower data transfer costs for Asia-Pacific traffic
- **Reserved Instances**: OCI Compute Reservations for 1-3 year commitments

**Estimated Monthly Costs** (OCI Hong Kong region):
- **OKE**: ~$500-700 (9 nodes × VM.Standard.E5.Flex)
- **Database**: ~$800-1,200 (5 DB instances)
- **Block Storage**: ~$1,200 (11.82 TB × $0.10/GB)
- **Object Storage**: ~$50 (2 TB × $0.025/GB)
- **Load Balancer**: ~$100-200 (5 LBs)
- **Networking**: ~$100-200 (data transfer)
- **Total**: ~$2,950-3,750/month

*(Note: Actual costs depend on usage patterns, reservations, and promotional discounts)*

### 10.6 Testing and Validation

**Pre-Migration Testing**:
1. **OKE Cluster Setup**: Deploy identical configuration in OCI
2. **Smoke Testing**: Deploy 5-10 namespaces for testing
3. **Performance Testing**: Load testing on OCI infrastructure
4. **Database Replication**: Test replication lag and data consistency
5. **Backup/Restore**: Validate backup and recovery procedures

**Cutover Plan**:
1. **Freeze AWS environment** (read-only mode)
2. **Final database sync** (15-30 minutes)
3. **Update DNS** (Route 53 → OCI DNS)
4. **Traffic cutover** (gradual or immediate)
5. **Monitor for 24-48 hours** (rollback capability)
6. **Decommission AWS** (after 1-2 weeks)

---

## 11. Migration Timeline Estimate

| Phase | Duration | Activities |
|-------|----------|------------|
| **Planning** | 2-3 weeks | Architecture design, OCI account setup, cost analysis |
| **Infrastructure Setup** | 2-3 weeks | VCN, OKE cluster, database provisioning |
| **Application Migration** | 3-4 weeks | Container images, Kubernetes manifests, testing |
| **Database Migration** | 1-2 weeks | Dump/restore or replication setup |
| **Integration Testing** | 2-3 weeks | End-to-end testing, performance validation |
| **Cutover** | 1 week | Planned downtime window, final migration |
| **Stabilization** | 2 weeks | Post-migration monitoring and optimization |
| **Total** | **13-18 weeks** | 3-4.5 months |

*(Timeline assumes parallel workstreams and no major blockers)*

---

## 12. Risks and Mitigation

| Risk | Impact | Mitigation |
|------|--------|-----------|
| **Database migration downtime** | High | Use continuous replication (GoldenGate) |
| **Application compatibility** | Medium | Thorough testing in OCI environment before cutover |
| **Network latency changes** | Medium | Performance testing and optimization |
| **Kubernetes version mismatch** | Low | Upgrade AWS EKS to latest before migration |
| **Data transfer time** | Medium | Use OCI Data Transfer Appliance for large datasets |
| **Staff training on OCI** | Medium | OCI training and certification for DevOps team |

---

## 13. Recommended Next Steps

1. **Conduct OCI Proof of Concept (PoC)**:
   - Deploy 1 game service on OKE
   - Test database connectivity and performance
   - Validate monitoring and logging

2. **Engage OCI Solutions Architect**:
   - Detailed architecture review
   - Cost optimization recommendations
   - Migration strategy refinement

3. **Prepare Detailed Migration Runbook**:
   - Step-by-step procedures
   - Rollback plans
   - Communication templates

4. **Establish OCI Environment**:
   - Production VCN and subnets
   - OKE cluster (non-prod environment first)
   - Database Service instances

5. **Application Inventory and Dependency Mapping**:
   - Document all external integrations
   - Identify AWS-specific dependencies
   - Plan configuration updates

---

## Appendix A: OCI Region Considerations

**Recommended OCI Region**: **Japan East (Tokyo)** or **South Korea Central (Seoul)**

| Region | Latency from HK | Availability Domains | Notes |
|--------|----------------|---------------------|-------|
| Japan East (Tokyo) | ~30-40ms | 1 AD (3 FDs) | Most popular for Asia-Pacific |
| South Korea Central (Seoul) | ~40-50ms | 1 AD (3 FDs) | Good for Korea/Japan users |
| Singapore | ~50-60ms | 1 AD (3 FDs) | Alternative if above not feasible |

**Note**: Hong Kong region is not yet available in OCI. Tokyo or Seoul are closest alternatives.

---

## Appendix B: Key Contacts and Resources

**OCI Documentation**:
- OKE: https://docs.oracle.com/en-us/iaas/Content/ContEng/home.htm
- Database Service: https://docs.oracle.com/en-us/iaas/Content/Database/home.htm
- Migration: https://docs.oracle.com/en-us/iaas/Content/cloud-migration/home.htm

**Migration Tools**:
- OCI Data Transfer Service: https://docs.oracle.com/en-us/iaas/Content/DataTransfer/home.htm
- Database Migration Service: https://docs.oracle.com/en-us/iaas/database-migration/home.htm

**Training**:
- OCI Foundations: https://learn.oracle.com/ols/learning-path/become-an-oci-foundations-associate/
- OKE Administration: https://learn.oracle.com/ols/learning-path/administer-container-engine-kubernetes/

---

**Document Version**: 1.0
**Last Updated**: 2026-01-02
**Prepared by**: DevOps Team
**Reviewed by**: (Pending OCI Solutions Architect review)

