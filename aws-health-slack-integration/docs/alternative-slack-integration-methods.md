# AWS 到 Slack 告警的替代方案

**日期**: 2025-12-20
**目的**: 分析所有可行的 AWS → Slack 告警整合方案

---

## 方案總覽

| 方案 | 複雜度 | 成本 | 彈性 | 維護 | 推薦指數 |
|------|--------|------|------|------|----------|
| **1. AWS Chatbot** | ⭐ | $0 | ⭐⭐ | ⭐ | ⭐⭐⭐⭐ |
| **2. EventBridge → Lambda → Slack** | ⭐⭐ | ~$0.05 | ⭐⭐⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐⭐⭐ |
| **3. SNS → Lambda → Slack** (已實作) | ⭐⭐ | ~$0.05 | ⭐⭐⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐⭐⭐ |
| **4. EventBridge API Destinations** | ⭐⭐ | ~$0.10 | ⭐⭐⭐ | ⭐ | ⭐⭐⭐⭐ |
| **5. CloudWatch Alarms → SNS → Chatbot** | ⭐ | $0 | ⭐⭐ | ⭐ | ⭐⭐⭐ |
| **6. SNS Email → Slack Email** | ⭐ | $0 | ⭐ | ⭐ | ⭐⭐ |
| **7. PagerDuty/Opsgenie** | ⭐⭐ | $9-19/user | ⭐⭐⭐⭐ | ⭐ | ⭐⭐⭐⭐ |
| **8. Datadog/New Relic** | ⭐⭐⭐ | $15+/host | ⭐⭐⭐⭐⭐ | ⭐ | ⭐⭐⭐ |

---

## 方案 1: AWS Chatbot (最簡單)

### 架構
```
AWS Health Event → EventBridge → SNS → AWS Chatbot → Slack
```

### 優點
- ✅ **零程式碼**: AWS 原生服務,完全託管
- ✅ **零維護**: AWS 自動更新和維護
- ✅ **零成本**: 完全免費
- ✅ **快速設定**: 5 分鐘內完成
- ✅ **多平台支援**: Slack + Microsoft Teams
- ✅ **內建安全**: IAM 角色整合

### 缺點
- ❌ **訊息格式固定**: 無法自訂樣式
- ❌ **功能有限**: 無法添加自訂邏輯
- ❌ **無事件過濾**: 無法在訊息層面做複雜過濾
- ❌ **無去重功能**: 可能收到重複通知

### 適用場景
- 快速原型驗證
- 不需要自訂訊息格式
- 團隊習慣 AWS 原生工具
- 預算極度受限

### 實作步驟

#### Step 1: 創建 AWS Chatbot 配置

```bash
# 方式 1: 透過 AWS Console (推薦,因為需要 OAuth)
# 1. 訪問: https://console.aws.amazon.com/chatbot/
# 2. Configure new client → Slack
# 3. 授權 AWS Chatbot 訪問你的 Slack workspace
# 4. 選擇頻道: #ops-alerts
# 5. 配置 IAM 角色和權限

# 方式 2: 透過 AWS CLI (需要先完成 OAuth)
aws chatbot create-slack-channel-configuration \
  --configuration-name "aws-health-alerts" \
  --iam-role-arn "arn:aws:iam::470013648166:role/AWSChatbotRole" \
  --slack-channel-id "C01234567890" \
  --slack-workspace-id "T01234567890" \
  --sns-topic-arns "arn:aws:sns:ap-east-1:470013648166:ops-alerts-aws-health" \
  --region ap-east-1
```

#### Step 2: 配置 EventBridge → SNS

```bash
# 使用現有的 SNS topic
SNS_TOPIC_ARN="arn:aws:sns:ap-east-1:470013648166:ops-alerts-aws-health"

# 創建 EventBridge 規則 (如果還沒有)
aws events put-rule \
  --name aws-health-to-chatbot \
  --event-pattern '{
    "source": ["aws.health"],
    "detail-type": ["AWS Health Event"]
  }' \
  --state ENABLED \
  --region ap-east-1

# 將 SNS 設為目標
aws events put-targets \
  --rule aws-health-to-chatbot \
  --targets "Id=1,Arn=$SNS_TOPIC_ARN" \
  --region ap-east-1
```

#### Step 3: 驗證

```bash
# 發送測試通知
aws sns publish \
  --topic-arn $SNS_TOPIC_ARN \
  --message "Test from AWS Chatbot" \
  --region ap-east-1
```

