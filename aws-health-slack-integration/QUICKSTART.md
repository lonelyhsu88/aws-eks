# Quick Start Guide

快速部署 AWS Health 到 Slack 實時告警系統

## 前置需求

- ✅ AWS CLI 已配置 (ap-east-1 region)
- ✅ Slack workspace 管理員權限
- ✅ 5-10 分鐘時間

## 3 步驟完成部署

### 步驟 1: 設置 Slack Webhook (2 分鐘)

```bash
# 1. 訪問 Slack API
open https://api.slack.com/apps

# 2. 創建新應用
# - Create New App → From scratch
# - App Name: "AWS Health Alerts"
# - 選擇你的 workspace

# 3. 啟用 Incoming Webhooks
# - Features → Incoming Webhooks → Activate

# 4. 添加 Webhook 到 #ops-alerts 頻道
# - Add New Webhook to Workspace
# - 選擇頻道: #ops-alerts
# - 複製 Webhook URL (類似: https://hooks.slack.com/services/...)
```

### 步驟 2: 配置專案 (1 分鐘)

```bash
# 進入專案目錄
cd aws-health-slack-integration

# 複製配置範本
cp config/config.sh.example config/config.sh

# 編輯配置檔案,填入你的 Slack Webhook URL
vim config/config.sh
# 或使用你喜歡的編輯器:
# code config/config.sh  # VS Code
# nano config/config.sh  # Nano
```

**必要設定** (在 `config/config.sh` 中):
```bash
SLACK_WEBHOOK_URL="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"  # 修改這行
```

### 步驟 3: 部署和測試 (3-5 分鐘)

```bash
# 自動部署所有資源
./scripts/deploy.sh

# 測試整合
./scripts/test.sh

# 檢查 Slack 頻道 #ops-alerts
# 你應該會看到 2 則測試訊息
```

## 驗證部署成功

✅ **部署腳本顯示綠色勾選標記**
```
✓ SNS topic verified
✓ Lambda function verified
✓ EventBridge rule verified
✓ SNS subscription verified (Active)
```

✅ **測試腳本執行成功**
```
✓ Slack webhook is reachable (HTTP 200)
✓ Lambda function executed successfully
✓ Test event published to SNS
```

✅ **Slack 頻道收到測試訊息**
- 訊息包含 🚨 AWS Health Alert 標題
- 顯示事件類型、服務、區域等資訊
- 有兩個操作按鈕 (AWS Health Dashboard, Runbook)

## 常見問題

### Q: 沒有收到 Slack 訊息?

**檢查清單**:
```bash
# 1. 驗證 Webhook URL
curl -X POST -H 'Content-Type: application/json' \
  -d '{"text": "Test"}' \
  YOUR_WEBHOOK_URL

# 2. 檢查 Lambda 日誌
aws logs tail /aws/lambda/AWSHealthToSlack --follow --region ap-east-1

# 3. 驗證 SNS 訂閱狀態
aws sns list-subscriptions --region ap-east-1 | grep AWSHealthToSlack
```

### Q: 如何監控系統運作?

```bash
# 即時查看 Lambda 日誌
aws logs tail /aws/lambda/AWSHealthToSlack --follow --region ap-east-1

# 查看最近 1 小時的錯誤
aws logs filter-log-events \
  --log-group-name /aws/lambda/AWSHealthToSlack \
  --filter-pattern "ERROR" \
  --start-time $(($(date +%s) - 3600))000 \
  --region ap-east-1
```

### Q: 如何移除所有資源?

```bash
./scripts/cleanup.sh
# 確認輸入 "yes" 來刪除所有資源
```

## 成本預估

| 項目 | 月成本 |
|------|--------|
| EventBridge | $0.00 (免費額度) |
| SNS | $0.00 (免費額度) |
| Lambda | $0.00 (免費額度) |
| CloudWatch Logs | ~$0.03 |
| **總計** | **~$0.03-0.10/月** |

## 下一步

1. **自訂訊息格式**: 編輯 `lambda/index.py` 調整 Slack 訊息樣式
2. **擴展監控服務**: 修改 `config/event-pattern.json` 添加更多 AWS 服務
3. **設置告警**: 啟用 CloudWatch 告警監控 Lambda 錯誤
4. **整合 PagerDuty**: 添加額外的 SNS 訂閱實現 on-call 輪班

## 需要幫助?

- 📖 **詳細文檔**: [docs/aws-health-slack-integration-guide.md](docs/aws-health-slack-integration-guide.md)
- 🔧 **故障排除**: 查看上方常見問題或詳細文檔的 Troubleshooting 章節
- 💬 **Slack 支援**: #ops-alerts, #devops

---

**預計總時間**: 5-10 分鐘
**技術難度**: ⭐⭐ (中等)
**維護需求**: ⭐ (極低)
