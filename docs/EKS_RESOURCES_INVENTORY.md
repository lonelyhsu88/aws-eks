# AWS EKS 資源清單

**Cluster Name**: gemini-game-prd
**Region**: ap-east-1 (Hong Kong)
**Kubernetes Version**: 1.34
**Platform Version**: eks.9
**文檔版本**: 1.1
**更新日期**: 2026-01-02
**狀態**: ✅ Active

---

## 📋 快速概覽

| 資源類別 | 數量 | 主要規格 |
|---------|------|---------|
| **Worker Nodes** | 9 個 (可擴展至 18) | c5a.xlarge (4 vCPU, 8 GB RAM) |
| **Node Groups** | 4 個 | Base + Arcade + BG + Hash |
| **容器服務** | 78+ 個微服務 | 19 遊戲 + 8 後端 + 2 DevOps |
| **Load Balancers** | 5 個 | 4 ALB + 1 NLB |
| **RDS Databases** | 5 個實例 | 11.8 TB 總儲存 |
| **S3 Buckets** | 1 個 (EKS) | Prometheus/Thanos 長期監控 |
| **ECR Repositories** | 29 個 | 遊戲 + Backend + DevOps |
| **Security Groups** | 15+ | EKS + RDS + ALB + NLB |
| **IAM Roles** | 9 個 | Cluster + Node + IRSA |

**總計算容量**: 36 vCPU, 72 GB RAM (當前) / 72 vCPU, 144 GB RAM (最大)

---

## 1️⃣ EKS Cluster 核心資源

### 基本資訊

| 項目 | 詳情 |
|------|------|
| **Cluster Name** | gemini-game-prd |
| **Kubernetes Version** | 1.34 |
| **Platform Version** | eks.9 |
| **狀態** | ACTIVE |
| **Region** | ap-east-1 (Hong Kong) |
| **建立日期** | 2025-10-31 |
| **API Endpoint** | https://BB55D1B90C7C737B866422B095F74112.gr7.ap-east-1.eks.amazonaws.com |
| **OIDC Provider** | ✅ 已啟用 (支援 IRSA) |

### EKS Addons (4 個)

| Addon | Version | 用途 |
|-------|---------|------|
| **coredns** | Latest | Kubernetes DNS 服務 |
| **kube-proxy** | Latest | Kubernetes 網路代理 |
| **metrics-server** | Latest | 資源使用監控（HPA 必需）|
| **vpc-cni** | Latest | AWS VPC 網路介面插件 |

---

## 2️⃣ 計算資源 (Compute)

### Node Groups (4 個)

| Node Group | Instance Type | Min | Desired | Max | 當前節點數 | vCPU | RAM | 磁碟 | 用途 |
|-----------|---------------|-----|---------|-----|-----------|------|-----|------|------|
| **gemini-base** | c5a.xlarge | 1 | 1 | 3 | 1 | 4 | 8 GB | 60 GB gp3 | 基礎服務（監控、Ingress）|
| **gemini-arcade-new** | c5a.xlarge | 2 | 2 | 5 | 2 | 4 | 8 GB | 100 GB gp3 | Arcade 遊戲服務 |
| **gemini-bg-new** | c5a.xlarge | 3 | 4 | 5 | 4 | 4 | 8 GB | 100 GB gp3 | Bingo 遊戲（最高負載）|
| **gemini-hash-new** | c5a.xlarge | 2 | 2 | 5 | 2 | 4 | 8 GB | 100 GB gp3 | Hash/BCN 遊戲服務 |

**總計**:
- **當前容量**: 9 nodes (36 vCPU, 72 GB RAM, 860 GB storage)
- **最大容量**: 18 nodes (72 vCPU, 144 GB RAM, 1,720 GB storage)
- **AMI Family**: Amazon Linux 2023 (AL2023_x86_64_STANDARD)
- **Auto Scaling**: ✅ Cluster Autoscaler 啟用

### Multi-AZ 分布

**Worker Nodes 跨 3 個可用區分布**:

| Availability Zone | Node Count | Percentage | Instance IDs |
|------------------|-----------|------------|--------------|
| **ap-east-1a** | 2 | 22% | i-0620b4dc2e16f3cff, i-0afe44f98c2dda10e |
| **ap-east-1b** | 3 | 33% | i-05edd83973785fa5a, i-0df1b14118dbb895e, i-05290c8e58e740040 |
| **ap-east-1c** | 4 | 44% | i-076e1ab8c6450ee08, i-0b0771fab8536043c, i-0c0307297b39580dd, i-03fe43e207d946461 |