### Slack 訊息範例 (AWS Chatbot)

```
AWS Health Event
Service: EC2
Region: ap-east-1
Status: open
Description: A subset of EC2 instances were unavailable...

View Event | AWS Console
```

**訊息特點**:
- 簡潔明瞭但格式固定
- 自動包含 AWS Console 連結
- 可以直接從 Slack 執行 AWS CLI 命令 (如果配置了)

---

## 方案 2: EventBridge → Lambda → Slack (直接整合)

### 架構
```
AWS Health Event → EventBridge → Lambda → Slack Webhook
```

### 優點
- ✅ **更低延遲**: 少一層 SNS (減少 ~100ms)
- ✅ **完全自訂**: 訊息格式完全控制
- ✅ **簡化架構**: 少一個服務
- ✅ **成本略低**: 少一次 SNS 調用

### 缺點
- ❌ **缺少 fanout**: 無法輕鬆添加其他通知渠道 (email, PagerDuty)
- ❌ **需要手動重試**: SNS 提供的重試機制需自行實作

### 適用場景
- 只需要 Slack 通知 (不需要其他渠道)
- 追求極致低延遲
- 架構簡化優先

### 實作步驟

```bash
# 使用現有的 Lambda 函數
LAMBDA_ARN="arn:aws:lambda:ap-east-1:470013648166:function:AWSHealthToSlack"

# 創建 EventBridge 規則直接指向 Lambda
aws events put-rule \
  --name aws-health-to-slack-direct \
  --event-pattern '{
    "source": ["aws.health"],
    "detail-type": ["AWS Health Event"]
  }' \
  --state ENABLED \
  --region ap-east-1

# 添加 Lambda 為目標
aws events put-targets \
  --rule aws-health-to-slack-direct \
  --targets "Id=1,Arn=$LAMBDA_ARN" \
  --region ap-east-1

# 授予 EventBridge 調用 Lambda 的權限
aws lambda add-permission \
  --function-name AWSHealthToSlack \
  --statement-id AllowEventBridgeInvoke \
  --action lambda:InvokeFunction \
  --principal events.amazonaws.com \
  --source-arn arn:aws:events:ap-east-1:470013648166:rule/aws-health-to-slack-direct \
  --region ap-east-1
```

### Lambda 函數調整

```python
# 修改 lambda/index.py 以處理 EventBridge 事件

def lambda_handler(event, context):
    """
    處理來自 EventBridge 的直接調用
    """

    # EventBridge 直接調用時,event 就是 AWS Health event
    if 'Records' in event:
        # 來自 SNS
        sns_message = json.loads(event['Records'][0]['Sns']['Message'])
        health_event = sns_message
    else:
        # 來自 EventBridge
        health_event = event

    # 後續處理相同...
    detail = health_event.get('detail', {})
    # ...
```

---

## 方案 3: EventBridge API Destinations (無 Lambda)

### 架構
```
AWS Health Event → EventBridge → API Destination → Slack Webhook
```

### 優點
- ✅ **無 Lambda**: 不需要管理函數代碼
- ✅ **原生 HTTP**: EventBridge 直接發送 HTTP 請求
- ✅ **簡化部署**: 少一個服務
- ✅ **內建重試**: EventBridge 自動重試失敗請求

### 缺點
- ❌ **訊息轉換有限**: 只能用 Input Transformer (有限的格式化能力)
- ❌ **無複雜邏輯**: 無法執行條件判斷、過濾等
- ❌ **Debug 困難**: 無法像 Lambda 一樣查看詳細日誌

### 適用場景
- 訊息格式需求簡單
- 不想維護 Lambda 代碼
- 希望架構極簡

### 實作步驟

#### Step 1: 創建 API Destination Connection (存儲 Slack Webhook)

```bash
# 創建連接 (存儲 Slack Webhook URL)
aws events create-connection \
  --name slack-webhook-connection \
  --authorization-type API_KEY \
  --auth-parameters '{
    "ApiKeyAuthParameters": {
      "ApiKeyName": "Authorization",
      "ApiKeyValue": "Bearer YOUR_SLACK_WEBHOOK_TOKEN"
    }
  }' \
  --region ap-east-1
```

**注意**: Slack Webhook 不需要 Authorization header,所以我們用另一種方式:

```bash
# 更簡單的方式: 不使用 Connection,直接用 Webhook URL
# 創建 API Destination
aws events create-api-destination \
  --name slack-webhook-destination \
  --invocation-endpoint "https://hooks.slack.com/services/YOUR/WEBHOOK/PATH" \
  --http-method POST \
  --invocation-rate-limit-per-second 10 \
  --region ap-east-1
```

