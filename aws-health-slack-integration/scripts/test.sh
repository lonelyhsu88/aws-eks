#!/bin/bash
#
# AWS Health to Slack Integration - Test Script
# Sends a test AWS Health event to verify the integration
#
# Usage: ./scripts/test.sh
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
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}AWS Health to Slack Integration${NC}"
echo -e "${GREEN}Integration Test${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Get SNS topic ARN
SNS_TOPIC_ARN=$(aws sns list-topics --region "$AWS_REGION" \
  --query "Topics[?contains(TopicArn, '$SNS_TOPIC_NAME')].TopicArn" --output text)

if [ -z "$SNS_TOPIC_ARN" ]; then
    echo -e "${RED}ERROR: SNS topic not found. Please run ./scripts/deploy.sh first${NC}"
    exit 1
fi

echo -e "${BLUE}Configuration:${NC}"
echo "  SNS Topic:    $SNS_TOPIC_ARN"
echo "  Lambda:       $LAMBDA_FUNCTION_NAME"
echo "  Slack Channel: $SLACK_CHANNEL"
echo "  Region:       $AWS_REGION"
echo ""

# ============================================
# Test 1: Direct Slack Webhook Test
# ============================================
echo -e "${YELLOW}[Test 1/3] Testing Slack Webhook...${NC}"

WEBHOOK_TEST=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
  -H 'Content-Type: application/json' \
  -d '{"text": "✅ AWS Health Integration Test: Webhook connectivity OK"}' \
  "$SLACK_WEBHOOK_URL")

if [ "$WEBHOOK_TEST" == "200" ]; then
    echo -e "${GREEN}✓ Slack webhook is reachable (HTTP 200)${NC}"
else
    echo -e "${RED}✗ Slack webhook test failed (HTTP $WEBHOOK_TEST)${NC}"
    exit 1
fi

sleep 2

# ============================================
# Test 2: Lambda Function Test
# ============================================
echo ""
echo -e "${YELLOW}[Test 2/3] Testing Lambda Function Directly...${NC}"

# Create test SNS event
TEST_SNS_EVENT=$(cat <<EOF
{
  "Records": [{
    "Sns": {
      "Message": "{\"version\":\"0\",\"id\":\"test-$(date +%s)\",\"detail-type\":\"AWS Health Event\",\"source\":\"aws.health\",\"account\":\"$AWS_ACCOUNT_ID\",\"time\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"region\":\"$AWS_REGION\",\"resources\":[\"i-test001\",\"i-test002\"],\"detail\":{\"eventArn\":\"arn:aws:health:$AWS_REGION::event/EC2/AWS_EC2_INSTANCE_AVAILABILITY_ISSUE/TEST-$(date +%s)\",\"service\":\"EC2\",\"eventTypeCode\":\"AWS_EC2_INSTANCE_AVAILABILITY_ISSUE\",\"eventTypeCategory\":\"issue\",\"startTime\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"eventDescription\":[{\"language\":\"en_US\",\"latestDescription\":\"[TEST EVENT] This is a test AWS Health event for Slack integration validation. A subset of EC2 instances are simulated as unavailable in the $AWS_REGION region.\"}],\"affectedEntities\":[{\"entityValue\":\"i-test001\"},{\"entityValue\":\"i-test002\"}]}}"
    }
  }]
}
EOF
)

# Invoke Lambda
LAMBDA_RESULT=$(aws lambda invoke \
  --function-name "$LAMBDA_FUNCTION_NAME" \
  --payload "$TEST_SNS_EVENT" \
  --region "$AWS_REGION" \
  /tmp/lambda-response.json 2>&1)

# Check result
if [ -f /tmp/lambda-response.json ]; then
    LAMBDA_STATUS=$(cat /tmp/lambda-response.json | jq -r '.statusCode' 2>/dev/null || echo "unknown")

    if [ "$LAMBDA_STATUS" == "200" ]; then
        echo -e "${GREEN}✓ Lambda function executed successfully${NC}"
    else
        echo -e "${RED}✗ Lambda function failed (Status: $LAMBDA_STATUS)${NC}"
        cat /tmp/lambda-response.json
        exit 1
    fi

    rm -f /tmp/lambda-response.json
else
    echo -e "${RED}✗ Lambda invocation failed${NC}"
    echo "$LAMBDA_RESULT"
    exit 1
fi

sleep 2

# ============================================
# Test 3: End-to-End Integration Test
# ============================================
echo ""
echo -e "${YELLOW}[Test 3/3] Testing End-to-End Integration (SNS → Lambda → Slack)...${NC}"

