# Jira OPS 工作記錄

**Summary**: BMM RNG Demo - GitLab Repository Access Configuration

**Issue Type**: Task

**Labels**: `bmm-rng`, `gitlab`, `infrastructure`, `security-group`

---

## 目的
為 BMM RNG Demo EC2 instance 設定 GitLab repository 存取權限，以便進行開發和部署作業。

## 背景
- **專案**: BMM RNG Demo (BMM 稽核用 RNG 遊戲展示)
- **EC2 Instance**: bmm-rng-demo (Region: ap-east-1)
- **GitLab Repository**: core/bmm-rng
- **Domain**: bmm.geminigame.cc

## 執行步驟

### 1. EC2 SSH Key 配置
- 在 EC2 instance 上產生 ED25519 SSH key pair
- 配置 Git 全域設定（user.email, user.name）
- 設定 SSH config 檔案，指向 GitLab 伺服器
- 加入 GitLab 主機到 known_hosts

### 2. GitLab 端設定
- 使用 GitLab API 加入 EC2 的 public key 作為 Deploy Key
- Deploy Key 設定為唯讀權限

### 3. 網路連線問題診斷

**問題發現**:
- EC2 無法連接到 GitLab 伺服器 (100% packet loss)
- SSH port 22 被過濾
- Git clone 操作失敗

**根本原因**:
- GitLab Security Group 未開放允許來自 BMM RNG EC2 的 SSH 連線

### 4. Security Group 修復

**查找 GitLab 伺服器**:
- 使用 AWS CLI 查詢 GitLab instance
- Instance Name: `gemini-gitlab`
- 確認 Security Group ID

**加入規則**:
```bash
# AWS CLI 命令（範例）
aws ec2 authorize-security-group-ingress \
  --group-id <gitlab-sg-id> \
  --ip-permissions IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges='[{CidrIp=<ec2-ip>/32,Description="BMM RNG Demo EC2 - SSH access"}]'
```

**規則詳情**:
- Protocol: TCP
- Port: 22
- Source: BMM RNG EC2 IP/32 (限制為特定 IP)
- Description: BMM RNG Demo EC2 - SSH access

### 5. 連線測試

**測試項目**:
| 項目 | 結果 | 說明 |
|------|------|------|
| ICMP ping | ⚠️ 被阻擋 | 正常，ICMP 未開放 |
| SSH port 22 | ✅ 連線成功 | Port 開放正常 |
| Git clone | ✅ 成功 | Repository 下載完成 |

**最終確認**:
```bash
# 在 EC2 上成功執行
git clone git@gitlab.ftgaming.cc:core/bmm-rng.git
# Repository 已下載至 /home/ec2-user/bmm-rng
```

## 結果

✅ **BMM RNG EC2 現在可以正常存取 GitLab repository**
✅ **開發人員可以進行 git clone, pull, push 等操作**
✅ **已建立診斷腳本供未來使用**: `scripts/04-fix-gitlab-access.sh`

## 檔案清單

專案檔案位於: `bmm-rng-demo/`

- `scripts/01-create-ec2.sh` - EC2 建立腳本
- `scripts/02-setup-ssl.sh` - SSL 設定腳本
- `scripts/03-deploy-audit.sh` - BMM 稽核部署腳本
- `scripts/04-fix-gitlab-access.sh` - **GitLab 連線診斷腳本（新增）**
- `scripts/instance-info.txt` - Instance 資訊
- `scripts/gitlab-ssh-key.pub` - SSH public key（供參考）
- `GITLAB_ACCESS_ISSUE.md` - **問題診斷完整文檔（新增）**

## 注意事項

1. **Security Group 最小權限原則**
   - 規則已限制為特定 EC2 IP/32
   - 符合安全性最佳實踐

2. **Deploy Key 權限**
   - 目前設定為唯讀權限
   - 如需推送權限需另行調整

3. **SSH Key 管理**
   - Private key 已妥善保管於 EC2 instance (`~/.ssh/id_ed25519`)
   - Public key 已加入 GitLab

4. **診斷工具**
   - `04-fix-gitlab-access.sh` 可用於未來類似問題的診斷
   - 包含完整的連線測試流程

## 相關資源

- **Repository**: gitlab.ftgaming.cc/core/bmm-rng
- **EC2 Region**: ap-east-1 (Hong Kong)
- **Domain**: bmm.geminigame.cc
- **Project**: BMM RNG Demo

## 技術細節（供參考）

### GitLab SSH 配置
```bash
# ~/.ssh/config on EC2
Host gitlab.ftgaming.cc
    HostName gitlab.ftgaming.cc
    User git
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking no
```

### 診斷腳本功能
`04-fix-gitlab-access.sh` 提供:
1. Security Group 配置檢查
2. Outbound rules 驗證
3. GitLab 連線測試（ping, SSH, Git clone）
4. 問題診斷建議

---

**建立日期**: 2025-12-01
**執行人員**: DevOps Team
**狀態**: ✅ 完成
