"""
AWS Health Event to Slack Formatter
Transforms AWS Health events from SNS to formatted Slack messages
"""

import json
import urllib3
import os
from datetime import datetime

http = urllib3.PoolManager()


def lambda_handler(event, context):
    """
    Transform AWS Health event to Slack message and post to webhook

    Args:
        event: SNS event containing AWS Health message
        context: Lambda context object

    Returns:
        dict: Status code and message
    """

    try:
        # Parse SNS message
        sns_message = json.loads(event['Records'][0]['Sns']['Message'])

        # Extract event details
        event_type = sns_message.get('detail-type', 'Unknown Event')
        detail = sns_message.get('detail', {})
        service = detail.get('service', 'Unknown')
        event_category = detail.get('eventTypeCategory', 'Unknown')
        event_type_code = detail.get('eventTypeCode', 'Unknown')
        region = sns_message.get('region', 'Unknown')

        # Event description
        event_descriptions = detail.get('eventDescription', [{}])
        description = event_descriptions[0].get('latestDescription', 'No description available') if event_descriptions else 'No description available'

        # Affected resources
        affected_resources = sns_message.get('resources', [])
        resource_count = len(affected_resources)

        # Event timestamps
        start_time = detail.get('startTime', 'Unknown')
        end_time = detail.get('endTime', 'Ongoing')

        # Determine severity and formatting
        severity_color = get_severity_color(event_category)
        severity_emoji = get_severity_emoji(event_category)
        severity_mention = get_severity_mention(event_category)

        # Build Slack message
        slack_message = build_slack_message(
            severity_emoji=severity_emoji,
            severity_mention=severity_mention,
            event_type=event_type,
            service=service,
            event_category=event_category,
            event_type_code=event_type_code,
            region=region,
            description=description,
            resource_count=resource_count,
            affected_resources=affected_resources,
            start_time=start_time,
            end_time=end_time,
            severity_color=severity_color
        )

        # Send to Slack
        send_to_slack(slack_message)

        return {
            'statusCode': 200,
            'body': json.dumps('Message sent to Slack successfully')
        }

    except Exception as e:
        print(f"ERROR: {str(e)}")
        print(f"Event: {json.dumps(event)}")
        raise


def build_slack_message(severity_emoji, severity_mention, event_type, service,
                         event_category, event_type_code, region, description,
                         resource_count, affected_resources, start_time, end_time,
                         severity_color):
    """
    Build formatted Slack message blocks

    Returns:
        dict: Slack message payload
    """

    message = {
        "text": f"{severity_emoji} {severity_mention}AWS Health Alert: {event_type}",
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
                        "text": f"*Event Type:*\n{event_type_code}"
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
                "fields": [
                    {
                        "type": "mrkdwn",
                        "text": f"*Affected Resources:*\n{resource_count} resource(s)"
                    },
                    {
                        "type": "mrkdwn",
                        "text": f"*Start Time:*\n{format_timestamp(start_time)}"
                    }
                ]
            }
        ],
        "attachments": [{
            "color": severity_color,
            "blocks": []
        }]
    }

    # Add end time if available
    if end_time and end_time != "Ongoing":
        message["blocks"][3]["fields"].append({
            "type": "mrkdwn",
            "text": f"*End Time:*\n{format_timestamp(end_time)}"
        })

    # Add affected resources (limit to first 10)
    if affected_resources:
        resource_text = format_resources(affected_resources, limit=10)

        message["blocks"].append({
            "type": "section",
            "text": {
                "type": "mrkdwn",
                "text": f"*Resource IDs:*\n{resource_text}"
            }
        })

    # Add action buttons
    message["blocks"].append({
        "type": "actions",
        "elements": [
            {
                "type": "button",
                "text": {
                    "type": "plain_text",
                    "text": "🔍 View in AWS Health Dashboard"
                },
                "url": f"https://phd.aws.amazon.com/phd/home?region={region}#/dashboard/open-issues",
                "style": "primary"
            },
            {
                "type": "button",
                "text": {
                    "type": "plain_text",
                    "text": "📖 View Incident Runbook"
                },
                "url": get_runbook_url(service)
            }
        ]
    })

    # Add metadata footer
    message["blocks"].append({
        "type": "context",
        "elements": [{
            "type": "mrkdwn",
            "text": f"Notification sent: {datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S UTC')} | Region: {region}"
        }]
    })

    return message