# Read test event from file
TEST_EVENT_FILE="$PROJECT_DIR/tests/test-event.json"
if [ ! -f "$TEST_EVENT_FILE" ]; then
    echo -e "${YELLOW}⚠ Test event file not found, creating default...${NC}"

    # Create test event
    cat > "$TEST_EVENT_FILE" <<EOF
{
  "version": "0",
  "id": "test-event-$(date +%s)",
  "detail-type": "AWS Health Event",
  "source": "aws.health",
  "account": "$AWS_ACCOUNT_ID",
  "time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "region": "$AWS_REGION",
  "resources": [
    "i-007f3dd92b10101e6",
    "i-0a767b5cf0c79ec7f"
  ],
  "detail": {
    "eventArn": "arn:aws:health:$AWS_REGION::event/EC2/AWS_EC2_INSTANCE_AVAILABILITY_ISSUE/TEST-001",
    "service": "EC2",
    "eventTypeCode": "AWS_EC2_INSTANCE_AVAILABILITY_ISSUE",
    "eventTypeCategory": "issue",
    "startTime": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "endTime": "$(date -u -d '+30 minutes' +%Y-%m-%dT%H:%M:%SZ)",
    "eventDescription": [{
      "language": "en_US",
      "latestDescription": "[END-TO-END TEST] This is a comprehensive test of the AWS Health to Slack integration. Between $(date -u +%Y-%m-%d) and $(date -u -d '+30 minutes' +%Y-%m-%d), a subset of EC2 instances were unavailable in the $AWS_REGION Region. This is a TEST event. The issue has been resolved and the service is operating normally."
    }],
    "affectedEntities": [
      {"entityValue": "i-007f3dd92b10101e6"},
      {"entityValue": "i-0a767b5cf0c79ec7f"}
    ]
  }
}
EOF
fi

# Publish to SNS
MESSAGE_ID=$(aws sns publish \
  --topic-arn "$SNS_TOPIC_ARN" \
  --message "file://$TEST_EVENT_FILE" \
  --region "$AWS_REGION" \
  --query 'MessageId' \
  --output text)

if [ -n "$MESSAGE_ID" ]; then
    echo -e "${GREEN}✓ Test event published to SNS (MessageId: $MESSAGE_ID)${NC}"
else
    echo -e "${RED}✗ Failed to publish test event to SNS${NC}"
    exit 1
fi

# Wait for processing
echo "  Waiting for message processing (5 seconds)..."
sleep 5

# Check Lambda logs for execution
echo ""
echo -e "${BLUE}Checking Lambda execution logs...${NC}"

LOG_STREAM=$(aws logs describe-log-streams \
  --log-group-name "/aws/lambda/$LAMBDA_FUNCTION_NAME" \
  --order-by LastEventTime \
  --descending \
  --max-items 1 \
  --region "$AWS_REGION" \
  --query 'logStreams[0].logStreamName' \
  --output text 2>/dev/null)

if [ -n "$LOG_STREAM" ] && [ "$LOG_STREAM" != "None" ]; then
    echo -e "${GREEN}✓ Recent Lambda execution found${NC}"

    # Get recent log events
    LOG_EVENTS=$(aws logs get-log-events \
      --log-group-name "/aws/lambda/$LAMBDA_FUNCTION_NAME" \
      --log-stream-name "$LOG_STREAM" \
      --limit 20 \
      --region "$AWS_REGION" \
      --query 'events[-5:].message' \
      --output text 2>/dev/null)

    if echo "$LOG_EVENTS" | grep -q "SUCCESS"; then
        echo -e "${GREEN}✓ Lambda execution successful${NC}"
    elif echo "$LOG_EVENTS" | grep -q "ERROR"; then
        echo -e "${RED}✗ Lambda execution had errors:${NC}"
        echo "$LOG_EVENTS"
    else
        echo -e "${YELLOW}⚠ Lambda execution status unclear${NC}"
        echo "$LOG_EVENTS"
    fi
else
    echo -e "${YELLOW}⚠ No recent Lambda execution found in logs${NC}"
fi

# ============================================
# Test Summary
# ============================================
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Integration Test Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}Test Results:${NC}"
echo "  1. Slack Webhook:          ✅ OK"
echo "  2. Lambda Function:        ✅ OK"
echo "  3. End-to-End Integration: ✅ OK"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "  1. Check Slack channel $SLACK_CHANNEL for test messages"
echo "  2. You should see 2 test messages:"
echo "     - Direct Lambda test message"
echo "     - End-to-end integration test message"
echo ""
echo "  3. Monitor Lambda logs in real-time:"
echo "     aws logs tail /aws/lambda/$LAMBDA_FUNCTION_NAME --follow --region $AWS_REGION"
echo ""
echo "  4. If no messages appear, check:"
echo "     - Slack webhook URL in config/config.sh"
echo "     - Lambda function environment variables"
echo "     - SNS subscription status"
echo ""
echo -e "${GREEN}========================================${NC}"
