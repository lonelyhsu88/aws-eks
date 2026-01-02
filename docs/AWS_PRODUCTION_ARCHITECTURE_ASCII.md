# AWS Production 架構圖 (ASCII 版本)

**AWS Account**: 470013648166
**Region**: ap-east-1 (Hong Kong)
**環境**: Production
**更新日期**: 2026-01-02

---

## 📐 簡化架構圖

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                          🌐 Internet / Users                                     │
│                                    ↓                                             │
│                      🌍 Route53 DNS (4 Zones, 59 Records)                       │
│                         • geminigame.cc (24)                                     │
│                         • geminiservice.cc (25)                                  │
│                         • geminiserv.cc (7)                                      │
│                         • geminigaming.io (3)                                    │
└─────────────────────────────────────────────────────────────────────────────────┘
                                     ↓
┌─────────────────────────────────────────────────────────────────────────────────┐
│                       🔐 Security Layer - WAF & IAM                              │
│                                                                                  │
│  🛡️  WAF: eks-waf (Regional)          🔑 IAM Roles: 9                          │
│  • Protect ALBs                        • EKS Cluster Roles (4)                  │
│  • Security filtering                  • IRSA (5)                               │
│                                                                                  │
│  🚧 Security Groups: 15+                                                        │
│  • EKS Control Plane & Nodes                                                    │
│  • RDS Databases                                                                │
│  • Load Balancers                                                               │
└─────────────────────────────────────────────────────────────────────────────────┘
                                     ↓