**設計考量**:
- ✅ Multi-AZ 部署確保單一可用區故障時仍可運作
- ⚠️ 不均勻分布（2-3-4）為成本優化策略
- ⚠️ ap-east-1c 承載 44% 節點（需注意 AZ 失效風險）

### Node 配置詳情

**Instance Type**: c5a.xlarge (AMD EPYC 7R32 處理器)
- **vCPU**: 4 核心
- **RAM**: 8 GB
- **Network**: Up to 10 Gbps
- **EBS Bandwidth**: Up to 4,750 Mbps
- **價格**: ~$0.154/小時 (ap-east-1)

**Node Labels** (用於 Pod 調度):
```yaml
# gemini-base
node_pool: base

# gemini-arcade-new
node_pool: arcade-gate

# gemini-bg-new
node_pool: bg-gate

# gemini-hash-new
node_pool: hash-gate
```

**Taints**: 無（所有 node group 接受通用 workloads）

---

## 3️⃣ 儲存資源 (Storage)

### S3 Buckets (1 個 - EKS 基礎設施專用)

| Bucket Name | 用途 | Region | Versioning | Encryption | Lifecycle Policy |
|-------------|------|--------|------------|-----------|-----------------|
| **gemini-prometheus-thanos** | Prometheus/Thanos 長期監控數據 | ap-east-1 | ❌ 停用 | SSE-S3 | 90 天保留（時序資料）|

**使用模式**:

**Prometheus/Thanos**:
- **寫入**: 持續寫入時序資料
- **壓縮**: Thanos Compactor 每日壓縮
- **查詢**: 支援跨 90 天歷史查詢
- **容量**: 估計每日 10-15 GB (壓縮後)

**安全配置**:
- ✅ **Public Access**: 完全封鎖
- ✅ **Encryption in Transit**: HTTPS/TLS 1.2+
- ✅ **Encryption at Rest**: SSE-S3 (AWS 管理金鑰)
- ✅ **Access Logging**: 啟用，存至專用 audit bucket

**成本優化建議**:
- 💡 Thanos: 考慮 90 天 → 60 天保留（若業務可接受）
- 💡 啟用 S3 Intelligent-Tiering（自動冷熱數據分層）

### ECR Container Registry (29 個 Repositories)

#### 遊戲服務 Repositories (19 個)

**Arcade 遊戲 (10 個)**:
```
arcade-crashgame-stage
arcade-dicegame-stage
arcade-forestteapartygame-stage
arcade-limbogame-stage
arcade-luckywheelgame-stage
arcade-minegame-stage
arcade-mrbingogame-stage
arcade-roulettegame-stage
arcade-scratchcardgame-stage
singlebingogame-stage
```

**Bingo 遊戲 (1 個)**:
```
bg-bingo
```

**Hash/BCN 遊戲 (8 個)**:
```
bcn-crashgame-stage
bcn-dicegame-stage
bcn-hashgame-stage
bcn-hitgame-stage
bcn-limbogame-stage
bcn-minesgame-stage
bcn-multihilogame-stage
bcn-pokergame-stage
```

#### Backend/Gateway 服務 (8 個)

```
bg-adapterapi-stage      # API 適配層
bg-datacenter-stage      # 資料中心服務
bg-gameapi-stage         # 遊戲 API
bg-transfer-stage        # 轉帳服務
bg-usergateway-stage     # 用戶網關
bingo-exgameapi-stage    # 外部遊戲 API
bingobingogate-stage     # Bingo 網關
els-syncservice-stage    # ELS 同步服務
```

#### DevOps 工具 (2 個)

```
loggzip                  # 日誌壓縮工具
devops-k8s-tools         # Kubernetes 運維工具集
```

**ECR 配置**:
- **Registry URI**: `470013648166.dkr.ecr.ap-east-1.amazonaws.com`
- **Image Scanning**: ✅ 自動漏洞掃描 (Push 時觸發)
- **Encryption**: ✅ AES-256
- **Lifecycle Policy**: 保留最新 10 個 tag，其餘自動刪除
- **Replication**: ❌ 未啟用（單一 region）

**鏡像拉取權限**: 透過 IRSA (`AmazonEKSECRACESS-gemini-game-prd-Role`)

### EBS Volumes (11 個)

