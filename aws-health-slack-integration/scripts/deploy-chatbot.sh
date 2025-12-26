#!/bin/bash
#
# AWS Chatbot Alternative Deployment
# 最簡單的 Slack 整合方案 (零程式碼)
#
# Usage: ./scripts/deploy-chatbot.sh
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Load configuration
CONFIG_FILE="$PROJECT_DIR/config/config.sh"
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}ERROR: Configuration file not found: $CONFIG_FILE${NC}"
    exit 1
fi

source "$CONFIG_FILE"

# Print banner
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}AWS Chatbot Deployment${NC}"
echo -e "${GREEN}零程式碼 Slack 整合方案${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Warning about OAuth requirement
echo -e "${YELLOW}注意事項:${NC}"
echo "AWS Chatbot 需要透過 AWS Console 進行 Slack OAuth 授權"
echo "此腳本將:"
echo "  1. 創建/確認 SNS topic"
echo "  2. 配置 EventBridge rule"
echo "  3. 提供 AWS Chatbot 設定指引"
echo ""
echo "你需要手動完成:"
echo "  1. AWS Console 中配置 Slack OAuth"
echo "  2. 選擇 Slack 頻道"
echo "  3. 配置 IAM 角色"
echo ""

read -p "是否繼續? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Deployment cancelled${NC}"
    exit 0
fi

# ============================================
# Step 1: Create/Verify SNS Topic
# ============================================
echo ""
echo -e "${YELLOW}[1/3] Creating/Verifying SNS Topic...${NC}"

SNS_TOPIC_ARN=$(aws sns create-topic \
  --name "$SNS_TOPIC_NAME" \
  --region "$AWS_REGION" \
  --tags "Key=Purpose,Value=AWS-Health-Alerts" "Key=ManagedBy,Value=DevOps" \
  --query 'TopicArn' \
  --output text 2>/dev/null || \
  aws sns list-topics --region "$AWS_REGION" --query "Topics[?contains(TopicArn, '$SNS_TOPIC_NAME')].TopicArn" --output text)

if [ -z "$SNS_TOPIC_ARN" ]; then
    echo -e "${RED}ERROR: Failed to create SNS topic${NC}"
    exit 1
fi

echo -e "${GREEN}✓ SNS Topic: $SNS_TOPIC_ARN${NC}"

# Configure SNS access policy for EventBridge
aws sns set-topic-attributes \
  --topic-arn "$SNS_TOPIC_ARN" \
  --attribute-name Policy \
  --attribute-value "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [{
      \"Effect\": \"Allow\",
      \"Principal\": {\"Service\": \"events.amazonaws.com\"},
      \"Action\": \"SNS:Publish\",
      \"Resource\": \"$SNS_TOPIC_ARN\"
    }]
  }" \
  --region "$AWS_REGION"

echo -e "${GREEN}✓ SNS access policy configured${NC}"

# ============================================
# Step 2: Create EventBridge Rule
# ============================================
echo ""
echo -e "${YELLOW}[2/3] Creating EventBridge Rule...${NC}"

aws events put-rule \
  --name "${EVENTBRIDGE_RULE_NAME}-chatbot" \
  --description "Route AWS Health events to Slack via SNS and AWS Chatbot" \
  --event-pattern "file://$PROJECT_DIR/config/event-pattern.json" \
  --state ENABLED \
  --region "$AWS_REGION" \
  --tags "Key=Purpose,Value=AWS-Health-Alerts" "Key=ManagedBy,Value=DevOps"

echo -e "${GREEN}✓ EventBridge Rule: ${EVENTBRIDGE_RULE_NAME}-chatbot${NC}"

# Add SNS topic as target
aws events put-targets \
  --rule "${EVENTBRIDGE_RULE_NAME}-chatbot" \
  --targets "Id=1,Arn=$SNS_TOPIC_ARN" \
  --region "$AWS_REGION"

echo -e "${GREEN}✓ SNS topic added as target${NC}"