┌─────────────────────────────────────────────────────────────────────────────────┐
│            ☁️ AWS Region: ap-east-1 (Hong Kong)                                 │
│                                                                                  │
│  ┌────────────────────────────────────────────────────────────────────────┐    │
│  │  🏢 VPC: vpc-086d3d02c471379fa (172.31.0.0/16)                         │    │
│  │                                                                          │    │
│  │  🌐 Internet Gateway ──┐                                                │    │
│  │  🔀 NAT Gateway ────────┤                                               │    │
│  │                         ↓                                                │    │
│  │  ┌──────────────────────────────────────────────────────────────┐      │    │
│  │  │           ⚖️  Load Balancers (Public Subnet)                 │      │    │
│  │  │                                                               │      │    │
│  │  │  ┌─────────────────────────────────────────────────────┐    │      │    │
│  │  │  │  Application Load Balancers (4)                     │    │      │    │
│  │  │  │  ┌─────────────────────────────────────────────┐   │    │      │    │
│  │  │  │  │  • Istio Gateway (k8s-istiosys-gatesvc)    │   │    │      │    │
│  │  │  │  │  • Backend API (k8s-istiosys-backenda)     │   │    │      │    │
│  │  │  │  │  • OpenAPI (k8s-istiosys-openapi)          │   │    │      │    │
│  │  │  │  │  • ArgoCD (k8s-argocd-argocd)              │   │    │      │    │
│  │  │  │  └─────────────────────────────────────────────┘   │    │      │    │
│  │  │  └─────────────────────────────────────────────────────┘    │      │    │
│  │  │                                                               │      │    │
│  │  │  Network Load Balancer (1) - Internal                        │      │    │
│  │  │  • Nginx Ingress Controller (k8s-ingressn-nginxing)          │      │    │
│  │  └──────────────────────────────────────────────────────────────┘      │    │
│  │                         ↓                                                │    │
│  │  ┌──────────────────────────────────────────────────────────────┐      │    │
│  │  │  ☸️  EKS Cluster: gemini-game-prd (K8s 1.34, eks.9)          │      │    │
│  │  │                                                               │      │    │
│  │  │  🎛️  EKS Control Plane (Managed by AWS)                      │      │    │
│  │  │                                                               │      │    │
│  │  │  ┌──────────────────────────────────────────────────────┐   │      │    │
│  │  │  │  📊 Node Groups (9 Nodes / 36 vCPU / 72 GB RAM)     │   │      │    │
│  │  │  │                                                       │   │      │    │
│  │  │  │  ┌─────────────────────────────────────────────┐    │   │      │    │
│  │  │  │  │  ap-east-1a (2 nodes)                       │    │   │      │    │
│  │  │  │  │  • gemini-base (1): 基礎服務                │    │   │      │    │
│  │  │  │  │  • gemini-arcade-new (1): Arcade 遊戲       │    │   │      │    │
│  │  │  │  └─────────────────────────────────────────────┘    │   │      │    │
│  │  │  │                                                       │   │      │    │
│  │  │  │  ┌─────────────────────────────────────────────┐    │   │      │    │
│  │  │  │  │  ap-east-1b (3 nodes)                       │    │   │      │    │
│  │  │  │  │  • gemini-arcade-new (1): Arcade 遊戲       │    │   │      │    │
│  │  │  │  │  • gemini-bg-new (2): BG 遊戲               │    │   │      │    │
│  │  │  │  └─────────────────────────────────────────────┘    │   │      │    │
│  │  │  │                                                       │   │      │    │
│  │  │  │  ┌─────────────────────────────────────────────┐    │   │      │    │
│  │  │  │  │  ap-east-1c (4 nodes)                       │    │   │      │    │
│  │  │  │  │  • gemini-bg-new (2): BG 遊戲               │    │   │      │    │
│  │  │  │  │  • gemini-hash-new (2): Hash 遊戲           │    │   │      │    │
│  │  │  │  └─────────────────────────────────────────────┘    │   │      │    │
│  │  │  └──────────────────────────────────────────────────────┘   │      │    │
│  │  │                         ↓                                     │      │    │
│  │  │  ┌──────────────────────────────────────────────────────┐   │      │    │
│  │  │  │  🎮 Applications (78+ Services)                      │   │      │    │
│  │  │  │                                                       │   │      │    │
│  │  │  │  🎰 Arcade Games (10)                                │   │      │    │
│  │  │  │    • singlebingogame, scratchcard, forestteaparty   │   │      │    │
│  │  │  │    • luckywheel, mrbingo, crash, dice, limbo        │   │      │    │
│  │  │  │    • mine, roulette                                  │   │      │    │
│  │  │  │                                                       │   │      │    │
│  │  │  │  🎲 Bingo Games (1)                                  │   │      │    │
│  │  │  │    • bg-bingo                                        │   │      │    │
│  │  │  │                                                       │   │      │    │
│  │  │  │  🎯 Hash/BCN Games (8)                               │   │      │    │
│  │  │  │    • poker, crash, mines, dice                       │   │      │    │
│  │  │  │    • hash, hit, limbo, multihilo                     │   │      │    │
│  │  │  │                                                       │   │      │    │
│  │  │  │  ⚙️  Backend Services (8)                            │   │      │    │
│  │  │  │    • exgameapi, syncservice, bingogate              │   │      │    │
│  │  │  │    • adapterapi, datacenter, usergateway            │   │      │    │
│  │  │  │    • transfer, gameapi                               │   │      │    │
│  │  │  │                                                       │   │      │    │
│  │  │  │  🛠️  DevOps Tools (2)                                │   │      │    │
│  │  │  │    • loggzip, k8s-tools                              │   │      │    │
│  │  │  └──────────────────────────────────────────────────────┘   │      │    │
│  │  │                                                               │      │    │
│  │  │  🔌 EKS Addons                                                │      │    │
│  │  │  • CoreDNS • kube-proxy • metrics-server • vpc-cni           │      │    │
│  │  └──────────────────────────────────────────────────────────────┘      │    │
│  │                         ↓                                                │    │
│  │  ┌──────────────────────────────────────────────────────────────┐      │    │
│  │  │  💽 RDS PostgreSQL (ap-east-1c) - 5 Instances / 11.8 TB      │      │    │
│  │  │                                                               │      │    │
│  │  │  Primary Databases (3)                                        │      │    │
│  │  │  • bingo-prd (db.m6g.large) - 2.75 TB                        │      │    │
│  │  │  • bingo-prd-backstage (db.m6g.large) - 5.02 TB              │      │    │
│  │  │  • bingo-prd-loyalty (db.t4g.medium) - 200 GB                │      │    │
│  │  │                                                               │      │    │
│  │  │  Read Replicas (2)                                            │      │    │
│  │  │  • bingo-prd-replica1 (db.m6g.large) - 2.66 TB               │      │    │
│  │  │  • backstage-replica1 (db.t4g.medium) - 1.47 TB              │      │    │
│  │  └──────────────────────────────────────────────────────────────┘      │    │
│  └────────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
│  ┌────────────────────────────────────────────────────────────────────────┐    │
│  │  📦 ECR Container Registry (29 Repositories)                           │    │
│  │  470013648166.dkr.ecr.ap-east-1.amazonaws.com                          │    │
│  │                                                                          │    │
│  │  • Arcade Games (10)    • Hash/BCN Games (8)                           │    │
│  │  • Bingo Games (1)      • Backend Services (8)                         │    │
│  │  • DevOps Tools (2)                                                    │    │
│  └────────────────────────────────────────────────────────────────────────┘    │
│              ↑                                                                   │
│              │ Pull Images                                                      │
│              └─────── EKS Nodes                                                 │
│                                                                                  │
│  ┌────────────────────────────────────────────────────────────────────────┐    │
│  │  🗄️  S3 Buckets (5)                                                    │    │
│  │                                                                          │    │
│  │  EKS 專用 (1)                     其他 (4)                              │    │
│  │  • prometheus-thanos              • campaigns-landing-pages            │    │
│  │                                    • comfyui                             │    │
│  │                                    • daily-reports                       │    │
│  │                                    • s3.geminigame.cc                    │    │
│  └────────────────────────────────────────────────────────────────────────┘    │
│              ↑                                                                   │
│              │ Backup & Monitoring Data                                         │
│              └─────── EKS / Prometheus                                          │
│                                                                                  │
│  ┌────────────────────────────────────────────────────────────────────────┐    │
│  │  📊 Monitoring & Logging                                                │    │
│  │                                                                          │    │
│  │  ☁️  CloudWatch                   📈 Prometheus/Thanos                  │    │
│  │  • EKS Control Plane Logs (~18GB) • Long-term metrics (S3)             │    │
│  │  • API Server, Audit, Auth        • Performance monitoring              │    │
│  │  • Controller, Scheduler                                                │    │
│  └────────────────────────────────────────────────────────────────────────┘    │
│                                                                                  │
│  ┌────────────────────────────────────────────────────────────────────────┐    │
│  │  📦 其他 EC2 資源 (獨立於 EKS)                                          │    │
│  │                                                                          │    │
│  │  🔧 Nginx Reverse Proxy (2 台 t3.small)                                │    │
│  │  • bingo-prd-ngx-01 (ap-east-1a)                                       │    │
│  │  • hash-prd-ngx-01 (ap-east-1a)                                        │    │
│  └────────────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## 📊 資源統計摘要