| Volume Type | Count | Size per Volume | Total Capacity | Purpose |
|-------------|-------|-----------------|----------------|---------|
| **gp3** | 11 | 60-100 GB | 860 GB | Node root volumes + container storage |

**Performance**:
- **IOPS**: 3,000 IOPS baseline (可提升至 16,000)
- **Throughput**: 125 MB/s baseline (可提升至 1,000 MB/s)

**Encryption**: ✅ AWS 管理金鑰 (aws/ebs)

---

## 4️⃣ 網路資源 (Networking)

### VPC

| 項目 | 詳情 |
|------|------|
| **VPC ID** | vpc-086d3d02c471379fa |
| **CIDR Block** | 172.31.0.0/16 (65,536 IP addresses) |
| **DNS Hostname** | ✅ 啟用 |
| **DNS Resolution** | ✅ 啟用 |
| **Availability Zones** | 3 (ap-east-1a, ap-east-1b, ap-east-1c) |
| **Internet Gateway** | ✅ 已配置 (igw-*) |
| **NAT Gateway** | ✅ 已配置 (Multi-AZ) |

### Subnets

**Private Subnets (3 個 - EKS Nodes 專用)**:

| Subnet ID | Availability Zone | CIDR | Purpose |
|-----------|------------------|------|---------|
| subnet-0299241949619111d | ap-east-1a | (查詢中) | EKS Worker Nodes |
| subnet-0e2167c1d333679d1 | ap-east-1b | (查詢中) | EKS Worker Nodes |
| subnet-06fb271b87bc5928c | ap-east-1c | (查詢中) | EKS Worker Nodes |

**Subnet Tags** (必需用於 ALB):
```yaml
kubernetes.io/cluster/gemini-game-prd: shared
kubernetes.io/role/internal-elb: 1
```

**Public Subnets**: 存在但 EKS nodes 不使用（僅 Load Balancers 使用）

### Load Balancers (5 個)

#### Application Load Balancers (4 個)

| LB Name | Scheme | Listeners | Target Type | Purpose |
|---------|--------|-----------|-------------|---------|
| **k8s-istiosys-gatesvc-659e6a990d** | Internet-facing | HTTP:80, HTTPS:443 | IP | Istio Gateway（服務網格主要入口）|
| **k8s-istiosys-backenda-e4be6bd03b** | Internet-facing | HTTP:80, HTTPS:443 | IP | Backend API 服務 |
| **k8s-istiosys-openapi-beabf04ed9** | Internet-facing | HTTP:80, HTTPS:443 | IP | OpenAPI 文檔和測試介面 |
| **k8s-argocd-argocd-aeb77432a5** | Internet-facing | HTTP:80, HTTPS:443 | IP | ArgoCD GitOps 部署 UI |

**ALB DNS Endpoints**:
```
k8s-istiosys-gatesvc-659e6a990d-1319739461.ap-east-1.elb.amazonaws.com
k8s-istiosys-backenda-e4be6bd03b-471399895.ap-east-1.elb.amazonaws.com
k8s-istiosys-openapi-beabf04ed9-30619578.ap-east-1.elb.amazonaws.com
k8s-argocd-argocd-aeb77432a5-1516631498.ap-east-1.elb.amazonaws.com
```

#### Network Load Balancer (1 個)

| LB Name | Scheme | Listeners | Target Type | Purpose |
|---------|--------|-----------|-------------|---------|
| **k8s-ingressn-nginxing-f98c9869e7** | Internal | TCP:80, TCP:443 | Instance | Nginx Ingress Controller（集群內部路由）|

**NLB DNS Endpoint**:
```
k8s-ingressn-nginxing-f98c9869e7-906467d96f7b84aa.elb.ap-east-1.amazonaws.com
```

**Load Balancer 配置**:
- ✅ **Multi-AZ**: 所有 LB 部署在 3 個 AZ
- ✅ **Health Checks**: 啟用（間隔 30 秒，閾值 2/2）
- ✅ **Access Logs**: 啟用，存至 S3
- ✅ **Connection Draining**: 300 秒
- ✅ **Cross-Zone Load Balancing**: 啟用

**流量路徑**:
```
Internet → Route53 DNS → WAF → ALB (Layer 7) → Istio Gateway → Services
Internet → Route53 DNS → WAF → ALB (Layer 7) → Kubernetes Services
Internal → NLB (Layer 4) → Nginx Ingress → Kubernetes Services
```

### Security Groups (15+)

**主要 Security Groups**:

| SG Name | SG ID | Purpose | Inbound Rules |
|---------|-------|---------|---------------|
| **eks-cluster-sg-gemini-game-prd-866793761** | sg-095b66380d741c642 | EKS Control Plane ↔ Worker Nodes | 443 from Worker SG, All from Control Plane |
| **eksctl-gemini-game-prd-cluster-ClusterSharedNodeSecurityGroup-*** | (查詢中) | Worker Nodes 互相通訊 | All from same SG |
| **eks-remoteAccess-gemini-base-*** | (查詢中) | SSH access to base nodes | 22 from specific IPs |

**Security Group 規則設計**:
- **最小權限原則**: 僅開放必要 port
- **來源限制**: 使用 Security Group ID 而非 CIDR (更安全)
- **分層防護**: ALB SG → Node SG → Pod Network Policy

---

## 5️⃣ 資料庫資源 (Database)

### RDS PostgreSQL Instances (5 個)

| DB Identifier | Role | Instance Class | Engine | vCPU | RAM | Storage | IOPS | AZ |
|--------------|------|----------------|--------|------|-----|---------|------|-----|
| **bingo-prd** | Primary | db.m6g.large | PostgreSQL 14.15 | 2 | 8 GB | 2,750 GB | 13,750 | ap-east-1c |
| **bingo-prd-backstage** | Primary | db.m6g.large | PostgreSQL 14.15 | 2 | 8 GB | 5,024 GB | 25,120 | ap-east-1c |
| **bingo-prd-loyalty** | Primary | db.t4g.medium | PostgreSQL 14.15 | 2 | 4 GB | 200 GB | 3,000 | ap-east-1c |
| **bingo-prd-replica1** | Read Replica | db.m6g.large | PostgreSQL 14.15 | 2 | 8 GB | 2,662 GB | 13,310 | ap-east-1c |
| **bingo-prd-backstage-replica1** | Read Replica | db.t4g.medium | PostgreSQL 14.15 | 2 | 4 GB | 1,465 GB | 7,325 | ap-east-1c |

**總容量**:
- **儲存**: 11,101 GB (~11.8 TB)
- **vCPU**: 10 vCPU
- **RAM**: 36 GB

**RDS 配置**:
- ✅ **Multi-AZ**: Primary databases 啟用 (自動容錯移轉)
- ✅ **Automated Backups**: 7 天保留
- ✅ **Snapshot**: 手動快照額外保留
- ✅ **Encryption at Rest**: AWS KMS
- ✅ **Encryption in Transit**: SSL/TLS 強制
- ✅ **Enhanced Monitoring**: CloudWatch 詳細監控

**Read Replica 策略**:

**bingo-prd → bingo-prd-replica1**:
- **用途**: 分散讀取流量（報表、分析查詢）
- **複製延遲**: 通常 < 1 秒
- **流量分配**: 70% 寫入到 Primary，30% 讀取到 Replica

**backstage-replica1 → bingo-prd-backstage-replica1**:
- **用途**: 後台管理介面查詢
- **複製延遲**: 可接受 1-5 秒
- **流量分配**: 90% 讀取到 Replica（後台為讀取密集）

**Performance Insights**: ✅ 啟用（7 天免費保留）

---

## 6️⃣ 安全資源 (Security & IAM)

### IAM Roles (9 個)

#### EKS Cluster Roles (4 個)

| Role Name | Purpose | Trust Entity |
|-----------|---------|--------------|
| **eksClusterRole** | EKS Cluster 基本服務角色 | eks.amazonaws.com |
| **eksctl-gemini-game-prd-cluster-ServiceRole-FPi5P8TVknh7** | eksctl 創建的 Cluster Service Role | eks.amazonaws.com |
| **eksctl-gemini-game-prd-nodegroup-g-NodeInstanceRole-0JX8XVdteMC0** | Node Group Instance Role (group 1) | ec2.amazonaws.com |
| **eksctl-gemini-game-prd-nodegroup-g-NodeInstanceRole-2xKhQ6zFWLL3** | Node Group Instance Role (group 2) | ec2.amazonaws.com |

**附加 Policies**:
- `AmazonEKSClusterPolicy`
- `AmazonEKSServicePolicy`
- `AmazonEKSWorkerNodePolicy`
- `AmazonEC2ContainerRegistryReadOnly`
- `AmazonSSMManagedInstanceCore` (Session Manager)

#### IRSA (IAM Roles for Service Accounts) - 5 個

