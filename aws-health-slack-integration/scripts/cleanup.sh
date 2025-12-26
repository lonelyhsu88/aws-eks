#!/bin/bash
#
# AWS Health to Slack Integration - Cleanup Script
# Removes all deployed resources
#
# Usage: ./scripts/cleanup.sh
#

set -e

# Colors for output
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
echo -e "${RED}========================================${NC}"
echo -e "${RED}AWS Health to Slack Integration${NC}"
echo -e "${RED}Resource Cleanup Script${NC}"
echo -e "${RED}========================================${NC}"
echo ""
echo -e "${YELLOW}WARNING: This will delete ALL deployed resources:${NC}"
echo "  - EventBridge Rule: $EVENTBRIDGE_RULE_NAME"
echo "  - Lambda Function: $LAMBDA_FUNCTION_NAME"
echo "  - SNS Topic: $SNS_TOPIC_NAME"
echo "  - IAM Role: $IAM_ROLE_NAME"
echo "  - Dead Letter Queue: $DLQ_NAME"
echo "  - CloudWatch Log Groups"
echo ""

# Confirm deletion
read -p "Are you ABSOLUTELY SURE you want to delete these resources? (yes/NO) " -r
echo
if [[ ! $REPLY == "yes" ]]; then
    echo -e "${GREEN}Cleanup cancelled${NC}"
    exit 0
fi

# ============================================
# Step 1: Delete EventBridge Rule
# ============================================
echo ""
echo -e "${YELLOW}[1/6] Deleting EventBridge Rule...${NC}"

# Remove targets first
aws events remove-targets \
  --rule "$EVENTBRIDGE_RULE_NAME" \
  --ids 1 \
  --region "$AWS_REGION" 2>/dev/null || true

# Delete rule
if aws events delete-rule \
  --name "$EVENTBRIDGE_RULE_NAME" \
  --region "$AWS_REGION" 2>/dev/null; then
    echo -e "${GREEN}✓ EventBridge rule deleted${NC}"
else
    echo -e "${YELLOW}⚠ EventBridge rule not found or already deleted${NC}"
fi

# ============================================
# Step 2: Delete Lambda Function
# ============================================
echo ""
echo -e "${YELLOW}[2/6] Deleting Lambda Function...${NC}"

if aws lambda delete-function \
  --function-name "$LAMBDA_FUNCTION_NAME" \
  --region "$AWS_REGION" 2>/dev/null; then
    echo -e "${GREEN}✓ Lambda function deleted${NC}"
else
    echo -e "${YELLOW}⚠ Lambda function not found or already deleted${NC}"
fi

# ============================================
# Step 3: Delete SNS Topic and Subscriptions
# ============================================
echo ""
echo -e "${YELLOW}[3/6] Deleting SNS Topic...${NC}"

# Get SNS topic ARN
SNS_TOPIC_ARN=$(aws sns list-topics --region "$AWS_REGION" \
  --query "Topics[?contains(TopicArn, '$SNS_TOPIC_NAME')].TopicArn" --output text 2>/dev/null)

if [ -n "$SNS_TOPIC_ARN" ]; then
    # Delete all subscriptions
    SUBSCRIPTIONS=$(aws sns list-subscriptions-by-topic \
      --topic-arn "$SNS_TOPIC_ARN" \
      --region "$AWS_REGION" \
      --query 'Subscriptions[*].SubscriptionArn' \
      --output text 2>/dev/null)

    for SUB_ARN in $SUBSCRIPTIONS; do
        if [ "$SUB_ARN" != "PendingConfirmation" ]; then
            aws sns unsubscribe \
              --subscription-arn "$SUB_ARN" \
              --region "$AWS_REGION" 2>/dev/null || true
        fi
    done

    # Delete topic
    if aws sns delete-topic \
      --topic-arn "$SNS_TOPIC_ARN" \
      --region "$AWS_REGION" 2>/dev/null; then
        echo -e "${GREEN}✓ SNS topic deleted${NC}"
    else
        echo -e "${YELLOW}⚠ Failed to delete SNS topic${NC}"
    fi
else
    echo -e "${YELLOW}⚠ SNS topic not found or already deleted${NC}"
fi

# ============================================
# Step 4: Delete Dead Letter Queue
# ============================================
echo ""
echo -e "${YELLOW}[4/6] Deleting Dead Letter Queue...${NC}"

DLQ_URL=$(aws sqs get-queue-url \
  --queue-name "$DLQ_NAME" \
  --region "$AWS_REGION" \
  --query 'QueueUrl' \
  --output text 2>/dev/null || echo "")

if [ -n "$DLQ_URL" ]; then
    if aws sqs delete-queue \
      --queue-url "$DLQ_URL" \
      --region "$AWS_REGION" 2>/dev/null; then
        echo -e "${GREEN}✓ Dead Letter Queue deleted${NC}"
    else
        echo -e "${YELLOW}⚠ Failed to delete DLQ${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Dead Letter Queue not found or already deleted${NC}"
fi

# ============================================
# Step 5: Delete IAM Role
# ============================================
echo ""
echo -e "${YELLOW}[5/6] Deleting IAM Role...${NC}"

# Detach policies
ATTACHED_POLICIES=$(aws iam list-attached-role-policies \
  --role-name "$IAM_ROLE_NAME" \
  --query 'AttachedPolicies[*].PolicyArn' \
  --output text 2>/dev/null || echo "")

for POLICY_ARN in $ATTACHED_POLICIES; do
    aws iam detach-role-policy \
      --role-name "$IAM_ROLE_NAME" \
      --policy-arn "$POLICY_ARN" 2>/dev/null || true
done

# Delete role
if aws iam delete-role \
  --role-name "$IAM_ROLE_NAME" 2>/dev/null; then
    echo -e "${GREEN}✓ IAM role deleted${NC}"
else
    echo -e "${YELLOW}⚠ IAM role not found or already deleted${NC}"
fi

# ============================================
# Step 6: Delete CloudWatch Log Groups
# ============================================
echo ""
echo -e "${YELLOW}[6/6] Deleting CloudWatch Log Groups...${NC}"

LOG_GROUP="/aws/lambda/$LAMBDA_FUNCTION_NAME"

if aws logs delete-log-group \
  --log-group-name "$LOG_GROUP" \
  --region "$AWS_REGION" 2>/dev/null; then
    echo -e "${GREEN}✓ CloudWatch log group deleted${NC}"
else
    echo -e "${YELLOW}⚠ CloudWatch log group not found or already deleted${NC}"
fi

# ============================================
# Cleanup Summary
# ============================================
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}Deleted Resources:${NC}"
echo "  ✓ EventBridge Rule"
echo "  ✓ Lambda Function"
echo "  ✓ SNS Topic and Subscriptions"
echo "  ✓ Dead Letter Queue"
echo "  ✓ IAM Role"
echo "  ✓ CloudWatch Log Groups"
echo ""
echo -e "${YELLOW}Note:${NC} Configuration files in config/ are preserved."
echo "To redeploy, run: ./scripts/deploy.sh"
echo ""
echo -e "${GREEN}========================================${NC}"