```
┌──────────────────┬────────────────────────┬──────────────┐
│ 類別             │ 項目                   │ 數量         │
├──────────────────┼────────────────────────┼──────────────┤
│ 計算資源         │ EKS Clusters           │ 1            │
│                  │ EKS Nodes (c5a.xlarge) │ 9            │
│                  │ Nginx Proxy (t3.small) │ 2            │
├──────────────────┼────────────────────────┼──────────────┤
│ 資料庫           │ RDS PostgreSQL         │ 5 (11.8 TB)  │
├──────────────────┼────────────────────────┼──────────────┤
│ 儲存             │ S3 Buckets             │ 5            │
│                  │ ECR Repositories       │ 29           │
│                  │ EBS Volumes            │ 11 (405 GB)  │
├──────────────────┼────────────────────────┼──────────────┤
│ 網路             │ VPC                    │ 1            │
│                  │ Load Balancers         │ 5 (4+1)      │
│                  │ Route53 Zones          │ 4 (59 rec)   │
├──────────────────┼────────────────────────┼──────────────┤
│ 安全             │ WAF Web ACLs           │ 1            │
│                  │ Security Groups        │ 15+          │
│                  │ IAM Roles              │ 9            │
└──────────────────┴────────────────────────┴──────────────┘
```

---

## 🔄 流量路徑簡圖