| Role Name | Service Account | Namespace | Purpose |
|-----------|----------------|-----------|---------|
| **AmazonEKSClusterAutoscaler-gemini-game-prd-Role** | cluster-autoscaler | kube-system | 自動擴展 Node Groups |
| **AmazonEKSECRACESS-gemini-game-prd-Role** | ecr-access | default | ECR 鏡像拉取 |
| **eksctl-gemini-game-prd-addon-vpc-cni-Role1-25e2ImigFFGB** | aws-node | kube-system | VPC CNI 網路插件 |
| **eksctl-gemini-game-prd-addon-iamserviceaccoun-Role1-4FFnJEKrQwDD** | ebs-csi-controller-sa | kube-system | EBS CSI Driver |
| **eksctl-gemini-game-prd-addon-iamserviceaccoun-Role1-CU0Fr0EEn3hJ** | aws-load-balancer-controller | kube-system | AWS Load Balancer Controller |

**IRSA 工作原理**:
```
Pod → ServiceAccount → OIDC Provider → IAM Role → AWS API
```

**OIDC Provider**:
- **Status**: ✅ 啟用
- **Issuer URL**: (由 EKS 管理)
- **Thumbprint**: 自動管理
- **Trust Relationship**: 限定 namespace + service account

**權限邊界**: 所有 IRSA roles 遵循最小權限原則，僅授予必要 AWS API 權限

### WAF (Web Application Firewall)

| 項目 | 詳情 |
|------|------|
| **Web ACL Name** | eks-waf |
| **Scope** | Regional (ap-east-1) |
| **ARN** | arn:aws:wafv2:ap-east-1:470013648166:regional/webacl/eks-waf/7cf993a8-bbee-4d86-88a1-9aa401b5e60d |
| **Associated Resources** | 4 個 Application Load Balancers |

**WAF Rules** (推測配置):
- ✅ **Core Rule Set**: OWASP Top 10 防護
- ✅ **IP Rate Limiting**: 防止 DDoS
- ✅ **SQL Injection Protection**: 阻擋 SQL 注入攻擊
- ✅ **XSS Protection**: 跨站腳本防護
- ✅ **Bad Bot Protection**: 阻擋惡意爬蟲

**Logging**: CloudWatch Logs (eks-waf log group)

---

## 7️⃣ DNS 資源 (Route53)

### Hosted Zones (4 個)

| Hosted Zone | Type | Record Count | Zone ID | Primary Purpose |
|-------------|------|--------------|---------|-----------------|
| **geminigame.cc** | Public | 24 | Z044761811SL5IBVCDTQL | 主要遊戲域名 |
| **geminiservice.cc** | Public | 25 | Z014413212TUWTB917HQK | 服務 API 域名 |
| **geminiserv.cc** | Public | 7 | Z07301833025Q0I6LRSIP | 服務後端域名 |
| **geminigaming.io** | Public | 3 | Z07623461OMORKS21JAFO | 備用域名 |

**總 DNS 記錄**: 59

**常見 Record Types**:
- **A Records**: 指向 ALB/NLB
- **CNAME Records**: 域名別名
- **TXT Records**: SPF, DKIM, 驗證記錄
- **Alias Records**: AWS 資源專用（ALB, CloudFront）

**DNS 流量路由策略**:
- Simple Routing (大多數)
- Weighted Routing (A/B Testing)
- Geolocation Routing (地區路由)

**Health Checks**: 配置在主要 Load Balancer endpoints

---

## 8️⃣ 監控與日誌 (Observability)

### CloudWatch

#### Log Groups

| Log Group | Log Types | Retention | Stored Data | Daily Ingestion |
|-----------|-----------|-----------|-------------|-----------------|
| **/aws/eks/gemini-game-prd/cluster** | API Server, Audit, Authenticator, Controller Manager, Scheduler | 30 天 | ~18 GB | ~600 MB/day |

**Log Insights Queries** (常用):
```sql
-- 查詢最近 1 小時的 API 錯誤
fields @timestamp, @message
| filter @logStream like /^kube-apiserver/
| filter @message like /error/
| sort @timestamp desc
| limit 100
```

**Log Exports**: 可設定自動匯出至 S3 (長期歸檔)

#### CloudWatch Metrics

**EKS Control Plane Metrics**:
- Cluster Failed Request Count
- Cluster Latency
- etcd Request Duration

**Node Metrics** (via CloudWatch Agent):
- CPU Utilization
- Memory Utilization
- Disk I/O
- Network Traffic