#### Step 2: 創建 EventBridge 規則並配置 Input Transformer

```bash
# 創建規則
aws events put-rule \
  --name aws-health-to-slack-api \
  --event-pattern '{
    "source": ["aws.health"],
    "detail-type": ["AWS Health Event"]
  }' \
  --state ENABLED \
  --region ap-east-1

# 創建 Input Transformer (將 AWS Health 事件轉換為 Slack 格式)
cat > /tmp/input-transformer.json <<'EOF'
{
  "InputPathsMap": {
    "service": "$.detail.service",
    "eventTypeCode": "$.detail.eventTypeCode",
    "region": "$.region",
    "description": "$.detail.eventDescription[0].latestDescription"
  },
  "InputTemplate": "{\"text\":\"🚨 AWS Health Alert\",\"blocks\":[{\"type\":\"header\",\"text\":{\"type\":\"plain_text\",\"text\":\"🚨 AWS Health Alert\"}},{\"type\":\"section\",\"fields\":[{\"type\":\"mrkdwn\",\"text\":\"*Service:*\\n<service>\"},{\"type\":\"mrkdwn\",\"text\":\"*Region:*\\n<region>\"}]},{\"type\":\"section\",\"text\":{\"type\":\"mrkdwn\",\"text\":\"*Event:* <eventTypeCode>\\n\\n<description>\"}}]}"
}
EOF

# 添加目標 (API Destination)
API_DEST_ARN=$(aws events describe-api-destination \
  --name slack-webhook-destination \
  --region ap-east-1 \
  --query 'ApiDestinationArn' \
  --output text)

# 創建 IAM 角色讓 EventBridge 調用 API Destination
cat > /tmp/eventbridge-trust.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "events.amazonaws.com"},
    "Action": "sts:AssumeRole"
  }]
}
EOF

ROLE_ARN=$(aws iam create-role \
  --role-name EventBridgeAPIDestinationRole \
  --assume-role-policy-document file:///tmp/eventbridge-trust.json \
  --query 'Role.Arn' \
  --output text)

# 附加權限
cat > /tmp/eventbridge-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["events:InvokeApiDestination"],
    "Resource": "$API_DEST_ARN"
  }]
}
EOF

aws iam put-role-policy \
  --role-name EventBridgeAPIDestinationRole \
  --policy-name InvokeAPIDestination \
  --policy-document file:///tmp/eventbridge-policy.json

# 添加目標
aws events put-targets \
  --rule aws-health-to-slack-api \
  --targets '[{
    "Id": "1",
    "Arn": "'$API_DEST_ARN'",
    "RoleArn": "'$ROLE_ARN'",
    "HttpParameters": {
      "HeaderParameters": {
        "Content-Type": "application/json"
      }
    },
    "InputTransformer": {
      "InputPathsMap": {
        "service": "$.detail.service",
        "eventTypeCode": "$.detail.eventTypeCode",
        "region": "$.region",
        "description": "$.detail.eventDescription[0].latestDescription"
      },
      "InputTemplate": "{\"text\":\"🚨 AWS Health Alert from <service> in <region>\",\"blocks\":[{\"type\":\"section\",\"text\":{\"type\":\"mrkdwn\",\"text\":\"*Event:* <eventTypeCode>\\n<description>\"}}]}"
    }
  }]' \
  --region ap-east-1
```

### 限制

**Input Transformer 限制**:
- 最多 100 個變數
- 輸出最大 8192 字符
- 無法執行條件邏輯
- 無法調用外部 API

---

## 方案 4: CloudWatch Alarms → SNS → Chatbot

### 架構
```
CloudWatch Alarms → SNS → AWS Chatbot → Slack
```

### 優點
- ✅ **原生整合**: CloudWatch + Chatbot 原生支援
- ✅ **豐富的告警**: CPU, Memory, 自訂指標
- ✅ **零程式碼**: 完全透過 Console/CLI 配置

### 缺點
- ❌ **僅限 CloudWatch**: 無法處理 AWS Health Events
- ❌ **需要額外配置**: 每個告警都要單獨設定

### 適用場景
- 監控 EKS/EC2 資源指標
- 補充 AWS Health 事件告警
- 需要閾值觸發的告警

### 實作步驟

