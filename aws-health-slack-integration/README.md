# AWS Health to Slack Real-Time Alerting

Real-time notification system for AWS Health events, addressing the 17-minute notification delay identified in the [December 17, 2025 AWS Hardware Failure Incident](../ops-records/2025-12-17-AWS-Hardware-Failure-Incident-Report.md).

## Quick Start

```bash
# 1. Configure your settings
cp config/config.sh.example config/config.sh
# Edit config/config.sh with your Slack webhook URL

# 2. Deploy the integration
./scripts/deploy.sh

# 3. Test the integration
./scripts/test.sh

# 4. Monitor logs
aws logs tail /aws/lambda/AWSHealthToSlack --follow --region ap-east-1
```

## Architecture

```
AWS Health Event → EventBridge → SNS → Lambda → Slack Webhook → #ops-alerts
```

**Components**:
- **EventBridge Rule**: Filters AWS Health events (EC2, EKS, RDS, ELB)
- **SNS Topic**: `ops-alerts-aws-health` - Notification hub with fanout capability
- **Lambda Function**: `AWSHealthToSlack` - Formats AWS events to Slack messages
- **Slack Channel**: `#ops-alerts` - Receives formatted notifications

## Features

- ✅ **Real-time Notifications**: < 30 seconds latency (vs. 17 minutes via email)
- ✅ **Rich Formatting**: Color-coded messages with emojis based on severity
- ✅ **Action Buttons**: Direct links to AWS Health Dashboard and runbooks
- ✅ **Multi-Service Support**: EC2, EKS, RDS, ELB health events
- ✅ **Dead Letter Queue**: Failed messages captured for troubleshooting
- ✅ **Cost-Effective**: ~$0.03-0.10/month

## Project Structure

```
aws-health-slack-integration/
├── README.md                    # This file
├── config/
│   ├── config.sh.example        # Configuration template
│   ├── config.sh                # Your configuration (gitignored)
│   └── event-pattern.json       # EventBridge event filter
├── lambda/
│   ├── index.py                 # Lambda function code
│   └── requirements.txt         # Python dependencies
├── scripts/
│   ├── deploy.sh                # Automated deployment script
│   ├── test.sh                  # Integration testing script
│   └── cleanup.sh               # Resource cleanup script
├── tests/
│   └── test-event.json          # Sample AWS Health event for testing
└── docs/
    └── aws-health-slack-integration-guide.md  # Detailed implementation guide
```

## Prerequisites

- AWS Account: 470013648166
- Region: ap-east-1 (Hong Kong)
- AWS CLI configured with appropriate permissions
- Slack workspace with webhook access
- Permissions: EventBridge, SNS, Lambda, IAM, CloudWatch Logs

## Configuration

### 1. Create Slack Incoming Webhook

1. Navigate to: https://api.slack.com/apps
2. Create New App → From scratch
3. App Name: "AWS Health Alerts"
4. Add Features → Incoming Webhooks → Activate
5. Add New Webhook to Workspace
6. Select Channel: `#ops-alerts`
7. Copy Webhook URL

### 2. Configure Project

```bash
# Copy configuration template
cp config/config.sh.example config/config.sh

# Edit configuration
vim config/config.sh
```

**Required Settings**:
```bash
SLACK_WEBHOOK_URL="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
AWS_REGION="ap-east-1"
AWS_ACCOUNT_ID="470013648166"
```

## Deployment

### Automated Deployment

```bash
./scripts/deploy.sh
```

This script will:
1. Create SNS topic: `ops-alerts-aws-health`
2. Create IAM role: `AWSHealthToSlackLambdaRole`
3. Deploy Lambda function: `AWSHealthToSlack`
4. Subscribe Lambda to SNS
5. Create EventBridge rule: `aws-health-to-slack`
6. Configure Dead Letter Queue

**Deployment Time**: ~2-3 minutes

### Verify Deployment

```bash
# Check all resources
aws sns list-topics --region ap-east-1 | grep ops-alerts-aws-health
aws lambda get-function --function-name AWSHealthToSlack --region ap-east-1
aws events describe-rule --name aws-health-to-slack --region ap-east-1
```

## Testing

### Manual Test

```bash
./scripts/test.sh
```

