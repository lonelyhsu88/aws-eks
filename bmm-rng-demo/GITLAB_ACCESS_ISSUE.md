# GitLab Access Issue - Diagnosis Report

## 📊 Issue Summary

**BMM RNG Demo EC2** (43.199.231.220) 無法連接到 **GitLab 伺服器** (gitlab.ftgaming.cc / 16.162.37.5)

## ✅ 已完成配置

### 1. SSH Key 設定
- ✅ EC2 已產生 ED25519 SSH key pair
- ✅ Public key 已加入 GitLab（Deploy Key 或 User SSH Key）
- ✅ SSH config 已配置
- ✅ Git 全域設定完成

```
Public Key: ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINSRftNrHO0Y2GeCtZWnmZ5KMrdwEhcy7rrqzu/jNL9d bmm-rng-demo@ec2
```

### 2. EC2 Security Group
- ✅ Security Group: `bmm-rng-demo-sg` (sg-08acd8614eda7364f)
- ✅ Outbound rules: **允許所有對外流量** (0.0.0.0/0, all protocols)

## ❌ 問題診斷

### 網路連線測試結果

| 測試項目 | 結果 | 說明 |
|---------|------|------|
| ICMP (ping) | ❌ 失敗 | 100% packet loss |
| SSH port 22 | ❌ 關閉/被過濾 | Connection refused/timeout |
| Git clone | ❌ 失敗 | Cannot connect to host |

### 根本原因

**GitLab 伺服器端阻擋了連線**，可能原因：

1. **GitLab Security Group 未開放** (最可能)
   - GitLab 伺服器的 Security Group 沒有允許來自 `43.199.231.220` 的 inbound 連線
   - 或未開放 port 22 給外部 IP

2. **Network ACL 限制**
   - VPC Network ACL 可能阻擋了特定 IP 範圍

3. **不同 VPC 未連接**
   - 如果 BMM RNG EC2 和 GitLab 在不同 VPC，需要 VPC Peering 或 Transit Gateway

4. **GitLab 伺服器防火牆**
   - GitLab EC2 instance 內部可能有 iptables 或其他防火牆規則

## 🔧 解決方案

### 方案 A：修改 GitLab Security Group（推薦）

需要在 GitLab 伺服器的 Security Group 加入以下 inbound rule：

```bash
# 允許 BMM RNG EC2 存取 SSH
Protocol: TCP
Port: 22
Source: 43.199.231.220/32
Description: bmm-rng-demo EC2 access
```

或者，如果要允許整個子網：

```bash
# 查詢 BMM RNG EC2 的子網 CIDR
AWS_PROFILE=gemini-pro_ck aws ec2 describe-subnets \
  --region ap-east-1 \
  --filters "Name=subnet-id,Values=<subnet-id>" \
  --query 'Subnets[0].CidrBlock'

# 加入到 GitLab Security Group
Protocol: TCP
Port: 22
Source: <subnet-cidr>
Description: BMM RNG subnet access
```

### 方案 B：檢查並修改 Network ACL

如果 Security Group 已正確但仍無法連線，檢查 Network ACL：

```bash
# 查詢 GitLab VPC 的 Network ACL
aws ec2 describe-network-acls \
  --filters "Name=vpc-id,Values=<gitlab-vpc-id>" \
  --query 'NetworkAcls[*].{ID:NetworkAclId,Rules:Entries}'
```

確保 Network ACL 允許：
- Inbound: TCP port 22 from 43.199.231.220/32
- Outbound: TCP port 1024-65535 (ephemeral ports) to 43.199.231.220/32

### 方案 C：VPC Peering（如果是不同 VPC）

如果兩個 EC2 在不同 VPC，需要建立 VPC Peering：

```bash
# 創建 VPC Peering Connection
aws ec2 create-vpc-peering-connection \
  --vpc-id <bmm-rng-vpc-id> \
  --peer-vpc-id <gitlab-vpc-id>

# 接受 Peering Connection
aws ec2 accept-vpc-peering-connection \
  --vpc-peering-connection-id <pcx-id>

# 更新 Route Tables
# BMM RNG VPC route table
aws ec2 create-route \
  --route-table-id <bmm-rng-rtb-id> \
  --destination-cidr-block <gitlab-vpc-cidr> \
  --vpc-peering-connection-id <pcx-id>

# GitLab VPC route table
aws ec2 create-route \
  --route-table-id <gitlab-rtb-id> \
  --destination-cidr-block <bmm-rng-vpc-cidr> \
  --vpc-peering-connection-id <pcx-id>
```

## 📝 下一步操作

### 立即行動（需要人工介入）

1. **找出 GitLab 伺服器的 Security Group**
   - 登入 GitLab 伺服器所在的 AWS 帳號
   - 查詢 IP `16.162.37.5` 對應的 EC2 instance
   - 找到其 Security Group

2. **修改 GitLab Security Group**
   - 加入 inbound rule 允許 `43.199.231.220:22`
   - 或聯絡 GitLab 管理員協助開通

3. **測試連線**
   - 執行測試腳本：`./04-fix-gitlab-access.sh`
   - 或手動測試：
     ```bash
     ssh -i bmm-rng-demo-key.pem ec2-user@43.199.231.220
     ping 16.162.37.5
     git clone git@gitlab.ftgaming.cc:core/bmm-rng.git
     ```

### 備用方案

如果無法修改 GitLab Security Group：

1. **使用 HTTPS clone 而非 SSH**
   - 需要 GitLab Personal Access Token
   - Clone URL: `https://gitlab.ftgaming.cc/core/bmm-rng.git`

2. **透過跳板機（Bastion Host）**
   - 如果有可以存取 GitLab 的跳板機
   - 設定 SSH ProxyJump

3. **手動部署**
   - 在本機 clone repository
   - 使用 `scp` 上傳到 EC2

## 📂 相關檔案

- SSH Public Key: `scripts/gitlab-ssh-key.pub`
- Instance Info: `scripts/instance-info.txt`
- 診斷腳本: `scripts/04-fix-gitlab-access.sh`

## 🔗 參考資訊

- BMM RNG EC2: i-0eaf76aff3757cd17 (43.199.231.220)
- Region: ap-east-1 (Hong Kong)
- Security Group: sg-08acd8614eda7364f
- GitLab: gitlab.ftgaming.cc (16.162.37.5)
- Repository: git@gitlab.ftgaming.cc:core/bmm-rng.git