```bash
# 創建 CloudWatch 告警
aws cloudwatch put-metric-alarm \
  --alarm-name eks-node-cpu-high \
  --alarm-description "EKS node CPU usage > 80%" \
  --metric-name CPUUtilization \
  --namespace AWS/EC2 \
  --statistic Average \
  --period 300 \
  --evaluation-periods 2 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --alarm-actions arn:aws:sns:ap-east-1:470013648166:ops-alerts \
  --region ap-east-1

# SNS topic 已連接到 AWS Chatbot
# 告警會自動發送到 Slack
```

---

## 方案 5: SNS Email → Slack Email Integration

### 架構
```
AWS Health → EventBridge → SNS (Email) → Slack Email Address
```

### 優點
- ✅ **超級簡單**: 只需要 Slack email integration
- ✅ **零設定**: 不需要 Lambda 或 Chatbot

### 缺點
- ❌ **訊息格式差**: 純文字 email,沒有格式
- ❌ **無法自訂**: 完全依賴 SNS email 格式
- ❌ **延遲較高**: Email 轉發有額外延遲
- ❌ **功能有限**: 無法添加按鈕、顏色等

### 適用場景
- 極簡快速原型
- 不需要任何格式化
- 臨時解決方案

### 實作步驟

```bash
# 1. 在 Slack 中獲取 email integration 地址
# Settings → Apps → Email → Get Email Address
# 例如: 12345abcde@your-workspace.slack.com

# 2. 訂閱 SNS topic
aws sns subscribe \
  --topic-arn arn:aws:sns:ap-east-1:470013648166:ops-alerts-aws-health \
  --protocol email \
  --notification-endpoint "12345abcde@your-workspace.slack.com" \
  --region ap-east-1

# 3. 確認訂閱 (Slack 會收到確認郵件,點擊確認連結)
```

---

## 方案 6: PagerDuty / Opsgenie (第三方)

### 架構
```
AWS Health → EventBridge → SNS → PagerDuty/Opsgenie → Slack
```

### 優點
- ✅ **專業 On-Call**: 輪班管理、升級流程
- ✅ **豐富整合**: Slack + Email + SMS + 電話
- ✅ **事件管理**: 完整的 incident lifecycle
- ✅ **分析報告**: 詳細的事件統計
- ✅ **自動化**: Runbook automation

### 缺點
- ❌ **額外成本**: $9-19/user/月
- ❌ **學習曲線**: 需要培訓團隊
- ❌ **外部依賴**: 依賴第三方服務

### 適用場景
- 需要 On-Call 輪班機制
- 多層級告警升級
- 大型團隊協作
- 預算充足

### PagerDuty 實作步驟

```bash
# 1. 在 PagerDuty 創建 Integration
# Services → Your Service → Integrations → Add Integration
# Integration Type: Amazon CloudWatch
# 複製 Integration Key

# 2. 安裝 PagerDuty AWS Integration
# https://www.pagerduty.com/docs/guides/aws-integration-guide/

# 3. 配置 SNS 訂閱
PAGERDUTY_ENDPOINT="https://events.pagerduty.com/integration/YOUR_INTEGRATION_KEY/enqueue"

# 創建 HTTPS 訂閱 (PagerDuty 提供的 endpoint)
aws sns subscribe \
  --topic-arn arn:aws:sns:ap-east-1:470013648166:ops-alerts-aws-health \
  --protocol https \
  --notification-endpoint "$PAGERDUTY_ENDPOINT" \
  --region ap-east-1

# 4. 在 PagerDuty 配置 Slack integration
# Extensions → Slack → Add to Service
```

---

## 方案 7: Datadog / New Relic (全方位監控)

### 架構
```
AWS Health → Datadog/New Relic (Agent) → Slack
CloudWatch Metrics → Datadog/New Relic → Slack
Application Logs → Datadog/New Relic → Slack
```

### 優點
- ✅ **統一監控**: Logs + Metrics + Traces + Events
- ✅ **強大分析**: Dashboard, Alerting, APM
- ✅ **自動發現**: 自動監控 AWS 資源
- ✅ **AI 異常檢測**: 機器學習告警

### 缺點
- ❌ **高成本**: $15-100+/host/月
- ❌ **複雜設定**: 需要專人維護
- ❌ **過度工程**: 對於簡單需求可能太重

### 適用場景
- 已使用 Datadog/New Relic
- 需要全方位可觀測性
- 大型複雜系統
- 預算充足

---

## 方案比較和選擇指南

### 快速決策樹