def send_to_slack(message):
    """
    Send formatted message to Slack webhook

    Args:
        message: Slack message payload

    Raises:
        ValueError: If Slack webhook returns an error
    """

    webhook_url = os.environ.get('SLACK_WEBHOOK_URL')
    if not webhook_url:
        raise ValueError("SLACK_WEBHOOK_URL environment variable not set")

    encoded_message = json.dumps(message).encode('utf-8')

    response = http.request(
        'POST',
        webhook_url,
        body=encoded_message,
        headers={'Content-Type': 'application/json'}
    )

    if response.status != 200:
        raise ValueError(
            f"Request to Slack returned error {response.status}: {response.data.decode('utf-8')}"
        )

    print(f"SUCCESS: Message sent to Slack (status: {response.status})")


def get_severity_color(category):
    """
    Map event category to Slack attachment color

    Args:
        category: AWS Health event category

    Returns:
        str: Hex color code
    """

    severity_map = {
        'issue': '#FF0000',              # Red for issues
        'scheduledChange': '#FFA500',    # Orange for scheduled changes
        'accountNotification': '#FFFF00', # Yellow for notifications
        'investigation': '#FF4500'       # Orange-red for investigations
    }
    return severity_map.get(category, '#808080')  # Gray as default


def get_severity_emoji(category):
    """
    Map event category to emoji

    Args:
        category: AWS Health event category

    Returns:
        str: Emoji character
    """

    emoji_map = {
        'issue': '🚨',
        'scheduledChange': '📅',
        'accountNotification': '📢',
        'investigation': '🔍'
    }
    return emoji_map.get(category, 'ℹ️')


def get_severity_mention(category):
    """
    Map event category to Slack mention

    Args:
        category: AWS Health event category

    Returns:
        str: Slack mention (@channel, @here, or empty)
    """

    mention_map = {
        'issue': '<!channel> ',        # @channel for critical issues
        'investigation': '<!here> ',   # @here for investigations
        'scheduledChange': '',         # No mention for scheduled changes
        'accountNotification': ''      # No mention for notifications
    }
    return mention_map.get(category, '')


def format_resources(resources, limit=10):
    """
    Format resource list for Slack message

    Args:
        resources: List of resource ARNs/IDs
        limit: Maximum number of resources to display

    Returns:
        str: Formatted resource list
    """

    resource_count = len(resources)

    # Display first N resources
    resource_text = "\n".join([f"• `{r}`" for r in resources[:limit]])

    # Add "and X more" if there are more resources
    if resource_count > limit:
        resource_text += f"\n_...and {resource_count - limit} more_"

    return resource_text


def format_timestamp(timestamp):
    """
    Format ISO timestamp to readable format

    Args:
        timestamp: ISO 8601 timestamp string

    Returns:
        str: Formatted timestamp
    """

    if not timestamp or timestamp == "Unknown":
        return "Unknown"

    try:
        dt = datetime.fromisoformat(timestamp.replace('Z', '+00:00'))
        return dt.strftime('%Y-%m-%d %H:%M:%S UTC')
    except Exception:
        return timestamp


def get_runbook_url(service):
    """
    Get runbook URL for specific service

    Args:
        service: AWS service name

    Returns:
        str: Runbook URL
    """

    runbook_map = {
        'EC2': 'https://github.com/your-org/runbooks/blob/main/eks-node-failure.md',
        'EKS': 'https://github.com/your-org/runbooks/blob/main/eks-cluster-issues.md',
        'RDS': 'https://github.com/your-org/runbooks/blob/main/rds-failover.md',
        'ELB': 'https://github.com/your-org/runbooks/blob/main/elb-issues.md',
        'ELASTICLOADBALANCING': 'https://github.com/your-org/runbooks/blob/main/elb-issues.md'
    }

    return runbook_map.get(
        service,
        'https://github.com/your-org/runbooks'
    )