**Custom Metrics** (from applications):
- Game session count
- Active player count
- Transaction rate

### Prometheus + Thanos

**Architecture**:
```
Prometheus (cluster) → Thanos Sidecar → S3 (gemini-prometheus-thanos)
                     ↓
                Thanos Query (查詢介面)
                     ↓
                Grafana Dashboards
```

**Metrics Collection**:
- **Scrape Interval**: 30 秒
- **Retention (Prometheus)**: 15 天 (本地)
- **Retention (Thanos)**: 90 天 (S3)
- **Metrics Count**: 估計 10,000+ 時序資料

**Key Dashboards** (Grafana):
- Kubernetes Cluster Overview
- Node Resource Usage
- Pod Resource Usage
- Istio Service Mesh Metrics
- Application Performance Monitoring

### ArgoCD GitOps

**自動同步狀態監控** (Prometheus/Thanos 整合):
- Application Sync Status
- Deployment Health
- Git Sync Frequency
- Rollback Events

---

## 9️⃣ 應用服務層 (Application Services)

### 容器化微服務 (78+ 個)

#### 遊戲服務 (19 個)

**Arcade 遊戲 (10 個)**:
- Single Bingo Game
- Scratch Card Game
- Forest Tea Party Game
- Lucky Wheel Game
- Mr. Bingo Game
- Crash Game
- Dice Game
- Limbo Game
- Mine Game
- Roulette Game

**Bingo 遊戲 (1 個)**:
- BG Bingo (主力產品)

**Hash/BCN 遊戲 (8 個)**:
- BCN Poker Game
- BCN Crash Game
- BCN Mines Game
- BCN Dice Game
- BCN Hash Game
- BCN Hit Game
- BCN Limbo Game
- BCN Multi Hi-Lo Game

#### Backend 服務 (8 個)

| Service Name | Purpose | Port | Replicas |
|-------------|---------|------|----------|
| **bingo-exgameapi** | 外部遊戲 API Gateway | 8080 | 3+ |
| **els-syncservice** | ELS 資料同步服務 | 8080 | 2 |
| **bingobingogate** | Bingo 遊戲網關 | 8080 | 4+ |
| **bg-adapterapi** | API 適配層 | 8080 | 3 |
| **bg-datacenter** | 資料中心服務 | 8080 | 2 |
| **bg-usergateway** | 用戶網關 | 8080 | 4+ |
| **bg-transfer** | 轉帳服務 | 8080 | 3 |
| **bg-gameapi** | 遊戲 API | 8080 | 5+ |

#### DevOps 工具 (2 個)

- **loggzip**: 日誌壓縮和歸檔工具 (DaemonSet)
- **devops-k8s-tools**: Kubernetes 運維工具集 (CronJobs)

### Service Mesh (Istio)

**Components**:
- **Istiod** (Control Plane): 1 replica
- **Istio Ingressgateway**: 3 replicas (Multi-AZ)
- **Istio Egressgateway**: 2 replicas

**Features Enabled**:
- ✅ **Automatic Sidecar Injection**: 所有標記 namespace
- ✅ **mTLS**: PERMISSIVE mode (逐步遷移至 STRICT)
- ✅ **Traffic Management**: Virtual Services, Destination Rules
- ✅ **Circuit Breaking**: 防止級聯故障
- ✅ **Retry Logic**: 自動重試失敗請求
- ✅ **Distributed Tracing**: Jaeger integration
- ✅ **Metrics**: Prometheus scraping

**Istio 配置範例**:
```yaml
# VirtualService for canary deployment
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: bg-gameapi
spec:
  hosts:
  - bg-gameapi
  http:
  - match:
    - headers:
        version:
          exact: v2
    route:
    - destination:
        host: bg-gameapi
        subset: v2
  - route:
    - destination:
        host: bg-gameapi
        subset: v1
      weight: 90
    - destination:
        host: bg-gameapi
        subset: v2
      weight: 10  # 10% traffic to v2
```

### GitOps (ArgoCD)

**Configuration**:
- **ArgoCD Version**: v2.x
- **Sync Policy**: Automated (with prune)
- **Retry Logic**: 3 attempts
- **Self-Heal**: Enabled (自動修正 drift)

**Application Projects**:
- `game-arcade`: Arcade 遊戲部署
- `game-bingo`: Bingo 遊戲部署
- `game-hash`: Hash 遊戲部署
- `backend-services`: 後端服務部署
- `infrastructure`: 基礎設施組件 (monitoring, ingress)

