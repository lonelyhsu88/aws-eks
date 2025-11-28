# BMM RNG Demo 工作紀錄

## 專案概述

**目的**：為 BMM 認證審核建立 RNG 演示環境，讓審計人員可以線上觀看部署過程並測試遊戲隨機數生成器。

**Jira Ticket**：[OPS-856](https://jira.ftgaming.cc/browse/OPS-856)

---

## EC2 基本資訊

| 項目 | 值 |
|------|-----|
| **Instance ID** | `i-0eaf76aff3757cd17` |
| **Instance Name** | `rng-game-srv01` |
| **Public IP** | `43.199.231.220` |
| **Region** | ap-east-1 (Hong Kong) |
| **Instance Type** | t3.small |
| **Security Group** | `sg-08acd8614eda7364f` |
| **Key Pair** | `bmm-rng-demo-key` |
| **AWS Profile** | `gemini-pro_ck` |

---

## Security Group 規則

所有端口限制為指定 IP 才能存取（已移除 0.0.0.0/0）：

| Port | 用途 | 允許的 IP |
|------|------|----------|
| 22 | SSH | 1.34.41.245, 16.162.117.249, 18.167.236.110, 61.218.59.85 |
| 80 | HTTP | 1.34.41.245, 16.162.117.249, 18.167.236.110, 61.218.59.85 |
| 443 | HTTPS | 1.34.41.245, 16.162.117.249, 18.167.236.110, 61.218.59.85 |
| 8000 | FastAPI | 1.34.41.245, 16.162.117.249, 18.167.236.110, 61.218.59.85 |

---

## BMM_RNG.py 資訊

| 項目 | 值 |
|------|-----|
| **來源路徑** | `/Users/lonelyhsu/Downloads/BMM_RNG.py` |
| **SHA256 Checksum** | `01e8759d536499b3be1fce50719e685c454fa8663ad24b92f0e213b43dac83c3` |
| **版本** | 1.0.0 |
| **RNG 模式** | SystemRNG (生產), HMACDRBG (審核重現) |

### 支援遊戲
- Gem Game (寶石抽取)
- Egypt Hilo (埃及高低牌)
- Forest Tea Party (森林茶會)
- Lucky Drop COCO2 (幸運掉落)
- Multi Hilo (多重高低牌)

---

## 專案結構

### 本地路徑
```
/Users/lonelyhsu/gemini/claude-project/aws-eks/bmm-rng-demo/
├── app.py                    # FastAPI 應用程式 + Web UI
├── Dockerfile                # Docker 配置（含 sha256sum）
├── docker-compose.yml        # 編排配置（含 nginx）
├── nginx.conf                # HTTPS 反向代理
├── requirements.txt          # Python 依賴
├── README.md                 # 說明文件
├── WORK_LOG.md               # 本工作紀錄
└── scripts/
    ├── 01-create-ec2.sh      # 建立 EC2（已執行）
    ├── 02-setup-ssl.sh       # 設定 SSL 憑證
    ├── 03-deploy-audit.sh    # BMM 審核當天部署腳本
    ├── bmm-rng-demo-key.pem  # SSH 金鑰
    └── instance-info.txt     # EC2 資訊
```

### EC2 路徑
```
/home/ec2-user/bmm-rng-demo/
├── app.py           # FastAPI 應用程式
├── Dockerfile       # Docker 配置
├── BMM_RNG.py       # RNG 核心模組（部署時上傳）
├── requirements.txt # Python 依賴
└── start.sh         # 啟動腳本
```

---

## 部署方式

### 方法一：使用啟動腳本（推薦）

```bash
# SSH 進入伺服器
ssh -i scripts/bmm-rng-demo-key.pem ec2-user@43.199.231.220

# 執行啟動腳本
cd /home/ec2-user/bmm-rng-demo
./start.sh
```

### 方法二：手動部署

```bash
# 1. 計算本地 checksum
shasum -a 256 /Users/lonelyhsu/Downloads/BMM_RNG.py

# 2. 上傳 BMM_RNG.py 到 EC2
scp -i scripts/bmm-rng-demo-key.pem \
    /Users/lonelyhsu/Downloads/BMM_RNG.py \
    ec2-user@43.199.231.220:/home/ec2-user/bmm-rng-demo/

# 3. SSH 進入伺服器
ssh -i scripts/bmm-rng-demo-key.pem ec2-user@43.199.231.220

# 4. 驗證遠端 checksum
sha256sum /home/ec2-user/bmm-rng-demo/BMM_RNG.py

# 5. 執行啟動腳本
cd /home/ec2-user/bmm-rng-demo
./start.sh
```

### 方法三：BMM 審核當天（本地執行）

```bash
cd /Users/lonelyhsu/gemini/claude-project/aws-eks/bmm-rng-demo/scripts
./03-deploy-audit.sh
```

---

## 測試 URL

```
http://43.199.231.220:8000
```

---

## UI 變更記錄

| 原本 | 修改後 |
|------|--------|
| `BMM RNG Demo - Gemini Gaming` | `RNG GAME` |
| `BMM RNG Demo` (標題) | `RNG GAME` |
| `BMM-Compliant Random Number Generator Demonstration` | (已移除) |
| `BMM RNG Demo v1.0.0 \| Gemini Gaming \| For Audit Purpose Only` | (已移除) |

---

## 主機設定

### Hostname
```
rng-game-srv01
```

### 歷史記錄
已禁用 bash history（審計安全考量）：
- `HISTFILE` unset
- `HISTSIZE=0`
- `HISTFILESIZE=0`

---

## 常用指令

### SSH 連線
```bash
ssh -i /Users/lonelyhsu/gemini/claude-project/aws-eks/bmm-rng-demo/scripts/bmm-rng-demo-key.pem ec2-user@43.199.231.220
```

### 查看容器狀態
```bash
docker ps
docker logs bmm-rng-demo
```

### 驗證 checksum
```bash
docker exec bmm-rng-demo sha256sum /app/BMM_RNG.py
```

### 重啟容器
```bash
cd /home/ec2-user/bmm-rng-demo
./start.sh
```

---

## AWS CLI 指令參考

### Security Group 操作
```bash
# 新增 IP
aws ec2 authorize-security-group-ingress \
  --profile gemini-pro_ck \
  --region ap-east-1 \
  --group-id sg-08acd8614eda7364f \
  --protocol tcp \
  --port 22 \
  --cidr x.x.x.x/32

# 移除 IP
aws ec2 revoke-security-group-ingress \
  --profile gemini-pro_ck \
  --region ap-east-1 \
  --group-id sg-08acd8614eda7364f \
  --protocol tcp \
  --port 22 \
  --cidr x.x.x.x/32
```

### EC2 操作
```bash
# 查看實例狀態
aws ec2 describe-instances \
  --profile gemini-pro_ck \
  --region ap-east-1 \
  --instance-ids i-0eaf76aff3757cd17

# 更新 Name tag
aws ec2 create-tags \
  --profile gemini-pro_ck \
  --region ap-east-1 \
  --resources i-0eaf76aff3757cd17 \
  --tags Key=Name,Value=rng-game-srv01
```

---

## Jira API 參考

```python
JIRA_URL = "https://jira.ftgaming.cc"
JIRA_TOKEN = "<your-jira-token>"  # Get from MCP config

headers = {
    "Authorization": f"Bearer {JIRA_TOKEN}",
    "Content-Type": "application/json"
}
```

**注意**：Jira 使用 Bearer 認證，不是 Basic auth。Token 請參考 `~/.config/claude-code/mcp_servers.json`。

---

## 建立日期
2024-11-28