This will:
1. Publish a test AWS Health event to SNS
2. Trigger Lambda function
3. Send formatted message to Slack

**Expected Result**: Message appears in #ops-alerts channel within 5 seconds

### Check Lambda Logs

```bash
# Real-time log tailing
aws logs tail /aws/lambda/AWSHealthToSlack --follow --region ap-east-1

# View recent logs
aws logs tail /aws/lambda/AWSHealthToSlack --since 1h --region ap-east-1
```

### Monitor Metrics

```bash
# Lambda invocations (last 1 hour)
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Invocations \
  --dimensions Name=FunctionName,Value=AWSHealthToSlack \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum \
  --region ap-east-1
```

## Monitoring

### CloudWatch Dashboard

Access pre-configured dashboard:
```bash
# Open in browser
open "https://ap-east-1.console.aws.amazon.com/cloudwatch/home?region=ap-east-1#dashboards:name=AWSHealthAlerting"
```

**Metrics Tracked**:
- EventBridge rule triggers
- SNS messages published
- Lambda invocations
- Lambda errors
- Lambda duration

### CloudWatch Alarms

**Active Alarms**:
- `aws-health-lambda-errors`: Triggers when Lambda function fails
- `aws-health-dlq-messages`: Triggers when messages appear in DLQ

### Dead Letter Queue

Check for failed messages:
```bash
aws sqs receive-message \
  --queue-url https://sqs.ap-east-1.amazonaws.com/470013648166/aws-health-lambda-dlq \
  --region ap-east-1
```

## Troubleshooting

### Issue: No Slack messages received

**Check**:
```bash
# 1. Verify Lambda is triggered
aws logs tail /aws/lambda/AWSHealthToSlack --since 10m --region ap-east-1

# 2. Check SNS subscription status
aws sns list-subscriptions-by-topic \
  --topic-arn arn:aws:sns:ap-east-1:470013648166:ops-alerts-aws-health \
  --region ap-east-1

# 3. Test Slack webhook directly
curl -X POST \
  -H 'Content-Type: application/json' \
  -d '{"text": "Test message"}' \
  $SLACK_WEBHOOK_URL
```

### Issue: Lambda function errors

**Check**:
```bash
# View error logs
aws logs filter-log-events \
  --log-group-name /aws/lambda/AWSHealthToSlack \
  --filter-pattern "ERROR" \
  --region ap-east-1

# Check Lambda configuration
aws lambda get-function-configuration \
  --function-name AWSHealthToSlack \
  --region ap-east-1
```

### Issue: Events not matching EventBridge rule

**Check**:
```bash
# Review event pattern
aws events describe-rule \
  --name aws-health-to-slack \
  --region ap-east-1 \
  --query 'EventPattern' \
  --output text | jq .

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

## Cleanup

To remove all resources:

```bash
./scripts/cleanup.sh
```

**Warning**: This will delete:
- EventBridge rule
- Lambda function
- SNS topic
- IAM role
- DLQ
- CloudWatch log groups

## Cost Analysis

**Monthly Cost** (estimated for ~10 health events/month):

| Service | Usage | Cost |
|---------|-------|------|
| EventBridge | ~10 events | $0.00 (free tier) |
| SNS | ~10 publishes | $0.00 (free tier) |
| Lambda | ~10 invocations, 128MB, 1s avg | $0.00 (free tier) |
| CloudWatch Logs | ~50 MB | $0.03 |
| SQS (DLQ) | Negligible | $0.00 |
| **Total** | - | **~$0.03-0.10/month** |

## Related Documentation

- **Implementation Guide**: [docs/aws-health-slack-integration-guide.md](docs/aws-health-slack-integration-guide.md)
- **Incident Report**: [ops-records/2025-12-17-AWS-Hardware-Failure-Incident-Report.md](../ops-records/2025-12-17-AWS-Hardware-Failure-Incident-Report.md)
- **EKS Node Failure Runbook**: (to be created)

## Support

For issues or questions:
- **Slack**: #ops-alerts, #devops
- **Email**: devops@company.com
- **On-Call**: PagerDuty rotation

## License

Internal use only - Proprietary

---

**Last Updated**: December 20, 2025
**Maintained By**: DevOps Team
**Status**: ⏳ Ready for Deployment
