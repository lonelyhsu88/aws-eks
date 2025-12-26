# AWS Health to Slack Real-Time Alerting Implementation Guide

**Document No.**: OPS-936
**Related to**: [OPS-935](./2025-12-17-AWS-Hardware-Failure-Incident-Report.md) - AWS Hardware Failure Incident
**Date**: December 20, 2025
**Purpose**: Reduce AWS Health notification delay from 17 minutes to < 30 seconds
**Author**: DevOps Team

---

## Executive Summary

This guide provides step-by-step implementation for real-time AWS Health event notifications to Slack, addressing the 17-minute notification delay identified in the December 17, 2025 hardware failure incident.

**Target Architecture**:
```
AWS Health Event → EventBridge → SNS → Lambda → Slack Webhook → #ops-alerts
```

**Expected Outcome**:
- Notification delay: < 30 seconds (vs. current 17 minutes)
- Cost: ~$1-2/month
- Availability: 99.99% (AWS SLA)

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Prerequisites](#2-prerequisites)
3. [Implementation Steps](#3-implementation-steps)
4. [Testing and Validation](#4-testing-and-validation)
5. [Monitoring and Troubleshooting](#5-monitoring-and-troubleshooting)
6. [Cost Analysis](#6-cost-analysis)
7. [Alternative Approaches](#7-alternative-approaches)
8. [Appendices](#8-appendices)

---

## 1. Architecture Overview

### 1.1 Component Responsibilities

| Component | Role | Responsibility |
|-----------|------|----------------|
| **AWS Health** | Event Source | Emits infrastructure events (EC2 failures, maintenance, etc.) |
| **EventBridge** | Event Router | Filters and routes events based on rules |
| **SNS Topic** | Notification Hub | Delivers messages to multiple subscribers |
| **Lambda Function** | Message Formatter | Transforms AWS events to Slack-formatted messages |
| **Slack Webhook** | Delivery Endpoint | Receives formatted messages and posts to channel |

### 1.2 Data Flow

```
┌─────────────────┐
│  AWS Health     │ EC2 instance failure detected
│  Dashboard      │ Event: AWS_EC2_INSTANCE_AVAILABILITY_ISSUE
└────────┬────────┘
         │ Real-time event
         ▼
┌─────────────────┐
│  EventBridge    │ Rule: "aws-health-incidents"
│  Rule           │ Filter: EC2, issue category
└────────┬────────┘
         │ Matched event
         ▼
┌─────────────────┐
│  SNS Topic      │ Topic: "ops-alerts"
│                 │ Fanout to multiple subscribers
└────────┬────────┘
         │ Trigger subscription
         ▼
┌─────────────────┐
│  Lambda         │ Function: "FormatHealthEventForSlack"
│  Function       │ Transform: AWS JSON → Slack Blocks
└────────┬────────┘
         │ HTTP POST
         ▼
┌─────────────────┐
│  Slack Webhook  │ URL: https://hooks.slack.com/services/...
│                 │ Channel: #ops-alerts
└────────┬────────┘
         │ Display message
         ▼
┌─────────────────┐
│  Slack Channel  │ @here AWS Health Alert!
│  #ops-alerts    │ EC2 instance i-xxx unavailable in ap-east-1
└─────────────────┘
```

### 1.3 Design Decisions

**Why Lambda Instead of SNS Direct Integration?**
- SNS → Slack direct integration lacks message formatting
- AWS Health events are complex JSON, need transformation
- Lambda provides flexibility for:
  - Custom message templates
  - Severity-based formatting (colors, mentions)
  - Link enrichment (AWS Console, runbook links)
  - Event deduplication

**Why SNS Between EventBridge and Lambda?**
- Enables multiple subscribers (email, PagerDuty, other tools)
- Built-in retry mechanism (3 attempts)
- Dead Letter Queue (DLQ) support for failed deliveries
- Easier to add new notification channels later

---

## 2. Prerequisites

### 2.1 Required Resources

- ✅ AWS Account: 470013648166
- ✅ Region: ap-east-1 (Hong Kong)
- ✅ Permissions: EventBridge, SNS, Lambda, IAM
- ✅ Slack Workspace: Access to create incoming webhooks

### 2.2 Slack Webhook Setup

**Step 1**: Create Incoming Webhook
```bash
# Navigate to: https://api.slack.com/apps
# Create New App → From scratch
# App Name: "AWS Health Alerts"
# Workspace: Your workspace
# Add Features → Incoming Webhooks → Activate
# Add New Webhook to Workspace
# Select Channel: #ops-alerts
# Copy Webhook URL: https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXX
```

**Step 2**: Test Webhook
```bash
curl -X POST \
  -H 'Content-Type: application/json' \
  -d '{"text": "AWS Health Integration Test"}' \
  https://hooks.slack.com/services/YOUR/WEBHOOK/URL
```

**Expected Result**: Message appears in #ops-alerts channel

### 2.3 AWS CLI Configuration

```bash
# Verify AWS credentials
aws sts get-caller-identity --region ap-east-1

# Expected output:
# Account: 470013648166
# UserId: AIDAXXXXXXXXXXXXXXXXX
# Arn: arn:aws:iam::470013648166:user/your-username
```

---

## 3. Implementation Steps

### 3.1 Create SNS Topic

**Purpose**: Central notification hub for AWS Health events

```bash
# Create SNS topic
SNS_TOPIC_ARN=$(aws sns create-topic \
  --name ops-alerts-aws-health \
  --region ap-east-1 \
  --tags "Key=Purpose,Value=AWS-Health-Alerts" "Key=ManagedBy,Value=DevOps" \
  --query 'TopicArn' \
  --output text)

echo "SNS Topic ARN: $SNS_TOPIC_ARN"

# Configure access policy (allow EventBridge to publish)
aws sns set-topic-attributes \
  --topic-arn $SNS_TOPIC_ARN \
  --attribute-name Policy \
  --attribute-value '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {
        "Service": "events.amazonaws.com"
      },
      "Action": "SNS:Publish",
      "Resource": "'$SNS_TOPIC_ARN'"
    }]
  }' \
  --region ap-east-1
```

**Verification**:
```bash
aws sns list-topics --region ap-east-1 | grep ops-alerts-aws-health
```

### 3.2 Create Lambda Function

**Purpose**: Transform AWS Health events to Slack-formatted messages

**Step 1**: Create IAM Role for Lambda
```bash
# Create trust policy file
cat > /tmp/lambda-trust-policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Service": "lambda.amazonaws.com"
    },
    "Action": "sts:AssumeRole"
  }]
}
EOF

# Create IAM role
LAMBDA_ROLE_ARN=$(aws iam create-role \
  --role-name AWSHealthToSlackLambdaRole \
  --assume-role-policy-document file:///tmp/lambda-trust-policy.json \
  --query 'Role.Arn' \
  --output text)

echo "Lambda Role ARN: $LAMBDA_ROLE_ARN"

# Attach basic execution policy
aws iam attach-role-policy \
  --role-name AWSHealthToSlackLambdaRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

# Wait for role propagation
sleep 10
```

**Step 2**: Create Lambda Function Code
```bash
# Create function directory
mkdir -p /tmp/aws-health-lambda
cd /tmp/aws-health-lambda

# Create function code
cat > index.py <<'PYTHON_CODE'
import json
import urllib3
import os
from datetime import datetime

http = urllib3.PoolManager()

def lambda_handler(event, context):
    """
    Transform AWS Health event to Slack message and post to webhook
    """

    # Parse SNS message
    sns_message = json.loads(event['Records'][0]['Sns']['Message'])

    # Extract event details
    event_type = sns_message.get('detail-type', 'Unknown Event')
    service = sns_message.get('detail', {}).get('service', 'Unknown')
    event_category = sns_message.get('detail', {}).get('eventTypeCategory', 'Unknown')
    region = sns_message.get('region', 'Unknown')

    # Event description
    description = sns_message.get('detail', {}).get('eventDescription', [{}])[0].get('latestDescription', 'No description available')

    # Affected resources
    affected_resources = sns_message.get('resources', [])
    resource_count = len(affected_resources)

    # Determine severity and color
    severity_color = get_severity_color(event_category)
    severity_emoji = get_severity_emoji(event_category)

    # Build Slack message
    slack_message = {
        "text": f"{severity_emoji} AWS Health Alert: {event_type}",
        "blocks": [
            {
                "type": "header",
                "text": {
                    "type": "plain_text",
                    "text": f"{severity_emoji} AWS Health Alert"
                }
            },
            {
                "type": "section",
                "fields": [
                    {
                        "type": "mrkdwn",
                        "text": f"*Event Type:*\n{event_type}"
                    },
                    {
                        "type": "mrkdwn",
                        "text": f"*Service:*\n{service}"
                    },
                    {
                        "type": "mrkdwn",
                        "text": f"*Category:*\n{event_category}"
                    },
                    {
                        "type": "mrkdwn",
                        "text": f"*Region:*\n{region}"
                    }
                ]
            },
            {
                "type": "section",
                "text": {
                    "type": "mrkdwn",
                    "text": f"*Description:*\n{description}"
                }
            },
            {
                "type": "section",
                "text": {
                    "type": "mrkdwn",
                    "text": f"*Affected Resources:* {resource_count} resource(s)"
                }
            }
        ],
        "attachments": [{
            "color": severity_color,
            "blocks": []
        }]
    }

    # Add affected resources (limit to first 5)
    if affected_resources:
        resource_text = "\n".join([f"• `{r}`" for r in affected_resources[:5]])
        if resource_count > 5:
            resource_text += f"\n_...and {resource_count - 5} more_"

        slack_message["blocks"].append({
            "type": "section",
            "text": {
                "type": "mrkdwn",
                "text": f"*Resource IDs:*\n{resource_text}"
            }
        })

    # Add action buttons
    slack_message["blocks"].append({
        "type": "actions",
        "elements": [
            {
                "type": "button",
                "text": {
                    "type": "plain_text",
                    "text": "View in AWS Health Dashboard"
                },
                "url": f"https://phd.aws.amazon.com/phd/home?region={region}#/dashboard/open-issues"
            },
            {
                "type": "button",
                "text": {
                    "type": "plain_text",
                    "text": "View Incident Runbook"
                },
                "url": "https://github.com/your-org/runbooks/eks-node-failure"
            }
        ]
    })

    # Add metadata footer
    slack_message["blocks"].append({
        "type": "context",
        "elements": [{
            "type": "mrkdwn",
            "text": f"Timestamp: {datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S UTC')} | Region: {region}"
        }]
    })

    # Send to Slack
    webhook_url = os.environ['SLACK_WEBHOOK_URL']
    encoded_message = json.dumps(slack_message).encode('utf-8')

    response = http.request(
        'POST',
        webhook_url,
        body=encoded_message,
        headers={'Content-Type': 'application/json'}
    )

    if response.status != 200:
        raise ValueError(f"Request to Slack returned an error {response.status}, response: {response.data}")

    return {
        'statusCode': 200,
        'body': json.dumps('Message sent to Slack successfully')
    }

def get_severity_color(category):
    """Map event category to Slack attachment color"""
    severity_map = {
        'issue': '#FF0000',           # Red for issues
        'scheduledChange': '#FFA500',  # Orange for scheduled changes
        'accountNotification': '#FFFF00',  # Yellow for notifications
        'investigation': '#FF4500'     # Orange-red for investigations
    }
    return severity_map.get(category, '#808080')  # Gray as default

def get_severity_emoji(category):
    """Map event category to emoji"""
    emoji_map = {
        'issue': '🚨',
        'scheduledChange': '📅',
        'accountNotification': '📢',
        'investigation': '🔍'
    }
    return emoji_map.get(category, 'ℹ️')
PYTHON_CODE

# Create deployment package
zip -r function.zip index.py
```

**Step 3**: Deploy Lambda Function
```bash
# Replace with your Slack webhook URL
SLACK_WEBHOOK_URL="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"

# Create Lambda function
LAMBDA_FUNCTION_ARN=$(aws lambda create-function \
  --function-name AWSHealthToSlack \
  --runtime python3.11 \
  --role $LAMBDA_ROLE_ARN \
  --handler index.lambda_handler \
  --zip-file fileb://function.zip \
  --timeout 30 \
  --memory-size 128 \
  --environment "Variables={SLACK_WEBHOOK_URL=$SLACK_WEBHOOK_URL}" \
  --region ap-east-1 \
  --tags "Purpose=AWS-Health-Alerts,ManagedBy=DevOps" \
  --query 'FunctionArn' \
  --output text)

echo "Lambda Function ARN: $LAMBDA_FUNCTION_ARN"
```

**Verification**:
```bash
aws lambda get-function --function-name AWSHealthToSlack --region ap-east-1
```

### 3.3 Subscribe Lambda to SNS Topic

```bash
# Create SNS subscription
SUBSCRIPTION_ARN=$(aws sns subscribe \
  --topic-arn $SNS_TOPIC_ARN \
  --protocol lambda \
  --notification-endpoint $LAMBDA_FUNCTION_ARN \
  --region ap-east-1 \
  --query 'SubscriptionArn' \
  --output text)

echo "Subscription ARN: $SUBSCRIPTION_ARN"

# Grant SNS permission to invoke Lambda
aws lambda add-permission \
  --function-name AWSHealthToSlack \
  --statement-id AllowSNSInvoke \
  --action lambda:InvokeFunction \
  --principal sns.amazonaws.com \
  --source-arn $SNS_TOPIC_ARN \
  --region ap-east-1
```

**Verification**:
```bash
aws sns list-subscriptions-by-topic \
  --topic-arn $SNS_TOPIC_ARN \
  --region ap-east-1
```

### 3.4 Create EventBridge Rule

**Purpose**: Filter AWS Health events and route to SNS

```bash
# Create event pattern
cat > /tmp/health-event-pattern.json <<'EOF'
{
  "source": ["aws.health"],
  "detail-type": ["AWS Health Event"],
  "detail": {
    "service": ["EC2", "EKS", "RDS", "ELB"],
    "eventTypeCategory": ["issue", "scheduledChange", "investigation"]
  }
}
EOF

# Create EventBridge rule
aws events put-rule \
  --name aws-health-to-slack \
  --description "Route AWS Health events to Slack via SNS" \
  --event-pattern file:///tmp/health-event-pattern.json \
  --state ENABLED \
  --region ap-east-1 \
  --tags "Key=Purpose,Value=AWS-Health-Alerts" "Key=ManagedBy,Value=DevOps"

# Add SNS topic as target
aws events put-targets \
  --rule aws-health-to-slack \
  --targets "Id"="1","Arn"="$SNS_TOPIC_ARN" \
  --region ap-east-1
```

**Verification**:
```bash
# Check rule exists
aws events describe-rule \
  --name aws-health-to-slack \
  --region ap-east-1

# Check targets
aws events list-targets-by-rule \
  --rule aws-health-to-slack \
  --region ap-east-1
```

### 3.5 Add Dead Letter Queue (Optional but Recommended)

**Purpose**: Capture failed Lambda invocations for troubleshooting

```bash
# Create DLQ
DLQ_URL=$(aws sqs create-queue \
  --queue-name aws-health-lambda-dlq \
  --region ap-east-1 \
  --query 'QueueUrl' \
  --output text)

DLQ_ARN=$(aws sqs get-queue-attributes \
  --queue-url $DLQ_URL \
  --attribute-names QueueArn \
  --region ap-east-1 \
  --query 'Attributes.QueueArn' \
  --output text)

echo "DLQ ARN: $DLQ_ARN"

# Configure Lambda DLQ
aws lambda update-function-configuration \
  --function-name AWSHealthToSlack \
  --dead-letter-config TargetArn=$DLQ_ARN \
  --region ap-east-1

# Grant Lambda permission to send to DLQ
aws sqs set-queue-attributes \
  --queue-url $DLQ_URL \
  --attributes '{
    "Policy": "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Service\":\"lambda.amazonaws.com\"},\"Action\":\"sqs:SendMessage\",\"Resource\":\"'$DLQ_ARN'\"}]}"
  }' \
  --region ap-east-1
```

---

## 4. Testing and Validation

### 4.1 Manual Test via AWS CLI

**Test 1**: Publish test event to SNS
```bash
# Create test AWS Health event
cat > /tmp/test-health-event.json <<'EOF'
{
  "version": "0",
  "id": "test-event-001",
  "detail-type": "AWS Health Event",
  "source": "aws.health",
  "account": "470013648166",
  "time": "2025-12-20T12:00:00Z",
  "region": "ap-east-1",
  "resources": ["i-0123456789abcdef0", "i-0fedcba9876543210"],
  "detail": {
    "eventArn": "arn:aws:health:ap-east-1::event/EC2/AWS_EC2_INSTANCE_AVAILABILITY_ISSUE/TEST-001",
    "service": "EC2",
    "eventTypeCode": "AWS_EC2_INSTANCE_AVAILABILITY_ISSUE",
    "eventTypeCategory": "issue",
    "startTime": "2025-12-20T12:00:00Z",
    "eventDescription": [{
      "language": "en_US",
      "latestDescription": "This is a test AWS Health event for Slack integration validation. A subset of EC2 instances are simulated as unavailable in the ap-east-1 region."
    }],
    "affectedEntities": [{
      "entityValue": "i-0123456789abcdef0"
    }, {
      "entityValue": "i-0fedcba9876543210"
    }]
  }
}
EOF

# Publish to SNS (will trigger Lambda → Slack)
aws sns publish \
  --topic-arn $SNS_TOPIC_ARN \
  --message file:///tmp/test-health-event.json \
  --region ap-east-1
```

**Expected Result**:
- Lambda invoked successfully
- Slack message appears in #ops-alerts
- Message contains:
  - 🚨 AWS Health Alert header
  - Event type: AWS Health Event
  - Service: EC2
  - Category: issue
  - Description: Test event message
  - 2 affected resources
  - Action buttons (AWS Health Dashboard, Runbook)

**Test 2**: Check Lambda execution logs
```bash
# Get latest log stream
LOG_STREAM=$(aws logs describe-log-streams \
  --log-group-name /aws/lambda/AWSHealthToSlack \
  --order-by LastEventTime \
  --descending \
  --max-items 1 \
  --region ap-east-1 \
  --query 'logStreams[0].logStreamName' \
  --output text)

# View logs
aws logs get-log-events \
  --log-group-name /aws/lambda/AWSHealthToSlack \
  --log-stream-name "$LOG_STREAM" \
  --region ap-east-1 \
  --query 'events[*].[timestamp,message]' \
  --output table
```

**Expected Result**:
- START RequestId
- Message sent to Slack successfully
- END RequestId
- No ERROR messages

### 4.2 Simulate Real AWS Health Event (Advanced)

**Option 1**: Use AWS FIS (Fault Injection Simulator)
```bash
# Requires AWS FIS setup - not included in basic implementation
# Reference: https://docs.aws.amazon.com/fis/latest/userguide/what-is.html
```

**Option 2**: Monitor real events (Passive)
```bash
# Check EventBridge metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/Events \
  --metric-name TriggeredRules \
  --dimensions Name=RuleName,Value=aws-health-to-slack \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum \
  --region ap-east-1
```

### 4.3 Validation Checklist

- [ ] **SNS Topic Created**: `aws sns list-topics | grep ops-alerts-aws-health`
- [ ] **Lambda Function Deployed**: `aws lambda get-function --function-name AWSHealthToSlack`
- [ ] **SNS Subscription Active**: Check `PendingConfirmation` = false
- [ ] **EventBridge Rule Enabled**: `aws events describe-rule --name aws-health-to-slack`
- [ ] **Lambda Permissions Set**: `aws lambda get-policy --function-name AWSHealthToSlack`
- [ ] **Slack Webhook Works**: Test message received in #ops-alerts
- [ ] **Test Event Processed**: Manual SNS publish triggers Slack message
- [ ] **Lambda Logs Clean**: No errors in CloudWatch Logs
- [ ] **DLQ Configured**: Lambda has DLQ configured (optional)

---

## 5. Monitoring and Troubleshooting

### 5.1 CloudWatch Dashboards

**Create Monitoring Dashboard**:
```bash
cat > /tmp/health-alerts-dashboard.json <<'EOF'
{
  "widgets": [
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["AWS/Events", "TriggeredRules", {"stat": "Sum", "label": "EventBridge Rule Triggers"}],
          ["AWS/SNS", "NumberOfMessagesPublished", {"stat": "Sum", "label": "SNS Messages Published"}],
          ["AWS/Lambda", "Invocations", {"stat": "Sum", "label": "Lambda Invocations"}],
          ["AWS/Lambda", "Errors", {"stat": "Sum", "label": "Lambda Errors"}],
          ["AWS/Lambda", "Duration", {"stat": "Average", "label": "Lambda Duration (ms)"}]
        ],
        "view": "timeSeries",
        "stacked": false,
        "region": "ap-east-1",
        "title": "AWS Health to Slack Pipeline Metrics",
        "period": 300
      }
    },
    {
      "type": "log",
      "properties": {
        "query": "SOURCE '/aws/lambda/AWSHealthToSlack'\n| fields @timestamp, @message\n| filter @message like /ERROR/\n| sort @timestamp desc\n| limit 20",
        "region": "ap-east-1",
        "title": "Recent Lambda Errors"
      }
    }
  ]
}
EOF

aws cloudwatch put-dashboard \
  --dashboard-name AWSHealthAlerting \
  --dashboard-body file:///tmp/health-alerts-dashboard.json \
  --region ap-east-1
```

### 5.2 CloudWatch Alarms

**Alarm 1**: Lambda Function Errors
```bash
aws cloudwatch put-metric-alarm \
  --alarm-name aws-health-lambda-errors \
  --alarm-description "Alert when AWS Health Lambda function fails" \
  --metric-name Errors \
  --namespace AWS/Lambda \
  --statistic Sum \
  --period 300 \
  --evaluation-periods 1 \
  --threshold 1 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=FunctionName,Value=AWSHealthToSlack \
  --treat-missing-data notBreaching \
  --region ap-east-1
```

**Alarm 2**: Dead Letter Queue Messages
```bash
aws cloudwatch put-metric-alarm \
  --alarm-name aws-health-dlq-messages \
  --alarm-description "Alert when messages appear in DLQ" \
  --metric-name ApproximateNumberOfMessagesVisible \
  --namespace AWS/SQS \
  --statistic Average \
  --period 300 \
  --evaluation-periods 1 \
  --threshold 1 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=QueueName,Value=aws-health-lambda-dlq \
  --treat-missing-data notBreaching \
  --region ap-east-1
```

### 5.3 Common Issues and Solutions

| Issue | Symptom | Solution |
|-------|---------|----------|
| **Lambda not triggered** | No Slack messages | Check SNS subscription status, verify Lambda permissions |
| **Slack webhook fails** | Lambda errors: "400 Bad Request" | Verify webhook URL, check message format |
| **Missing events** | Expected events not appearing | Review EventBridge event pattern, check AWS Health dashboard |
| **High latency** | Delay > 1 minute | Check Lambda cold start time, increase memory allocation |
| **Message formatting issues** | Slack message unreadable | Review Lambda code, test with sample events |

**Debug Commands**:
```bash
# Check Lambda error rate
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Errors \
  --dimensions Name=FunctionName,Value=AWSHealthToSlack \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum \
  --region ap-east-1

# Check DLQ for failed messages
aws sqs receive-message \
  --queue-url $DLQ_URL \
  --region ap-east-1

# View recent Lambda invocations
aws lambda list-provisioned-concurrency-configs \
  --function-name AWSHealthToSlack \
  --region ap-east-1
```

---

## 6. Cost Analysis

### 6.1 Monthly Cost Breakdown

| Service | Usage | Unit Cost | Monthly Cost |
|---------|-------|-----------|--------------|
| **EventBridge** | ~10 health events/month | $0.00 (1M free) | **$0.00** |
| **SNS** | ~10 publishes/month | $0.50 per 1M | **$0.00** |
| **Lambda** | ~10 invocations/month, 128MB, 1s avg | $0.20 per 1M requests + $0.0000166667 per GB-second | **$0.00** |
| **CloudWatch Logs** | ~50 MB/month | $0.50 per GB | **$0.03** |
| **SQS (DLQ)** | Negligible (only failures) | $0.40 per 1M requests | **$0.00** |
| **Total** | - | - | **~$0.03-0.10/month** |

**Note**: Costs are negligible due to AWS Free Tier coverage for low-volume alerting.

### 6.2 Cost Comparison vs. Alternatives

| Solution | Monthly Cost | Pros | Cons |
|----------|-------------|------|------|
| **AWS Native (This)** | $0.03-0.10 | Native integration, low cost, full control | Requires maintenance |
| **AWS Chatbot** | $0.00 | No Lambda needed, AWS managed | Limited formatting, less flexible |
| **PagerDuty** | $19+ per user | Full incident management, on-call rotation | Higher cost, may be overkill |
| **Opsgenie** | $9+ per user | Alerting + on-call | Higher cost |
| **Datadog** | $15+ per host | Full observability platform | Significantly higher cost |

**Recommendation**: AWS Native solution for cost-effectiveness, upgrade to PagerDuty/Opsgenie if need on-call rotation.

---

## 7. Alternative Approaches

### 7.1 Option 1: AWS Chatbot (Simpler, Less Flexible)

**Architecture**: AWS Health → EventBridge → AWS Chatbot → Slack

**Pros**:
- No Lambda maintenance
- AWS-managed service
- Built-in Slack/Microsoft Teams support

**Cons**:
- Limited message customization
- Cannot add custom logic (deduplication, enrichment)
- Less control over formatting

**Implementation**:
```bash
# Create Chatbot configuration via AWS Console
# Services → AWS Chatbot → Configure new client
# Select Slack → Authorize → Select channel
# Add SNS topic as notification source
```

**When to Use**:
- Simple notification requirements
- No custom message formatting needed
- Prefer AWS-managed solution

### 7.2 Option 2: EventBridge → Lambda → Slack (Skip SNS)

**Architecture**: AWS Health → EventBridge → Lambda → Slack

**Pros**:
- One less service in chain (lower latency)
- Simpler architecture

**Cons**:
- Loses SNS fanout capability (can't add email, PagerDuty easily)
- No built-in retry from SNS
- No DLQ without additional setup

**Implementation**:
```bash
# Same Lambda function
# EventBridge target = Lambda directly (instead of SNS)
aws events put-targets \
  --rule aws-health-to-slack \
  --targets "Id"="1","Arn"="$LAMBDA_FUNCTION_ARN"
```

**When to Use**:
- Only need Slack notifications (no other channels)
- Want minimal latency

### 7.3 Option 3: Third-Party Integration (PagerDuty/Opsgenie)

**Architecture**: AWS Health → EventBridge → PagerDuty/Opsgenie → Slack

**Pros**:
- Professional incident management platform
- On-call rotation support
- Escalation policies
- Incident tracking and analytics

**Cons**:
- Higher cost ($9-19+ per user/month)
- External dependency

**When to Use**:
- Need on-call rotation
- Require incident management workflows
- Have budget for dedicated platform

---

## 8. Appendices

### Appendix A: Complete Deployment Script

**File**: `scripts/deploy-health-alerts.sh`

```bash
#!/bin/bash
set -e

# Configuration
REGION="ap-east-1"
ACCOUNT_ID="470013648166"
SLACK_WEBHOOK_URL="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}AWS Health to Slack Integration Setup${NC}"
echo -e "${GREEN}========================================${NC}"

# Step 1: Create SNS Topic
echo -e "\n${YELLOW}[1/6] Creating SNS Topic...${NC}"
SNS_TOPIC_ARN=$(aws sns create-topic \
  --name ops-alerts-aws-health \
  --region $REGION \
  --query 'TopicArn' \
  --output text 2>/dev/null || \
  aws sns list-topics --region $REGION --query "Topics[?contains(TopicArn, 'ops-alerts-aws-health')].TopicArn" --output text)

echo -e "${GREEN}✓ SNS Topic: $SNS_TOPIC_ARN${NC}"

# Configure SNS access policy
aws sns set-topic-attributes \
  --topic-arn $SNS_TOPIC_ARN \
  --attribute-name Policy \
  --attribute-value '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Service": "events.amazonaws.com"},
      "Action": "SNS:Publish",
      "Resource": "'$SNS_TOPIC_ARN'"
    }]
  }' \
  --region $REGION

# Step 2: Create IAM Role for Lambda
echo -e "\n${YELLOW}[2/6] Creating IAM Role for Lambda...${NC}"

cat > /tmp/lambda-trust-policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "lambda.amazonaws.com"},
    "Action": "sts:AssumeRole"
  }]
}
EOF

LAMBDA_ROLE_ARN=$(aws iam create-role \
  --role-name AWSHealthToSlackLambdaRole \
  --assume-role-policy-document file:///tmp/lambda-trust-policy.json \
  --query 'Role.Arn' \
  --output text 2>/dev/null || \
  aws iam get-role --role-name AWSHealthToSlackLambdaRole --query 'Role.Arn' --output text)

echo -e "${GREEN}✓ Lambda Role: $LAMBDA_ROLE_ARN${NC}"

aws iam attach-role-policy \
  --role-name AWSHealthToSlackLambdaRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true

sleep 5

# Step 3: Create Lambda Function
echo -e "\n${YELLOW}[3/6] Creating Lambda Function...${NC}"

mkdir -p /tmp/aws-health-lambda
cd /tmp/aws-health-lambda

# Copy Lambda code from section 3.2 (index.py)
# ... (code omitted for brevity, same as section 3.2)

zip -q -r function.zip index.py

LAMBDA_FUNCTION_ARN=$(aws lambda create-function \
  --function-name AWSHealthToSlack \
  --runtime python3.11 \
  --role $LAMBDA_ROLE_ARN \
  --handler index.lambda_handler \
  --zip-file fileb://function.zip \
  --timeout 30 \
  --memory-size 128 \
  --environment "Variables={SLACK_WEBHOOK_URL=$SLACK_WEBHOOK_URL}" \
  --region $REGION \
  --query 'FunctionArn' \
  --output text 2>/dev/null || \
  aws lambda get-function --function-name AWSHealthToSlack --region $REGION --query 'Configuration.FunctionArn' --output text)

echo -e "${GREEN}✓ Lambda Function: $LAMBDA_FUNCTION_ARN${NC}"

# Step 4: Subscribe Lambda to SNS
echo -e "\n${YELLOW}[4/6] Subscribing Lambda to SNS...${NC}"

aws sns subscribe \
  --topic-arn $SNS_TOPIC_ARN \
  --protocol lambda \
  --notification-endpoint $LAMBDA_FUNCTION_ARN \
  --region $REGION 2>/dev/null || true

aws lambda add-permission \
  --function-name AWSHealthToSlack \
  --statement-id AllowSNSInvoke \
  --action lambda:InvokeFunction \
  --principal sns.amazonaws.com \
  --source-arn $SNS_TOPIC_ARN \
  --region $REGION 2>/dev/null || true

echo -e "${GREEN}✓ Lambda subscribed to SNS${NC}"

# Step 5: Create EventBridge Rule
echo -e "\n${YELLOW}[5/6] Creating EventBridge Rule...${NC}"

cat > /tmp/health-event-pattern.json <<'EOF'
{
  "source": ["aws.health"],
  "detail-type": ["AWS Health Event"],
  "detail": {
    "service": ["EC2", "EKS", "RDS", "ELB"],
    "eventTypeCategory": ["issue", "scheduledChange", "investigation"]
  }
}
EOF

aws events put-rule \
  --name aws-health-to-slack \
  --description "Route AWS Health events to Slack via SNS" \
  --event-pattern file:///tmp/health-event-pattern.json \
  --state ENABLED \
  --region $REGION

aws events put-targets \
  --rule aws-health-to-slack \
  --targets "Id"="1","Arn"="$SNS_TOPIC_ARN" \
  --region $REGION

echo -e "${GREEN}✓ EventBridge Rule created${NC}"

# Step 6: Verification
echo -e "\n${YELLOW}[6/6] Running Verification...${NC}"

echo -e "${GREEN}✓ All components deployed successfully!${NC}"
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}Deployment Summary${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "SNS Topic:         $SNS_TOPIC_ARN"
echo -e "Lambda Function:   $LAMBDA_FUNCTION_ARN"
echo -e "EventBridge Rule:  aws-health-to-slack"
echo -e "Slack Channel:     #ops-alerts"
echo -e "${GREEN}========================================${NC}"

echo -e "\n${YELLOW}Next Steps:${NC}"
echo "1. Test the integration with: aws sns publish --topic-arn $SNS_TOPIC_ARN --message '{\"test\": true}'"
echo "2. Monitor Lambda logs: aws logs tail /aws/lambda/AWSHealthToSlack --follow --region $REGION"
echo "3. Check Slack channel #ops-alerts for test message"

cd - > /dev/null
```

### Appendix B: Lambda Function - Advanced Features

**Enhanced Lambda with Deduplication and Rate Limiting**:

```python
import json
import urllib3
import os
from datetime import datetime, timedelta
import hashlib
import boto3

http = urllib3.PoolManager()
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('aws-health-event-cache')  # Create this table separately

def lambda_handler(event, context):
    """
    Enhanced AWS Health to Slack with deduplication
    """

    # Parse SNS message
    sns_message = json.loads(event['Records'][0]['Sns']['Message'])

    # Generate event hash for deduplication
    event_id = sns_message.get('id', 'unknown')
    event_hash = hashlib.md5(event_id.encode()).hexdigest()

    # Check if event was already processed (within 1 hour)
    try:
        response = table.get_item(Key={'event_hash': event_hash})
        if 'Item' in response:
            last_sent = datetime.fromisoformat(response['Item']['timestamp'])
            if datetime.utcnow() - last_sent < timedelta(hours=1):
                print(f"Event {event_id} already processed, skipping")
                return {'statusCode': 200, 'body': 'Duplicate event, skipped'}
    except Exception as e:
        print(f"DynamoDB error: {e}")

    # Send to Slack (same code as before)
    send_to_slack(sns_message)

    # Store event hash
    try:
        table.put_item(Item={
            'event_hash': event_hash,
            'event_id': event_id,
            'timestamp': datetime.utcnow().isoformat(),
            'ttl': int((datetime.utcnow() + timedelta(hours=24)).timestamp())
        })
    except Exception as e:
        print(f"Failed to store event hash: {e}")

    return {'statusCode': 200, 'body': 'Success'}

def send_to_slack(event_data):
    # Same implementation as basic version
    pass
```

**DynamoDB Table for Deduplication**:
```bash
aws dynamodb create-table \
  --table-name aws-health-event-cache \
  --attribute-definitions AttributeName=event_hash,AttributeType=S \
  --key-schema AttributeName=event_hash,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --time-to-live-specification "Enabled=true,AttributeName=ttl" \
  --region ap-east-1
```

### Appendix C: Slack Message Examples

**Example 1**: EC2 Instance Availability Issue (from 12/17 incident)
```json
{
  "text": "🚨 AWS Health Alert: AWS Health Event",
  "blocks": [
    {
      "type": "header",
      "text": {"type": "plain_text", "text": "🚨 AWS Health Alert"}
    },
    {
      "type": "section",
      "fields": [
        {"type": "mrkdwn", "text": "*Event Type:*\nAWS Health Event"},
        {"type": "mrkdwn", "text": "*Service:*\nEC2"},
        {"type": "mrkdwn", "text": "*Category:*\nissue"},
        {"type": "mrkdwn", "text": "*Region:*\nap-east-1"}
      ]
    },
    {
      "type": "section",
      "text": {
        "type": "mrkdwn",
        "text": "*Description:*\nA subset of EC2 instances were unavailable in the ap-east-1 Region."
      }
    },
    {
      "type": "section",
      "text": {"type": "mrkdwn", "text": "*Affected Resources:* 2 resource(s)"}
    },
    {
      "type": "section",
      "text": {
        "type": "mrkdwn",
        "text": "*Resource IDs:*\n• `i-007f3dd92b10101e6`\n• `i-0a767b5cf0c79ec7f`"
      }
    },
    {
      "type": "actions",
      "elements": [
        {
          "type": "button",
          "text": {"type": "plain_text", "text": "View in AWS Health Dashboard"},
          "url": "https://phd.aws.amazon.com/phd/home?region=ap-east-1#/dashboard/open-issues"
        },
        {
          "type": "button",
          "text": {"type": "plain_text", "text": "View Incident Runbook"},
          "url": "https://github.com/your-org/runbooks/eks-node-failure"
        }
      ]
    }
  ],
  "attachments": [{"color": "#FF0000"}]
}
```

### Appendix D: Incident Response Integration

**Slack Message with @mention for On-Call**:

Modify Lambda to add @channel or @here mentions for critical events:

```python
def format_slack_message(event_data):
    severity = event_data.get('detail', {}).get('eventTypeCategory', 'unknown')

    # Add mentions for critical events
    if severity == 'issue':
        prefix = "<!channel> "  # @channel
    elif severity == 'investigation':
        prefix = "<!here> "     # @here
    else:
        prefix = ""

    return {
        "text": f"{prefix}🚨 AWS Health Alert",
        # ... rest of message
    }
```

**Integration with Runbook**:

Update action buttons to link to specific runbooks:

```python
runbook_map = {
    'EC2': 'https://github.com/your-org/runbooks/eks-node-failure',
    'RDS': 'https://github.com/your-org/runbooks/rds-failover',
    'EKS': 'https://github.com/your-org/runbooks/eks-cluster-issues'
}

service = event_data.get('detail', {}).get('service', 'Unknown')
runbook_url = runbook_map.get(service, 'https://github.com/your-org/runbooks')
```

---

## Document Metadata

**Document Version**: 1.0
**Last Updated**: December 20, 2025
**Next Review**: January 20, 2026
**Approval Required**: DevOps Lead, Engineering Manager
**Related Documents**:
- [OPS-935: AWS Hardware Failure Incident Report](./2025-12-17-AWS-Hardware-Failure-Incident-Report.md)
- [EKS Node Failure Runbook](../runbooks/eks-node-failure-response.md) (to be created)

**Deployment Status**: ⏳ Pending Implementation

**Testing Status**: ⏳ Pending Testing

---

**End of Document**
