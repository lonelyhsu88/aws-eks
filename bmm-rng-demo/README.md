# BMM RNG Demo

BMM 認證審核用的 RNG 演示環境。

## 檔案說明

| 檔案 | 用途 |
|------|------|
| `app.py` | FastAPI Web 應用程式（含測試 UI） |
| `Dockerfile` | Docker 映像檔配置 |
| `docker-compose.yml` | Docker Compose 配置 |
| `nginx.conf` | Nginx HTTPS 反向代理配置 |

## 部署流程

### 準備階段（審核前）

```bash
cd scripts/

# 1. 建立 EC2 實例和 Key Pair
./01-create-ec2.sh

# 2. 設定 DNS（手動）
# bmm.geminigame.cc -> EC2 Public IP

# 3. 設定 SSL 憑證
./02-setup-ssl.sh
```

### 審核當天（BMM 審計人員觀看時）

```bash
cd scripts/

# 執行部署腳本，會顯示完整的 checksum 驗證過程
./03-deploy-audit.sh
```

## Checksum 驗證

BMM_RNG.py 的 SHA256 checksum：
```
01e8759d536499b3be1fce50719e685c454fa8663ad24b92f0e213b43dac83c3
```

## 測試 URL

- 網頁介面：https://bmm.geminigame.cc
- API 狀態：https://bmm.geminigame.cc/api/status

## 支援的遊戲

1. **Gem Game** - 寶石抽取
2. **Egypt Hilo** - 埃及高低牌
3. **Forest Tea Party** - 森林茶會
4. **Lucky Drop COCO2** - 幸運掉落
5. **Multi Hilo** - 多重高低牌

## RNG 模式

- **System RNG**：使用系統 CSPRNG（生產用）
- **Deterministic**：使用 HMAC-DRBG（可重現，審計用）