```
Users (HTTPS)
    ↓
Route53 DNS (4 zones, 59 records)
    ↓
WAF (eks-waf) - Security Filtering
    ↓
┌─────────────────────────────────────────────┐
│  Application Load Balancers (4)             │
│  • Istio Gateway                            │
│  • Backend API                              │
│  • OpenAPI                                  │
│  • ArgoCD                                   │
└─────────────────────────────────────────────┘
    ↓
Network Load Balancer (Internal)
    • Nginx Ingress Controller
    ↓
┌─────────────────────────────────────────────┐
│  EKS Nodes (9 nodes across 3 AZs)          │
│                                             │
│  ap-east-1a: 2 nodes                       │
│  ap-east-1b: 3 nodes                       │
│  ap-east-1c: 4 nodes                       │
└─────────────────────────────────────────────┘
    ↓
┌─────────────────────────────────────────────┐
│  Application Pods (78+ Services)            │
│  • 10 Arcade Games                          │
│  • 1 Bingo Game                             │
│  • 8 Hash/BCN Games                         │
│  • 8 Backend Services                       │
│  • 2 DevOps Tools                           │
└─────────────────────────────────────────────┘
    ↓
┌─────────────────────────────────────────────┐
│  RDS PostgreSQL (5 instances, 11.8 TB)     │
│  • 3 Primary Databases                      │
│  • 2 Read Replicas                          │
└─────────────────────────────────────────────┘
```

---

## 🌍 Multi-AZ 分布圖

```
┌────────────────────────────────────────────────────────────────┐
│                ap-east-1 (Hong Kong Region)                    │
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐        │
│  │ ap-east-1a   │  │ ap-east-1b   │  │ ap-east-1c   │        │
│  ├──────────────┤  ├──────────────┤  ├──────────────┤        │
│  │              │  │              │  │              │        │
│  │ EKS Nodes:   │  │ EKS Nodes:   │  │ EKS Nodes:   │        │
│  │ • Node 1     │  │ • Node 3     │  │ • Node 6     │        │
│  │ • Node 2     │  │ • Node 4     │  │ • Node 7     │        │
│  │              │  │ • Node 5     │  │ • Node 8     │        │
│  │              │  │              │  │ • Node 9     │        │
│  │              │  │              │  │              │        │
│  │ Node Groups: │  │ Node Groups: │  │ Node Groups: │        │
│  │ • base (1)   │  │ • arcade (1) │  │ • bg (2)     │        │
│  │ • arcade (1) │  │ • bg (2)     │  │ • hash (2)   │        │
│  │              │  │              │  │              │        │
│  │ Nginx Proxy: │  │ Nginx Proxy: │  │ RDS:         │        │
│  │ • bingo-ngx  │  │ • hash-ngx   │  │ • All DBs    │        │
│  │              │  │              │  │ • Replicas   │        │
│  └──────────────┘  └──────────────┘  └──────────────┘        │
│                                                                 │
│  Load Balancers: Multi-AZ (All 3 zones)                       │
│  • 4 ALBs (Internet-facing)                                    │
│  • 1 NLB (Internal)                                            │
└────────────────────────────────────────────────────────────────┘
```

---

## 🔐 安全層架構

```
┌─────────────────────────────────────────────────────────┐
│                    Security Layers                      │
│                                                          │
│  Layer 1: External Protection                           │
│  ┌─────────────────────────────────────────────┐       │
│  │  🛡️  WAF (Web Application Firewall)         │       │
│  │  • Regional: ap-east-1                      │       │
│  │  • Protects: 4 ALBs                         │       │
│  │  • Rules: Security filtering                │       │
│  └─────────────────────────────────────────────┘       │
│                     ↓                                    │
│  Layer 2: Network Security                              │
│  ┌─────────────────────────────────────────────┐       │
│  │  🚧 Security Groups (15+)                   │       │
│  │  • EKS Control Plane & Nodes                │       │
│  │  • RDS Databases                            │       │
│  │  • Load Balancers                           │       │
│  │  • VPC Endpoints                            │       │
│  └─────────────────────────────────────────────┘       │
│                     ↓                                    │
│  Layer 3: Identity & Access                             │
│  ┌─────────────────────────────────────────────┐       │
│  │  🔑 IAM (9 Roles)                           │       │
│  │                                              │       │
│  │  EKS Cluster Roles (4):                     │       │
│  │  • Cluster Service Role                     │       │
│  │  • Node Instance Roles (2)                  │       │
│  │  • EKS Cluster Role                         │       │
│  │                                              │       │
│  │  IRSA - Service Accounts (5):               │       │
│  │  • Cluster Autoscaler                       │       │
│  │  • ECR Access                                │       │
│  │  • VPC CNI                                   │       │
│  │  • Service Accounts (2)                     │       │
│  └─────────────────────────────────────────────┘       │
│                     ↓                                    │
│  Layer 4: Encryption                                     │
│  ┌─────────────────────────────────────────────┐       │
│  │  🔒 Data Encryption                          │       │
│  │                                              │       │
│  │  At Rest:                                    │       │
│  │  • RDS: AES-256                             │       │
│  │  • EBS: AES-256                             │       │
│  │  • S3: SSE-S3                               │       │
│  │  • ECR: AES-256                             │       │
│  │                                              │       │
│  │  In Transit:                                 │       │
│  │  • HTTPS/TLS for all external traffic       │       │
│  │  • VPC encryption for internal traffic      │       │
│  └─────────────────────────────────────────────┘       │
└─────────────────────────────────────────────────────────┘
```