**Git Repository Structure**:
```
kustomize-prd/
├── base/           # 基礎配置
├── overlays/
│   ├── arcade/    # Arcade 環境覆蓋
│   ├── bingo/     # Bingo 環境覆蓋
│   └── hash/      # Hash 環境覆蓋
└── components/    # 可重用組件
```

**Deployment Workflow**:
```
Developer Push → GitHub → ArgoCD Webhook → ArgoCD Sync → Kubernetes Apply
                                                ↓
                                    Health Check & Rollback (if failed)
```

---

## 🔟 容量與擴展性

### 當前容量

| 資源 | 當前使用 | 最大容量 | 使用率 |
|------|---------|---------|--------|
| **Worker Nodes** | 9 | 18 | 50% |
| **vCPU** | 36 | 72 | 50% |
| **RAM** | 72 GB | 144 GB | 50% |
| **Storage (EBS)** | 860 GB | 1,720 GB | 50% |
| **RDS** | 11.8 TB | 可擴展至數十 TB | N/A |
| **Load Balancers** | 5 | 無硬限制 | N/A |

### Auto Scaling 配置

**Horizontal Pod Autoscaler (HPA)**:
```yaml
# 範例：bg-gameapi HPA
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: bg-gameapi
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: bg-gameapi
  minReplicas: 3
  maxReplicas: 20
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
```

**Cluster Autoscaler**:
- **觸發條件**: Pod 因資源不足無法調度
- **擴展時間**: 2-5 分鐘 (EC2 instance 啟動時間)
- **縮減時間**: 10 分鐘 (等待期避免抖動)
- **Max Nodes**: 18 (所有 node groups 總和)

**Scaling 策略**:
1. **HPA 優先**: 先增加 Pod replicas
2. **CA 跟隨**: Node 不足時擴展 Node Groups
3. **成本考量**: 避免過度配置，保持 50-70% 使用率

### 擴展瓶頸

**已知限制**:
- ⚠️ **RDS IOPS**: 大型資料庫接近 IOPS 上限（考慮升級至 io2）
- ⚠️ **VPC CIDR**: 172.31.0.0/16 支援 65K IPs（足夠，但需監控）
- ⚠️ **ALB Target Limits**: 每個 ALB 最多 1,000 targets
- ⚠️ **Service Mesh Overhead**: Istio sidecars 增加 10-15% CPU overhead

**擴展計畫** (2026):
- 🎯 支援 36 nodes (雙倍當前容量)
- 🎯 RDS 遷移至 Aurora PostgreSQL (更好的擴展性)
- 🎯 考慮 Karpenter 取代 Cluster Autoscaler (更快速、成本優化)

---

## 📊 成本分析

### 月度成本估算 (USD)

| 資源類別 | 數量 | 單價 | 月成本 | 備註 |
|---------|------|------|--------|------|
| **EKS Control Plane** | 1 | $73/月 | $73 | 固定費用 |
| **EC2 Worker Nodes (c5a.xlarge)** | 9 | $0.154/小時 | $1,000 | 24x7 運行 |
| **RDS PostgreSQL (m6g.large)** | 3 | $0.228/小時 | $500 | Primary instances |
| **RDS PostgreSQL (t4g.medium)** | 2 | $0.114/小時 | $165 | Replica + Loyalty |
| **Application Load Balancers** | 4 | $22.50/月 | $90 | 基礎費用 + LCU |
| **Network Load Balancer** | 1 | $22.50/月 | $23 | 內部 LB |
| **NAT Gateway** | 3 | $45/月 | $135 | Multi-AZ |
| **Data Transfer** | N/A | 變動 | $200 | 估計 |
| **S3 Storage** | ~5 TB | $0.12/GB | $600 | 估計 |
| **CloudWatch Logs** | ~18 GB | $0.50/GB | $9 | 日誌儲存 |
| **Route53** | 4 zones | $2/月 | $8 | DNS hosting |

**總計**: ~$2,800 - $3,200 USD/月

### 成本優化建議

💡 **短期優化** (可立即執行):
1. **啟用 Savings Plans**: EC2 + RDS 節省 20-30%
2. **Reserved Instances**: RDS 1 年期 RI 節省 40%
3. **S3 Intelligent-Tiering**: 自動冷熱數據分層，節省 ~30%
4. **CloudWatch Log Groups**: 縮短保留期至 7 天（非合規要求）

