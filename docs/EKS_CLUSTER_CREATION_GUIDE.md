# EKS Cluster 創建指南

**Cluster**: gemini-game-prd
**Region**: ap-east-1 (Hong Kong)
**Kubernetes Version**: 1.34
**最後更新**: 2025-12-31

---

## 📋 目錄

- [架構概述](#架構概述)
- [先決條件](#先決條件)
- [配置文件說明](#配置文件說明)
- [創建流程](#創建流程)
- [驗證部署](#驗證部署)
- [故障排除](#故障排除)

---

## 架構概述

### Cluster 架構

```
gemini-game-prd (EKS 1.34)
├── VPC: vpc-086d3d02c471379fa
│   ├── Private Subnet (ap-east-1a): subnet-0299241949619111d
│   ├── Private Subnet (ap-east-1b): subnet-0e2167c1d333679d1
│   └── Private Subnet (ap-east-1c): subnet-06fb271b87bc5928c
│
├── Node Groups
│   ├── gemini-base (1 node, c5a.xlarge)       - 基礎設施
│   ├── gemini-bg-new (3-5 nodes)              - Bingo 遊戲
│   ├── gemini-arcade-new (2-5 nodes)          - Arcade 遊戲
│   └── gemini-hash-new (2-5 nodes)            - Hash/BCN 遊戲
│
└── Addons
    ├── AWS Load Balancer Controller
    ├── EBS CSI Driver
    ├── Cluster Autoscaler
    ├── ECR IRSA (Image Pull)
    └── Istio Service Mesh
```

### 資源配置摘要

| 組件 | 配置 | 說明 |
|------|------|------|
| **Cluster** | gemini-game-prd | 生產環境 EKS cluster |
| **Kubernetes** | 1.34 | 最新穩定版本 |
| **VPC** | vpc-086d3d02c471379fa | 現有 VPC (172.31.0.0/16) |
| **Subnets** | 3 Private Subnets | Multi-AZ 部署 |
| **Node Type** | c5a.xlarge (4 vCPU, 8 GB) | 成本優化型計算實例 |
| **AMI** | AmazonLinux2023 | 最新 Amazon Linux |
| **Volume** | gp3 (60-100 GB) | 高效能 SSD |
| **Security Group** | sg-095b66380d741c642 | 統一安全組 |
| **SSH Key** | hk-devops | 管理用 SSH 金鑰 |

---

## 先決條件

### 1. 本地工具安裝

```bash
# eksctl (EKS 管理工具)
brew install eksctl

# kubectl (Kubernetes CLI)
brew install kubectl

# AWS CLI v2
brew install awscli

# 驗證安裝
eksctl version     # 應顯示 0.190.0+
kubectl version    # 應顯示 client version
aws --version      # 應顯示 aws-cli/2.x
```

### 2. AWS 憑證配置

```bash
# 配置 AWS Profile (使用具有 EKS 完整權限的 profile)
aws configure --profile gemini-ck

# 驗證憑證
aws sts get-caller-identity --profile gemini-ck

# 輸出範例：
# {
#     "UserId": "AIDAXXXXXXXXXXXXXXXXX",
#     "Account": "470013648166",
#     "Arn": "arn:aws:iam::470013648166:user/eks-admin"
# }
```

### 3. IAM 權限要求

確保 IAM 用戶/角色具有以下權限：
- `AmazonEKSClusterPolicy`
- `AmazonEKSServicePolicy`
- `AmazonEKSVPCResourceController`
- EC2 完整權限（創建節點群組需要）
- CloudFormation 完整權限（eksctl 使用）
- IAM 權限（創建 service accounts）

### 4. 網路資源確認

```bash
# 確認 VPC 存在
aws ec2 describe-vpcs --vpc-ids vpc-086d3d02c471379fa --profile gemini-ck

# 確認 Subnets 存在
aws ec2 describe-subnets --subnet-ids \
  subnet-0299241949619111d \
  subnet-0e2167c1d333679d1 \
  subnet-06fb271b87bc5928c \
  --profile gemini-ck

# 確認 Security Group 存在
aws ec2 describe-security-groups --group-ids sg-095b66380d741c642 --profile gemini-ck

# 確認 SSH Key Pair 存在
aws ec2 describe-key-pairs --key-names hk-devops --profile gemini-ck
```

---

## 配置文件說明

### 文件結構

參考配置位於：`/Users/lonelyhsu/gemini/toolkits/AWS/EKS/gemini-game-prd/create_eks_cluster/`

```
create_eks_cluster/
├── cluster.yaml                    # 主 Cluster + Base 節點群組配置
├── new-gemini-game-bg.yaml         # Bingo 遊戲節點群組
├── new-gemini-game-arcade.yaml     # Arcade 遊戲節點群組
├── new-gemini-game-hash.yaml       # Hash/BCN 遊戲節點群組
├── eks_menu.sh                     # 互動式管理腳本
└── README.md                       # 快速參考
```

### 主要配置檔案

#### 1. `cluster.yaml` - 主 Cluster 配置

**核心配置**:
```yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: gemini-game-prd
  region: ap-east-1
  version: "1.34"

iam:
  withOIDC: true  # 啟用 IRSA (IAM Roles for Service Accounts)

vpc:
  id: vpc-086d3d02c471379fa
  subnets:
    private:
      ap-east-1a: { id: subnet-0299241949619111d }
      ap-east-1b: { id: subnet-0e2167c1d333679d1 }
      ap-east-1c: { id: subnet-06fb271b87bc5928c }
    public: {}  # 不使用公有子網路（節點全部私有）

managedNodeGroups:
  - name: gemini-base
    amiFamily: AmazonLinux2023
    instanceType: c5a.xlarge
    minSize: 1
    maxSize: 2
    desiredCapacity: 1
    privateNetworking: true
    volumeSize: 60
    volumeType: gp3
    labels:
      node_pool: base
      cluster: gemini-game-prd
      service: all
```

**關鍵特性**:
- ✅ OIDC Provider 啟用（支援 IRSA）
- ✅ 私有網路（所有節點無公網 IP）
- ✅ gp3 磁碟（比 gp2 更高效能且成本相同）
- ✅ Cluster Autoscaler 支援
- ✅ CloudWatch Logs（保留 30 天）

**時區配置**:
```yaml
preBootstrapCommands:
  - "ln -sf /usr/share/zoneinfo/Asia/Taipei /etc/localtime"
  - "echo 'Asia/Taipei' > /etc/timezone"
```
> 確保所有節點使用台北時區，避免日誌時間混亂

**CloudWatch Logging**:
```yaml
cloudWatch:
  clusterLogging:
    enableTypes: ["audit", "authenticator", "controllerManager"]
    logRetentionInDays: 30
```

啟用的日誌類型：
- `audit`: Kubernetes 審計日誌（安全合規必備）
- `authenticator`: 身份驗證日誌
- `controllerManager`: Controller manager 日誌

未啟用的日誌類型（可選）：
- `api`: API Server 日誌（流量大，成本高）
- `scheduler`: Scheduler 調度日誌（除錯用）

#### 2. Node Group 配置文件

**BG (Bingo) 節點群組** (`new-gemini-game-bg.yaml`):
```yaml
managedNodeGroups:
  - name: gemini-bg-new
    instanceTypes: [c5a.xlarge, c5.xlarge]  # 支援兩種實例類型（fallback）
    minSize: 3
    maxSize: 5
    desiredCapacity: 3
    volumeSize: 100  # 較大的磁碟空間（遊戲資料）
    labels:
      node_pool: bg-gate
```
> **用途**: Bingo 遊戲服務（最高負載，預設 3 節點）

**Arcade 節點群組** (`new-gemini-game-arcade.yaml`):
```yaml
managedNodeGroups:
  - name: gemini-arcade-new
    instanceTypes: [c5a.xlarge, c5.xlarge]
    minSize: 2
    maxSize: 5
    desiredCapacity: 2
    labels:
      node_pool: arcade-gate
```
> **用途**: Arcade 遊戲服務（中等負載，預設 2 節點）

**Hash/BCN 節點群組** (`new-gemini-game-hash.yaml`):
```yaml
managedNodeGroups:
  - name: gemini-hash-new
    instanceTypes: [c5a.xlarge, c5.xlarge]
    minSize: 2
    maxSize: 5
    desiredCapacity: 2
    labels:
      node_pool: hash-gate
```
> **用途**: Hash/BCN 遊戲服務（中等負載，預設 2 節點）

---

## 創建流程

### 方式一：使用互動式腳本（推薦）

#### 1. 執行管理腳本

```bash
cd /Users/lonelyhsu/gemini/toolkits/AWS/EKS/gemini-game-prd/create_eks_cluster

# 執行互動式選單
bash eks_menu.sh
```

#### 2. 選擇選項

```
========================================
            EKS 管理面板 (gemini-game-prd)
========================================
[1] 建立完整 EKS 環境 (叢集+addon+ingress)
[2] 刪除叢集與節點組
[3] 建立節點組 - Arcade
[4] 建立節點組 - BG
[5] 建立節點組 - Hash
[6] 刪除節點組 - Arcade
[7] 刪除節點組 - BG
[8] 刪除節點組 - Hash
[0] 離開程式
----------------------------------------
目前設定：PROFILE=gemini-ck  REGION=ap-east-1
```

**選項說明**:
- **選項 1**: 完整部署（Cluster → Addons → Ingress）
  - 創建 EKS cluster + base 節點群組
  - 自動執行 `initial_configuration/install.sh`
  - 自動部署 Ingress 配置
  - 自動發送 Slack 通知（需配置 Token）

- **選項 3-5**: 僅創建額外節點群組
- **選項 6-8**: 刪除節點群組（保留 cluster）

#### 3. 自動化流程

選擇「選項 1」後，腳本會自動執行：

```bash
# 步驟 1: 創建 Cluster + Base 節點群組
eksctl --profile gemini-ck create cluster -f cluster.yaml

# 步驟 2: 部署 K8s Addons
cd ../initial_configuration && bash install.sh
# ✅ AWS Load Balancer Controller
# ✅ EBS CSI Driver
# ✅ Cluster Autoscaler
# ✅ ECR IRSA
# ✅ Istio Service Mesh

# 步驟 3: 部署 Ingress
kubectl apply -f ../gate-svc-ingress.yaml
kubectl apply -f ../backend-api-ingress.yaml
kubectl apply -f ../open-api-ingress.yaml
```

**預計時間**:
- Cluster 創建: ~15-20 分鐘
- Addons 部署: ~10-15 分鐘
- Ingress 部署: ~5 分鐘
- **總計**: ~30-40 分鐘

---

### 方式二：手動逐步執行

#### 步驟 1: 創建 Cluster + Base 節點群組

```bash
cd /Users/lonelyhsu/gemini/toolkits/AWS/EKS/gemini-game-prd/create_eks_cluster

eksctl --profile gemini-ck create cluster -f cluster.yaml
```

**預期輸出**:
```
2025-12-31 10:00:00 [ℹ]  eksctl version 0.190.0
2025-12-31 10:00:00 [ℹ]  using region ap-east-1
2025-12-31 10:00:01 [ℹ]  setting availability zones to [ap-east-1a ap-east-1b ap-east-1c]
2025-12-31 10:00:01 [ℹ]  subnets for ap-east-1a - private:172.31.48.0/20
2025-12-31 10:00:01 [ℹ]  subnets for ap-east-1b - private:172.31.64.0/20
2025-12-31 10:00:01 [ℹ]  subnets for ap-east-1c - private:172.31.80.0/20
2025-12-31 10:00:02 [ℹ]  nodegroup "gemini-base" will use "ami-0abcd1234567890ef" [AmazonLinux2023/1.34]
2025-12-31 10:00:05 [ℹ]  using Kubernetes version 1.34
2025-12-31 10:00:05 [ℹ]  creating EKS cluster "gemini-game-prd" in "ap-east-1" region
...
2025-12-31 10:15:00 [✔]  EKS cluster "gemini-game-prd" in "ap-east-1" region is ready
```

#### 步驟 2: 更新 Kubeconfig

```bash
# 自動配置（eksctl 會自動更新）
# 如果 kubeconfig 為空，手動執行：
eksctl utils write-kubeconfig \
  --cluster gemini-game-prd \
  --region ap-east-1 \
  --profile gemini-ck

# 驗證
kubectl config current-context
# 輸出: iam-root-account@gemini-game-prd.ap-east-1.eksctl.io

kubectl get nodes
# 輸出:
# NAME                                          STATUS   ROLES    AGE   VERSION
# ip-172-31-48-123.ap-east-1.compute.internal   Ready    <none>   2m    v1.34.0
```

#### 步驟 3: 部署 Addons

```bash
cd ../initial_configuration

# 執行自動化安裝腳本
bash install.sh
```

`install.sh` 會依序部署：
1. **AWS Load Balancer Controller**: ALB/NLB 整合
2. **EBS CSI Driver**: 持久化儲存
3. **Cluster Autoscaler**: 自動擴展節點
4. **ECR IRSA**: 私有鏡像拉取權限
5. **Istio**: Service Mesh（可選）

#### 步驟 4: 創建額外節點群組

```bash
cd ../create_eks_cluster

# BG 節點群組
eksctl --profile gemini-ck create nodegroup --config-file new-gemini-game-bg.yaml

# Arcade 節點群組
eksctl --profile gemini-ck create nodegroup --config-file new-gemini-game-arcade.yaml

# Hash 節點群組
eksctl --profile gemini-ck create nodegroup --config-file new-gemini-game-hash.yaml
```

**預計時間**: 每個節點群組 ~10-12 分鐘

#### 步驟 5: 部署 Ingress

```bash
cd ..

# Gateway Service Ingress (Istio)
kubectl apply -f gate-svc-ingress.yaml

# Backend API Ingress
kubectl apply -f backend-api-ingress.yaml

# OpenAPI Ingress
kubectl apply -f open-api-ingress.yaml
```

---

## 驗證部署

### 1. 檢查 Cluster 狀態

```bash
# Cluster 資訊
eksctl --profile gemini-ck get cluster --name gemini-game-prd

# 輸出:
# NAME               REGION      EKSCTL CREATED
# gemini-game-prd    ap-east-1   True

# 詳細資訊
aws eks describe-cluster \
  --name gemini-game-prd \
  --region ap-east-1 \
  --profile gemini-ck \
  --query 'cluster.{Name:name,Status:status,Version:version,Endpoint:endpoint}'

# 輸出 (JSON):
# {
#     "Name": "gemini-game-prd",
#     "Status": "ACTIVE",
#     "Version": "1.34",
#     "Endpoint": "https://BB55D1B90C7C737B866422B095F74112.gr7.ap-east-1.eks.amazonaws.com"
# }
```

### 2. 檢查節點群組

```bash
# 列出所有節點群組
eksctl --profile gemini-ck get nodegroup --cluster gemini-game-prd

# 輸出:
# CLUSTER             NODEGROUP          STATUS   CREATED                 MIN SIZE  MAX SIZE  DESIRED CAPACITY  INSTANCE TYPE  IMAGE ID    ASG NAME
# gemini-game-prd     gemini-base        ACTIVE   2025-10-31T00:00:00Z    1         2         1                 c5a.xlarge     AL2023      eks-gemini-base-xxx
# gemini-game-prd     gemini-bg-new      ACTIVE   2025-11-01T00:00:00Z    3         5         4                 c5a.xlarge     AL2023      eks-gemini-bg-new-xxx
# gemini-game-prd     gemini-arcade-new  ACTIVE   2025-11-01T00:00:00Z    2         5         2                 c5a.xlarge     AL2023      eks-gemini-arcade-xxx
# gemini-game-prd     gemini-hash-new    ACTIVE   2025-11-01T00:00:00Z    2         5         2                 c5a.xlarge     AL2023      eks-gemini-hash-xxx
```

### 3. 檢查節點狀態

```bash
# 列出所有節點
kubectl get nodes -o wide

# 輸出範例:
# NAME                                          STATUS   ROLES    AGE   VERSION   INTERNAL-IP     EXTERNAL-IP   OS-IMAGE         KERNEL-VERSION   CONTAINER-RUNTIME
# ip-172-31-48-123.ap-east-1.compute.internal   Ready    <none>   5d    v1.34.0   172.31.48.123   <none>        Amazon Linux 2   6.1.112-124.190  containerd://1.7.11
# ip-172-31-64-234.ap-east-1.compute.internal   Ready    <none>   5d    v1.34.0   172.31.64.234   <none>        Amazon Linux 2   6.1.112-124.190  containerd://1.7.11
# ...

# 按節點群組查看
kubectl get nodes --selector node_pool=base
kubectl get nodes --selector node_pool=bg-gate
kubectl get nodes --selector node_pool=arcade-gate
kubectl get nodes --selector node_pool=hash-gate

# 節點詳細資訊（資源、標籤、taints）
kubectl describe node <node-name>
```

### 4. 檢查 Addons

```bash
# AWS Load Balancer Controller
kubectl get deployment -n kube-system aws-load-balancer-controller
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# EBS CSI Driver
kubectl get daemonset -n kube-system ebs-csi-node
kubectl get deployment -n kube-system ebs-csi-controller

# Cluster Autoscaler
kubectl get deployment -n kube-system cluster-autoscaler
kubectl logs -n kube-system deployment/cluster-autoscaler | tail -20

# Istio (如果已安裝)
kubectl get pods -n istio-system
kubectl get svc -n istio-system istio-ingressgateway
```

### 5. 檢查 Ingress

```bash
# 列出所有 Ingress
kubectl get ingress --all-namespaces

# 檢查 ALB 狀態
kubectl get ingress -n istio-system gate-svc-ingress -o yaml
kubectl get ingress -n istio-system backend-api-ingress -o yaml
kubectl get ingress -n istio-system open-api-ingress -o yaml

# 檢查 AWS Load Balancer
aws elbv2 describe-load-balancers \
  --region ap-east-1 \
  --profile gemini-ck \
  --query 'LoadBalancers[?starts_with(LoadBalancerName, `k8s-istiosys`)].{Name:LoadBalancerName,DNS:DNSName,State:State.Code}'
```

### 6. 檢查 OIDC Provider

```bash
# 獲取 OIDC Provider URL
aws eks describe-cluster \
  --name gemini-game-prd \
  --region ap-east-1 \
  --profile gemini-ck \
  --query 'cluster.identity.oidc.issuer' \
  --output text

# 輸出範例:
# https://oidc.eks.ap-east-1.amazonaws.com/id/BB55D1B90C7C737B866422B095F74112

# 驗證 OIDC Provider 存在
aws iam list-open-id-connect-providers --profile gemini-ck
```

### 7. 檢查 Service Accounts (IRSA)

```bash
# 列出所有 Service Accounts
kubectl get serviceaccounts --all-namespaces | grep eks.amazonaws.com

# 檢查具有 IAM Role 的 Service Accounts
kubectl get sa -n kube-system aws-load-balancer-controller -o yaml
kubectl get sa -n kube-system ebs-csi-controller-sa -o yaml
kubectl get sa -n kube-system cluster-autoscaler -o yaml

# 驗證 annotation
kubectl get sa -n kube-system aws-load-balancer-controller \
  -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}'
# 輸出: arn:aws:iam::470013648166:role/AmazonEKSLoadBalancerControllerRole
```

### 8. 功能驗證

#### 測試 Cluster Autoscaler

```bash
# 檢查 Autoscaler 日誌
kubectl logs -n kube-system deployment/cluster-autoscaler --tail=50

# 創建測試部署（大量 replicas 觸發擴展）
kubectl create deployment test-scale --image=nginx --replicas=20
kubectl set resources deployment test-scale --requests=cpu=1000m,memory=1Gi

# 觀察節點自動擴展（需等待 2-3 分鐘）
watch kubectl get nodes

# 清理測試
kubectl delete deployment test-scale
```

#### 測試 EBS CSI Driver

```bash
# 創建 PVC
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-ebs-claim
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: gp3
EOF

# 檢查 PVC 狀態
kubectl get pvc test-ebs-claim

# 檢查 PV 自動創建
kubectl get pv

# 清理測試
kubectl delete pvc test-ebs-claim
```

#### 測試 ALB Ingress

```bash
# 創建測試服務
kubectl create deployment test-nginx --image=nginx
kubectl expose deployment test-nginx --port=80 --type=NodePort

# 創建 Ingress
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: test-ingress
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
spec:
  rules:
  - http:
      paths:
      - path: /test
        pathType: Prefix
        backend:
          service:
            name: test-nginx
            port:
              number: 80
EOF

# 檢查 Ingress（等待 ALB 創建，約 2-3 分鐘）
kubectl get ingress test-ingress
kubectl describe ingress test-ingress

# 清理測試
kubectl delete ingress test-ingress
kubectl delete service test-nginx
kubectl delete deployment test-nginx
```

---

## 故障排除

### 常見問題

#### 1. Cluster 創建失敗

**錯誤訊息**:
```
Error: checking STS access: operation error STS: GetCallerIdentity
```

**解決方案**:
```bash
# 檢查 AWS 憑證
aws sts get-caller-identity --profile gemini-ck

# 重新配置 profile
aws configure --profile gemini-ck

# 確認 IAM 權限
aws iam get-user --profile gemini-ck
```

#### 2. Kubeconfig 為空

**錯誤訊息**:
```
The connection to the server localhost:8080 was refused
```

**解決方案**:
```bash
# 重新寫入 kubeconfig
eksctl utils write-kubeconfig \
  --cluster gemini-game-prd \
  --region ap-east-1 \
  --profile gemini-ck

# 驗證
kubectl config current-context
kubectl get nodes
```

#### 3. 節點群組創建失敗

**錯誤訊息**:
```
error creating node group: operation error EKS: CreateNodegroup
```

**可能原因**:
- Subnet 不存在或無權限
- Security Group 不存在
- SSH Key 不存在
- Instance 類型在該 region 不可用

**排查步驟**:
```bash
# 1. 驗證 Subnets
aws ec2 describe-subnets \
  --subnet-ids subnet-0299241949619111d subnet-0e2167c1d333679d1 subnet-06fb271b87bc5928c \
  --profile gemini-ck

# 2. 驗證 Security Group
aws ec2 describe-security-groups \
  --group-ids sg-095b66380d741c642 \
  --profile gemini-ck

# 3. 驗證 SSH Key
aws ec2 describe-key-pairs \
  --key-names hk-devops \
  --profile gemini-ck

# 4. 檢查 Instance 類型可用性
aws ec2 describe-instance-type-offerings \
  --location-type availability-zone \
  --filters Name=instance-type,Values=c5a.xlarge \
  --region ap-east-1 \
  --profile gemini-ck
```

#### 4. Addon 部署失敗

**AWS Load Balancer Controller 無法啟動**:
```bash
# 檢查 IRSA 配置
kubectl get sa -n kube-system aws-load-balancer-controller -o yaml

# 檢查 IAM Role
aws iam get-role \
  --role-name AmazonEKSLoadBalancerControllerRole \
  --profile gemini-ck

# 檢查 Pod 日誌
kubectl logs -n kube-system deployment/aws-load-balancer-controller
```

**EBS CSI Driver 無法創建 PV**:
```bash
# 檢查 IRSA
kubectl get sa -n kube-system ebs-csi-controller-sa -o yaml

# 檢查 Pod 狀態
kubectl get pods -n kube-system -l app=ebs-csi-controller

# 檢查日誌
kubectl logs -n kube-system deployment/ebs-csi-controller -c ebs-plugin
```

#### 5. Ingress 無法創建 ALB

**錯誤訊息（在 Ingress events）**:
```
Failed build model due to failed to build targetGroup
```

**解決方案**:
```bash
# 1. 檢查 ALB Controller 日誌
kubectl logs -n kube-system deployment/aws-load-balancer-controller

# 2. 驗證 Subnet 標籤
aws ec2 describe-subnets \
  --subnet-ids subnet-0299241949619111d \
  --profile gemini-ck \
  --query 'Subnets[0].Tags'

# 需要的標籤：
# - kubernetes.io/role/internal-elb: 1 (私有 ALB)
# - kubernetes.io/role/elb: 1 (公網 ALB)
# - kubernetes.io/cluster/gemini-game-prd: shared

# 3. 添加缺失的標籤
aws ec2 create-tags \
  --resources subnet-0299241949619111d subnet-0e2167c1d333679d1 subnet-06fb271b87bc5928c \
  --tags Key=kubernetes.io/role/internal-elb,Value=1 \
         Key=kubernetes.io/cluster/gemini-game-prd,Value=shared \
  --profile gemini-ck
```

#### 6. Cluster Autoscaler 不擴展

**檢查 Autoscaler 狀態**:
```bash
# 查看日誌
kubectl logs -n kube-system deployment/cluster-autoscaler --tail=100

# 常見錯誤：無權限擴展 ASG
# 解決：檢查 IAM Policy

# 驗證 IAM Role
aws iam get-role-policy \
  --role-name eksctl-gemini-game-prd-nodegroup-NodeInstanceRole-xxx \
  --policy-name cluster-autoscaler-policy \
  --profile gemini-ck
```

---

### 日誌收集

#### Cluster 級別日誌

```bash
# CloudWatch Logs
aws logs describe-log-groups \
  --log-group-name-prefix /aws/eks/gemini-game-prd \
  --profile gemini-ck

# 查看審計日誌
aws logs tail /aws/eks/gemini-game-prd/cluster/audit \
  --follow \
  --profile gemini-ck

# 查看 authenticator 日誌
aws logs tail /aws/eks/gemini-game-prd/cluster/authenticator \
  --follow \
  --profile gemini-ck
```

#### 節點級別日誌

```bash
# SSH 到節點（需要 Session Manager 或 SSH Key）
aws ssm start-session \
  --target <instance-id> \
  --profile gemini-ck

# 在節點上查看日誌
sudo journalctl -u kubelet -f
sudo journalctl -u containerd -f
cat /var/log/cloud-init-output.log
```

#### Pod 日誌

```bash
# 查看 Pod 日誌
kubectl logs <pod-name> -n <namespace>

# 查看前一個容器日誌（如果 Pod 重啟）
kubectl logs <pod-name> -n <namespace> --previous

# 查看所有容器日誌
kubectl logs <pod-name> -n <namespace> --all-containers=true

# 實時跟蹤日誌
kubectl logs <pod-name> -n <namespace> -f
```

---

## 安全注意事項

### 1. SSH Key 管理

```bash
# 不要在配置文件中硬編碼 SSH private key
# 使用 AWS EC2 Key Pair

# 定期輪換 SSH Key
aws ec2 create-key-pair \
  --key-name hk-devops-2026 \
  --profile gemini-ck
```

### 2. IAM 權限最小化

```bash
# 定期審查 IAM Roles
aws iam list-attached-role-policies \
  --role-name eksctl-gemini-game-prd-nodegroup-NodeInstanceRole-xxx \
  --profile gemini-ck

# 移除不必要的權限
```

### 3. Security Group 規則

```bash
# 定期審查 Security Group
aws ec2 describe-security-groups \
  --group-ids sg-095b66380d741c642 \
  --profile gemini-ck

# 確保最小權限原則
# - 僅允許必要的端口
# - 限制來源 IP（不要使用 0.0.0.0/0，除非必要）
```

### 4. Secrets 管理

```bash
# 使用 AWS Secrets Manager 或 Kubernetes Secrets
# 不要在配置文件中硬編碼敏感資訊

# 例如：Slack Token 應該從 Secrets Manager 讀取
aws secretsmanager get-secret-value \
  --secret-id slack-webhook-token \
  --profile gemini-ck
```

### 5. 網路隔離

- ✅ 所有 worker nodes 使用私有子網路
- ✅ Control Plane 端點可選擇私有或公有+私有
- ✅ 使用 Security Groups 限制流量
- ✅ 啟用 VPC Flow Logs（可選）

---

## 成本優化建議

### 1. 使用 Spot Instances（開發/測試環境）

```yaml
# 在 nodegroup 配置中添加
instancesDistribution:
  maxPrice: 0.1  # 每小時最高價格
  instanceTypes: [c5a.xlarge, c5.xlarge]
  onDemandBaseCapacity: 1  # 至少 1 個 On-Demand
  onDemandPercentageAboveBaseCapacity: 0  # 其他全用 Spot
  spotInstancePools: 2
```

### 2. 使用 Reserved Instances（生產環境）

```bash
# 購買 1 年或 3 年期 Reserved Instances
# 節省高達 72% 成本
```

### 3. Right-sizing

```bash
# 定期檢查節點資源使用率
kubectl top nodes

# 調整節點群組大小
eksctl --profile gemini-ck scale nodegroup \
  --cluster gemini-game-prd \
  --name gemini-bg-new \
  --nodes 3 \
  --nodes-min 2 \
  --nodes-max 6
```

### 4. 啟用 Cluster Autoscaler

- ✅ 已在配置中啟用
- ✅ 自動根據負載調整節點數量
- ✅ 避免過度配置

---

## 參考資源

### 官方文檔
- [EKS User Guide](https://docs.aws.amazon.com/eks/latest/userguide/)
- [eksctl Documentation](https://eksctl.io/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)

### 內部文檔
- [AWS Production Resources List](./AWS_PRODUCTION_RESOURCES_LIST.md)
- [AWS Production Architecture Diagram](./AWS_PRODUCTION_ARCHITECTURE_DIAGRAM.md)

### 配置範本位置
- 主配置: `/Users/lonelyhsu/gemini/toolkits/AWS/EKS/gemini-game-prd/create_eks_cluster/`
- Addons: `/Users/lonelyhsu/gemini/toolkits/AWS/EKS/gemini-game-prd/initial_configuration/`
- Ingress: `/Users/lonelyhsu/gemini/toolkits/AWS/EKS/gemini-game-prd/*.yaml`

---

## 版本歷史

| 版本 | 日期 | 變更內容 |
|------|------|----------|
| 1.0 | 2025-12-31 | 初始版本 - 基於現有生產環境配置創建 |

---

**注意事項**:
- 本文檔基於現有生產環境 `gemini-game-prd` 的配置編寫
- 執行任何變更前請先在開發/測試環境驗證
- 生產環境變更需要經過 Change Management 流程
- 保持配置文件版本控制，避免配置漂移
