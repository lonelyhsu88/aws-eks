#!/bin/bash
#
# AWS Health to Slack Integration - Deployment Script
# Automates deployment of EventBridge → SNS → Lambda → Slack integration
#
# Usage: ./scripts/deploy.sh
#

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Load configuration
CONFIG_FILE="$PROJECT_DIR/config/config.sh"
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}ERROR: Configuration file not found: $CONFIG_FILE${NC}"
    echo -e "${YELLOW}Please create config.sh from config.sh.example:${NC}"
    echo "  cp config/config.sh.example config/config.sh"
    echo "  vim config/config.sh"
    exit 1
fi

source "$CONFIG_FILE"

# Validate required configuration
if [ "$SLACK_WEBHOOK_URL" == "https://hooks.slack.com/services/YOUR/WEBHOOK/URL" ]; then
    echo -e "${RED}ERROR: Please configure SLACK_WEBHOOK_URL in config/config.sh${NC}"
    exit 1
fi

# Print banner
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}AWS Health to Slack Integration${NC}"
echo -e "${GREEN}Automated Deployment Script${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}Configuration:${NC}"
echo "  AWS Region:        $AWS_REGION"
echo "  AWS Account:       $AWS_ACCOUNT_ID"
echo "  Slack Channel:     $SLACK_CHANNEL"
echo "  SNS Topic:         $SNS_TOPIC_NAME"
echo "  Lambda Function:   $LAMBDA_FUNCTION_NAME"
echo "  EventBridge Rule:  $EVENTBRIDGE_RULE_NAME"
echo ""

# Confirm deployment
read -p "Proceed with deployment? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Deployment cancelled${NC}"
    exit 0
fi

# ============================================
# Step 1: Create SNS Topic
# ============================================
echo ""
echo -e "${YELLOW}[1/7] Creating SNS Topic...${NC}"

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
# Step 2: Create IAM Role for Lambda
# ============================================
echo ""
echo -e "${YELLOW}[2/7] Creating IAM Role for Lambda...${NC}"

# Create trust policy
TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "lambda.amazonaws.com"},
    "Action": "sts:AssumeRole"
  }]
}
EOF
)

LAMBDA_ROLE_ARN=$(aws iam create-role \
  --role-name "$IAM_ROLE_NAME" \
  --assume-role-policy-document "$TRUST_POLICY" \
  --tags "Key=Purpose,Value=AWS-Health-Alerts" "Key=ManagedBy,Value=DevOps" \
  --query 'Role.Arn' \
  --output text 2>/dev/null || \
  aws iam get-role --role-name "$IAM_ROLE_NAME" --query 'Role.Arn' --output text)

if [ -z "$LAMBDA_ROLE_ARN" ]; then
    echo -e "${RED}ERROR: Failed to create IAM role${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Lambda Role: $LAMBDA_ROLE_ARN${NC}"

# Attach basic execution policy
aws iam attach-role-policy \
  --role-name "$IAM_ROLE_NAME" \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true

echo -e "${GREEN}✓ Basic execution policy attached${NC}"

# Wait for role propagation
echo "  Waiting for role propagation (10 seconds)..."
sleep 10

# ============================================
# Step 3: Create Dead Letter Queue (Optional)
# ============================================
if [ "$ENABLE_DLQ" == "true" ]; then
    echo ""
    echo -e "${YELLOW}[3/7] Creating Dead Letter Queue...${NC}"

    DLQ_URL=$(aws sqs create-queue \
      --queue-name "$DLQ_NAME" \
      --region "$AWS_REGION" \
      --tags "Purpose=AWS-Health-Alerts-DLQ,ManagedBy=DevOps" \
      --query 'QueueUrl' \
      --output text 2>/dev/null || \
      aws sqs get-queue-url --queue-name "$DLQ_NAME" --region "$AWS_REGION" --query 'QueueUrl' --output text)

    DLQ_ARN=$(aws sqs get-queue-attributes \
      --queue-url "$DLQ_URL" \
      --attribute-names QueueArn \
      --region "$AWS_REGION" \
      --query 'Attributes.QueueArn' \
      --output text)

    echo -e "${GREEN}✓ DLQ: $DLQ_ARN${NC}"

    # Configure DLQ access policy
    DLQ_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "lambda.amazonaws.com"},
    "Action": "sqs:SendMessage",
    "Resource": "$DLQ_ARN"
  }]
}
EOF
)

    aws sqs set-queue-attributes \
      --queue-url "$DLQ_URL" \
      --attributes "Policy=$DLQ_POLICY" \
      --region "$AWS_REGION"

    echo -e "${GREEN}✓ DLQ access policy configured${NC}"