```
需要 On-Call 輪班嗎?
├─ 是 → PagerDuty / Opsgenie
└─ 否 → 需要自訂訊息格式嗎?
    ├─ 是 → 需要多通知渠道嗎?
    │   ├─ 是 → SNS + Lambda (已實作)
    │   └─ 否 → EventBridge + Lambda (方案 2)
    └─ 否 → 追求極簡嗎?
        ├─ 是 → AWS Chatbot (方案 1)
        └─ 否 → API Destinations (方案 3)
```

### 依需求選擇

| 需求 | 推薦方案 |
|------|----------|
| **最快速部署** | AWS Chatbot |
| **完全免費** | AWS Chatbot 或 Email Integration |
| **最彈性** | SNS + Lambda (已實作) |
| **最低延遲** | EventBridge + Lambda |
| **On-Call 管理** | PagerDuty/Opsgenie |
| **全方位監控** | Datadog/New Relic |
| **最簡架構** | API Destinations |
| **多通知渠道** | SNS + Lambda |

### 成本比較 (月費)

| 方案 | 10 events/月 | 100 events/月 | 1000 events/月 |
|------|--------------|---------------|----------------|
| AWS Chatbot | $0 | $0 | $0 |
| Lambda + SNS | $0.03 | $0.10 | $0.50 |
| API Destinations | $0.05 | $0.20 | $1.00 |
| PagerDuty | $9/user | $9/user | $9/user |
| Datadog | $15/host | $15/host | $15/host |

---

## 混合方案 (推薦)

### 多層級告警策略

```
Critical (P0/P1):
  AWS Health → SNS → Lambda → Slack (@channel)
                    └→ PagerDuty → On-Call Engineer

Warning (P2/P3):
  CloudWatch Alarms → SNS → AWS Chatbot → Slack (no mention)

Info (P4):
  Application Logs → CloudWatch → Email
```

### 實作範例

```bash
# 1. Critical 告警: 使用現有 Lambda + 添加 PagerDuty
aws sns subscribe \
  --topic-arn arn:aws:sns:ap-east-1:470013648166:ops-alerts-aws-health \
  --protocol https \
  --notification-endpoint "$PAGERDUTY_CRITICAL_ENDPOINT" \
  --region ap-east-1

# 2. Warning 告警: 使用 AWS Chatbot
aws chatbot create-slack-channel-configuration \
  --configuration-name "aws-warnings" \
  --slack-channel-id "C-WARNINGS" \
  --sns-topic-arns "arn:aws:sns:ap-east-1:470013648166:ops-warnings"

# 3. 在 Lambda 中根據嚴重性路由
def lambda_handler(event, context):
    severity = get_event_severity(event)

    if severity in ['critical', 'high']:
        send_to_slack_with_mention(event)  # @channel
        send_to_pagerduty(event)
    elif severity == 'medium':
        send_to_slack_no_mention(event)
    else:
        send_to_email(event)
```

---

## 總結和建議

### 當前方案 (SNS + Lambda)
✅ **保留**: 這是最佳平衡方案
- 完全控制訊息格式
- 支援多通知渠道
- 成本極低
- 易於擴展

### 可考慮添加

1. **AWS Chatbot** (補充方案)
   - 用於非關鍵告警 (Warning, Info)
   - 零成本,零維護
   - 快速設定

2. **PagerDuty** (未來升級)
   - 當團隊擴大需要 On-Call 輪班時
   - 可與現有 SNS 整合
   - 漸進式引入

3. **API Destinations** (備選)
   - 如果不想維護 Lambda 代碼
   - 訊息格式需求簡單時

### 不推薦

- ❌ Email Integration: 格式差,延遲高
- ❌ Datadog/New Relic: 成本過高,除非已使用

---

## 快速開始指南

### 添加 AWS Chatbot (5 分鐘)

```bash
# 1. 訪問 AWS Chatbot Console
open https://console.aws.amazon.com/chatbot/

# 2. Configure Slack
# - 授權 workspace
# - 選擇 #ops-alerts-warning 頻道
# - 添加現有 SNS topic

# 3. 測試
aws sns publish \
  --topic-arn arn:aws:sns:ap-east-1:470013648166:ops-alerts-aws-health \
  --message "Test AWS Chatbot" \
  --region ap-east-1
```

### 切換到 API Destinations (15 分鐘)

參考上方「方案 3」的詳細步驟

---

**文檔版本**: 1.0
**最後更新**: 2025-12-20
**下次審查**: 2026-01-20