# ============================================
# Step 3: AWS Chatbot Configuration Guide
# ============================================
echo ""
echo -e "${YELLOW}[3/3] AWS Chatbot Configuration Instructions${NC}"
echo ""
echo -e "${BLUE}請按照以下步驟在 AWS Console 配置 Chatbot:${NC}"
echo ""
echo "1️⃣  訪問 AWS Chatbot Console:"
echo "   https://console.aws.amazon.com/chatbot/"
echo ""
echo "2️⃣  點擊 'Configure new client'"
echo "   - 選擇 'Slack'"
echo "   - 點擊 'Configure client'"
echo ""
echo "3️⃣  授權 Slack workspace"
echo "   - 登入你的 Slack workspace"
echo "   - 點擊 'Allow' 授權 AWS Chatbot"
echo ""
echo "4️⃣  配置 Slack channel"
echo "   - Configuration name: aws-health-alerts"
echo "   - Slack channel: $SLACK_CHANNEL"
echo "   - IAM role: 可選擇創建新角色或使用現有角色"
echo ""
echo "5️⃣  配置通知"
echo "   - Region: $AWS_REGION"
echo "   - SNS topics: 選擇 $SNS_TOPIC_NAME"
echo "   - 點擊 'Configure'"
echo ""
echo "6️⃣  測試配置"
echo "   執行以下命令發送測試訊息:"
echo "   aws sns publish \\"
echo "     --topic-arn $SNS_TOPIC_ARN \\"
echo "     --message 'Test from AWS Chatbot' \\"
echo "     --region $AWS_REGION"
echo ""

# Save configuration info
cat > "$PROJECT_DIR/CHATBOT_SETUP.txt" <<EOF
AWS Chatbot Setup Information
==============================

Date: $(date)
Region: $AWS_REGION
Account: $AWS_ACCOUNT_ID

Resources Created:
- SNS Topic: $SNS_TOPIC_ARN
- EventBridge Rule: ${EVENTBRIDGE_RULE_NAME}-chatbot

Next Steps:
1. Visit: https://console.aws.amazon.com/chatbot/
2. Configure Slack OAuth authorization
3. Select channel: $SLACK_CHANNEL
4. Add SNS topic: $SNS_TOPIC_ARN

Test Command:
aws sns publish \\
  --topic-arn $SNS_TOPIC_ARN \\
  --message "Test AWS Chatbot" \\
  --region $AWS_REGION

Documentation:
https://docs.aws.amazon.com/chatbot/latest/adminguide/slack-setup.html
EOF

echo -e "${GREEN}✓ 配置資訊已儲存到: CHATBOT_SETUP.txt${NC}"

# ============================================
# Deployment Summary
# ============================================
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}自動化部分已完成!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}已完成:${NC}"
echo "  ✓ SNS Topic 創建"
echo "  ✓ EventBridge Rule 配置"
echo "  ✓ SNS 權限設定"
echo ""
echo -e "${YELLOW}待完成 (需手動):${NC}"
echo "  ⏳ AWS Chatbot Slack OAuth 授權"
echo "  ⏳ Slack 頻道選擇"
echo "  ⏳ IAM 角色配置"
echo ""
echo -e "${BLUE}優點:${NC}"
echo "  ✅ 零程式碼維護"
echo "  ✅ 完全免費"
echo "  ✅ AWS 託管服務"
echo "  ✅ 自動更新"
echo ""
echo -e "${YELLOW}限制:${NC}"
echo "  ⚠️  訊息格式固定"
echo "  ⚠️  無法自訂邏輯"
echo "  ⚠️  需要 Console 配置"
echo ""
echo -e "${GREEN}========================================${NC}"

# Open browser (optional)
read -p "是否開啟 AWS Chatbot Console? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    if command -v open &> /dev/null; then
        open "https://$AWS_REGION.console.aws.amazon.com/chatbot/home?region=$AWS_REGION#/"
    elif command -v xdg-open &> /dev/null; then
        xdg-open "https://$AWS_REGION.console.aws.amazon.com/chatbot/home?region=$AWS_REGION#/"
    else
        echo "請手動訪問: https://$AWS_REGION.console.aws.amazon.com/chatbot/home?region=$AWS_REGION#/"
    fi
fi