else
    echo ""
    echo -e "${YELLOW}[3/7] Skipping Dead Letter Queue (disabled in config)${NC}"
fi

# ============================================
# Step 4: Create Lambda Function
# ============================================
echo ""
echo -e "${YELLOW}[4/7] Creating Lambda Function...${NC}"

# Prepare Lambda deployment package
TEMP_DIR=$(mktemp -d)
cp "$PROJECT_DIR/lambda/index.py" "$TEMP_DIR/"
cd "$TEMP_DIR"
zip -q function.zip index.py
cd - > /dev/null

# Deploy Lambda function
if [ "$ENABLE_DLQ" == "true" ]; then
    DLQ_CONFIG="TargetArn=$DLQ_ARN"
else
    DLQ_CONFIG=""
fi

LAMBDA_FUNCTION_ARN=$(aws lambda create-function \
  --function-name "$LAMBDA_FUNCTION_NAME" \
  --runtime "$LAMBDA_RUNTIME" \
  --role "$LAMBDA_ROLE_ARN" \
  --handler index.lambda_handler \
  --zip-file "fileb://$TEMP_DIR/function.zip" \
  --timeout "$LAMBDA_TIMEOUT" \
  --memory-size "$LAMBDA_MEMORY" \
  --environment "Variables={SLACK_WEBHOOK_URL=$SLACK_WEBHOOK_URL}" \
  $([ -n "$DLQ_CONFIG" ] && echo "--dead-letter-config $DLQ_CONFIG") \
  --region "$AWS_REGION" \
  --tags "Purpose=AWS-Health-Alerts,ManagedBy=DevOps" \
  --query 'FunctionArn' \
  --output text 2>/dev/null || \
  aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" --region "$AWS_REGION" --query 'Configuration.FunctionArn' --output text)

# Update function if it already exists
if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" --region "$AWS_REGION" &>/dev/null; then
    aws lambda update-function-code \
      --function-name "$LAMBDA_FUNCTION_NAME" \
      --zip-file "fileb://$TEMP_DIR/function.zip" \
      --region "$AWS_REGION" > /dev/null

    aws lambda update-function-configuration \
      --function-name "$LAMBDA_FUNCTION_NAME" \
      --timeout "$LAMBDA_TIMEOUT" \
      --memory-size "$LAMBDA_MEMORY" \
      --environment "Variables={SLACK_WEBHOOK_URL=$SLACK_WEBHOOK_URL}" \
      --region "$AWS_REGION" > /dev/null

    echo -e "${GREEN}✓ Lambda function updated${NC}"
fi

if [ -z "$LAMBDA_FUNCTION_ARN" ]; then
    echo -e "${RED}ERROR: Failed to create Lambda function${NC}"
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo -e "${GREEN}✓ Lambda Function: $LAMBDA_FUNCTION_ARN${NC}"

# Cleanup temp directory
rm -rf "$TEMP_DIR"

# ============================================
# Step 5: Subscribe Lambda to SNS
# ============================================
echo ""
echo -e "${YELLOW}[5/7] Subscribing Lambda to SNS...${NC}"

# Create subscription
SUBSCRIPTION_ARN=$(aws sns subscribe \
  --topic-arn "$SNS_TOPIC_ARN" \
  --protocol lambda \
  --notification-endpoint "$LAMBDA_FUNCTION_ARN" \
  --region "$AWS_REGION" \
  --query 'SubscriptionArn' \
  --output text 2>/dev/null || \
  aws sns list-subscriptions-by-topic --topic-arn "$SNS_TOPIC_ARN" --region "$AWS_REGION" \
    --query "Subscriptions[?Endpoint=='$LAMBDA_FUNCTION_ARN'].SubscriptionArn" --output text)

echo -e "${GREEN}✓ Subscription: $SUBSCRIPTION_ARN${NC}"

# Grant SNS permission to invoke Lambda
aws lambda add-permission \
  --function-name "$LAMBDA_FUNCTION_NAME" \
  --statement-id AllowSNSInvoke \
  --action lambda:InvokeFunction \
  --principal sns.amazonaws.com \
  --source-arn "$SNS_TOPIC_ARN" \
  --region "$AWS_REGION" 2>/dev/null || true

echo -e "${GREEN}✓ Lambda permission granted to SNS${NC}"

# ============================================
# Step 6: Create EventBridge Rule
# ============================================
echo ""
echo -e "${YELLOW}[6/7] Creating EventBridge Rule...${NC}"

# Create rule with event pattern
aws events put-rule \
  --name "$EVENTBRIDGE_RULE_NAME" \
  --description "Route AWS Health events to Slack via SNS and Lambda" \
  --event-pattern "file://$PROJECT_DIR/config/event-pattern.json" \
  --state ENABLED \
  --region "$AWS_REGION" \
  --tags "Key=Purpose,Value=AWS-Health-Alerts" "Key=ManagedBy,Value=DevOps"

echo -e "${GREEN}✓ EventBridge Rule: $EVENTBRIDGE_RULE_NAME${NC}"

# Add SNS topic as target
aws events put-targets \
  --rule "$EVENTBRIDGE_RULE_NAME" \
  --targets "Id=1,Arn=$SNS_TOPIC_ARN" \
  --region "$AWS_REGION"

echo -e "${GREEN}✓ SNS topic added as target${NC}"

# ============================================
# Step 7: Verification
# ============================================
echo ""
echo -e "${YELLOW}[7/7] Running Verification...${NC}"

# Verify SNS topic
if aws sns get-topic-attributes --topic-arn "$SNS_TOPIC_ARN" --region "$AWS_REGION" &>/dev/null; then
    echo -e "${GREEN}✓ SNS topic verified${NC}"
else
    echo -e "${RED}✗ SNS topic verification failed${NC}"
fi

# Verify Lambda function
if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" --region "$AWS_REGION" &>/dev/null; then
    echo -e "${GREEN}✓ Lambda function verified${NC}"
else
    echo -e "${RED}✗ Lambda function verification failed${NC}"
fi

# Verify EventBridge rule
if aws events describe-rule --name "$EVENTBRIDGE_RULE_NAME" --region "$AWS_REGION" &>/dev/null; then
    echo -e "${GREEN}✓ EventBridge rule verified${NC}"
else
    echo -e "${RED}✗ EventBridge rule verification failed${NC}"
fi

# Verify subscription
SUBSCRIPTION_STATUS=$(aws sns list-subscriptions-by-topic \
  --topic-arn "$SNS_TOPIC_ARN" \
  --region "$AWS_REGION" \
  --query "Subscriptions[?Endpoint=='$LAMBDA_FUNCTION_ARN'].SubscriptionArn" \
  --output text)

if [ -n "$SUBSCRIPTION_STATUS" ] && [ "$SUBSCRIPTION_STATUS" != "PendingConfirmation" ]; then
    echo -e "${GREEN}✓ SNS subscription verified (Active)${NC}"
else
    echo -e "${YELLOW}⚠ SNS subscription status: $SUBSCRIPTION_STATUS${NC}"
fi

# ============================================
# Deployment Summary
# ============================================
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Deployment Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}Deployed Resources:${NC}"
echo "  SNS Topic:         $SNS_TOPIC_ARN"
echo "  Lambda Function:   $LAMBDA_FUNCTION_ARN"
echo "  EventBridge Rule:  $EVENTBRIDGE_RULE_NAME"
echo "  Subscription:      $SUBSCRIPTION_ARN"
if [ "$ENABLE_DLQ" == "true" ]; then
    echo "  Dead Letter Queue: $DLQ_ARN"
fi
echo ""
echo -e "${BLUE}Monitoring:${NC}"
echo "  Slack Channel:     $SLACK_CHANNEL"
echo "  CloudWatch Logs:   /aws/lambda/$LAMBDA_FUNCTION_NAME"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "  1. Test the integration:"
echo "     ./scripts/test.sh"
echo ""
echo "  2. Monitor Lambda logs:"
echo "     aws logs tail /aws/lambda/$LAMBDA_FUNCTION_NAME --follow --region $AWS_REGION"
echo ""
echo "  3. Check Slack channel $SLACK_CHANNEL for test message"
echo ""
echo -e "${GREEN}========================================${NC}"