---

## 📊 監控架構

```
┌──────────────────────────────────────────────────────────┐
│              Monitoring & Observability                  │
│                                                           │
│  ┌────────────────────────────────────────────────┐     │
│  │  ☁️  CloudWatch (AWS Managed)                  │     │
│  │                                                 │     │
│  │  EKS Control Plane Logs (~18 GB):              │     │
│  │  • API Server                                   │     │
│  │  • Audit Logs                                   │     │
│  │  • Authenticator                                │     │
│  │  • Controller Manager                           │     │
│  │  • Scheduler                                    │     │
│  └────────────────────────────────────────────────┘     │
│                     ↓                                     │
│  ┌────────────────────────────────────────────────┐     │
│  │  📈 Prometheus/Thanos                          │     │
│  │                                                 │     │
│  │  Collection:                                    │     │
│  │  • Node metrics                                 │     │
│  │  • Pod metrics                                  │     │
│  │  • Application metrics                          │     │
│  │                                                 │     │
│  │  Long-term Storage:                            │     │
│  │  • S3: gemini-prometheus-thanos                │     │
│  │  • Retention: Unlimited                        │     │
│  └────────────────────────────────────────────────┘     │
│                     ↓                                     │
│  ┌────────────────────────────────────────────────┐     │
│  │  🔌 EKS Addons                                 │     │
│  │                                                 │     │
│  │  • metrics-server: Resource metrics            │     │
│  │  • CoreDNS: DNS metrics                        │     │
│  │  • kube-proxy: Network metrics                 │     │
│  │  • vpc-cni: VPC networking metrics             │     │
│  └────────────────────────────────────────────────┘     │
└──────────────────────────────────────────────────────────┘
```

---

## 📝 說明

1. **ASCII 圖例**:
   - `┌─┐└─┘├─┤│`: 方框邊框
   - `↓ ↑ →`: 資料/流量流向
   - `•`: 列表項目
   - `🎯 ☁️ 📦 等`: Emoji 圖示表示資源類型

2. **架構特點**:
   - ✅ Multi-AZ 高可用性 (3 個 AZ)
   - ✅ 多層安全防護 (WAF + SG + IAM + Encryption)
   - ✅ 水平擴展能力 (Auto Scaling)
   - ✅ 讀寫分離 (RDS Read Replicas)
   - ✅ GitOps 部署 (ArgoCD)
   - ✅ 服務網格 (Istio)
   - ✅ 完整監控 (CloudWatch + Prometheus/Thanos)

3. **容量總計**:
   - 計算: 11 instances (40 vCPU, 76 GB RAM)
   - 儲存: 11.8 TB (RDS) + 405 GB (EBS)
   - 網路: 5 Load Balancers, 4 DNS zones
   - 應用: 78+ 部署服務

---

**文檔版本**: 4.1
**創建日期**: 2025-12-31
**最後更新**: 2026-01-02
**對應清單**: AWS_PRODUCTION_RESOURCES_LIST.md v2.0

---

## 📝 文檔變更記錄

| 版本 | 日期 | 變更內容 |
|------|------|---------|
| **4.1** | 2026-01-02 | 🔧 **S3 Buckets 清單更新 (對齊 v4.1)**: ① EKS 專用 S3 buckets 從 3 個更新為 1 個 ② 移除 velero-backups 和 svc-backup ③ 只保留 prometheus-thanos ④ 總 S3 buckets 數量從 7 個更新為 5 個 ⑤ 與 AWS_PRODUCTION_ARCHITECTURE.md v4.1 和 EKS_RESOURCES_INVENTORY.md v1.1 保持一致 ⑥ 相關 JIRA: OPS-993 |
| 1.0 | 2025-12-31 | 📋 初始 ASCII 架構圖版本 |