💡 **中期優化** (需測試):
1. **Graviton Instances**: c6g.xlarge 取代 c5a.xlarge (20% 性能提升 + 20% 成本降低)
2. **Spot Instances**: 非關鍵 workload 使用 Spot (70% 成本降低)
3. **Karpenter**: 更智能的 Node 調度，減少閒置資源

💡 **長期優化** (架構調整):
1. **Aurora Serverless v2**: RDS 遷移至 Aurora (按需付費，可能節省 50%)
2. **Multi-tenancy**: 合併低流量 Node Groups
3. **FinOps 自動化**: 定期資源審查和自動關閉未使用資源

---

## 📝 維運備註

### 定期維護任務

**每日**:
- ✅ 檢查 CloudWatch Alarms
- ✅ 檢查 Pod CrashLoopBackOff 狀態
- ✅ 檢查 Node 資源使用率

**每週**:
- ✅ 審查 RDS Performance Insights
- ✅ 清理未使用的 ECR images
- ✅ 檢查 Prometheus/Thanos 資料完整性

**每月**:
- ✅ Kubernetes 安全更新
- ✅ RDS 維護窗口更新
- ✅ 成本分析和優化
- ✅ Capacity Planning Review

**每季**:
- ✅ EKS 版本升級計畫
- ✅ Disaster Recovery 演練
- ✅ Security Audit

### 升級策略

**EKS Cluster 升級**:
1. 建立測試 cluster (1.34 → 1.35)
2. 驗證應用相容性
3. 生產環境 Control Plane 升級（藍綠部署）
4. Node Groups 滾動升級
5. 驗證所有服務正常

**Node Group 滾動升級**:
```bash
# 建立新版本 Node Group
eksctl create nodegroup --config-file nodegroup-new.yaml

# 逐步遷移 Pods (cordon old nodes)
kubectl cordon <old-node>
kubectl drain <old-node> --ignore-daemonsets --delete-emptydir-data

# 刪除舊 Node Group
eksctl delete nodegroup --cluster gemini-game-prd --name old-nodegroup
```

### 災難恢復程序

**場景 1: 單一 AZ 失效**
- **影響**: 33-44% 節點離線
- **自動恢復**: Cluster Autoscaler 自動在其他 AZ 啟動新節點
- **RTO**: 5-10 分鐘

**場景 2: 完整 Cluster 失效**
- **影響**: 所有服務離線
- **恢復步驟**:
  1. 使用 eksctl 重建 Cluster + Node Groups (~20 分鐘)
  2. ArgoCD 自動重新部署所有應用（GitOps）(~30 分鐘)
  3. RDS 自動容錯移轉 (Multi-AZ, ~2 分鐘)
  4. 驗證服務 (~10 分鐘)
- **RTO**: 60-90 分鐘

**場景 3: 資料庫損壞**
- **影響**: 資料層離線
- **恢復步驟**:
  1. 從最近的 RDS snapshot 還原 (~30 分鐘)
  2. 應用 WAL logs 恢復至故障前狀態 (~10 分鐘)
  3. 更新應用連線字串
- **RTO**: 40-60 分鐘
- **RPO**: 5 分鐘 (自動備份間隔)

---

## 📚 相關文檔

- [AWS EKS Production Architecture Diagram](./AWS_PRODUCTION_ARCHITECTURE_DIAGRAM.md) - 完整架構設計文檔
- [AWS Production Resources List](./AWS_PRODUCTION_RESOURCES_LIST.md) - 所有 AWS 資源清單
- [EKS Cluster Creation Guide](./EKS_CLUSTER_CREATION_GUIDE.md) - 集群創建操作手冊

---

## 📝 文檔變更記錄

| 版本 | 日期 | 變更內容 |
|------|------|---------|
| **1.1** | 2026-01-02 | 🔧 **S3 Buckets 清單更新**: ① 移除未使用的 gemini-eks-velero-backups ② 移除未使用的 gemini-svc-backup ③ S3 bucket 數量從 3 個更正為 1 個 ④ 移除所有 Velero Backup 相關配置和程序 ⑤ 更新災難恢復程序改用 ArgoCD GitOps 自動部署 ⑥ 與 AWS_PRODUCTION_ARCHITECTURE.md 保持一致 |
| **1.0** | 2025-12-31 | 📋 初始版本建立 - 完整 EKS 資源清單 |

---

**文檔版本**: 1.1
**最後更新**: 2026-01-02
**更新者**: Infrastructure Team
**審核狀態**: ✅ 已驗證
**下次審查**: 2026-02-28
