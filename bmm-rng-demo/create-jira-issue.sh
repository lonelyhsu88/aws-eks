#!/bin/bash
# Create Jira OPS issue for GitLab Access Configuration

# Check for required environment variables
if [ -z "$JIRA_USER" ] || [ -z "$JIRA_TOKEN" ]; then
  echo "Error: JIRA_USER and JIRA_TOKEN environment variables must be set"
  echo "Usage: JIRA_USER=user@example.com JIRA_TOKEN=your_token $0"
  exit 1
fi

# GitLab Access Configuration Issue
curl -X POST "https://jira.ftgaming.cc/rest/api/2/issue" \
  -u "$JIRA_USER:$JIRA_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "fields": {
      "project": {"key": "OPS"},
      "summary": "BMM RNG Demo - GitLab Repository Access Configuration",
      "description": "Configure GitLab repository access for BMM RNG Demo EC2\n\nBackground:\n- EC2 Instance: rng-game-srv01 (ap-east-1)\n- Repository: core/bmm-rng\n- Domain: bmm.geminigame.cc\n\nTasks Completed:\n1. EC2 SSH Key Configuration\n2. GitLab Deploy Key Setup\n3. Network Connectivity Diagnosis\n4. GitLab Security Group Configuration\n5. Connection Testing\n\nResults:\n- Git clone: Success\n- Git pull: Success\n- SSH connection: Verified\n\nSecurity:\n- Security Group limited to specific EC2 IP/32\n- Deploy Key set to read-only\n- SSH key securely stored on EC2\n\nFiles:\n- scripts/04-fix-gitlab-access.sh\n- GITLAB_ACCESS_ISSUE.md",
      "issuetype": {"name": "Task"},
      "assignee": {"name": "lonely.h"},
      "labels": ["bmm-rng", "gitlab", "infrastructure"]
    }
  }'

echo ""
echo "---"
echo ""

# pip Installation Issue
curl -X POST "https://jira.ftgaming.cc/rest/api/2/issue" \
  -u "$JIRA_USER:$JIRA_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "fields": {
      "project": {"key": "OPS"},
      "summary": "BMM RNG Demo EC2 - Install pip for Python Package Management",
      "description": "Install pip on BMM RNG Demo EC2 for Python package management\n\nBackground:\n- EC2 Instance: rng-game-srv01\n- OS: Amazon Linux 2023\n- Python: 3.9.24 (installed)\n- Issue: pip/pip3 missing\n\nExecution:\n1. Diagnosis: Python installed, pip missing\n2. Installation: sudo dnf install -y python3-pip\n3. Verification: pip 21.3.1 installed successfully\n\nResults:\n- pip successfully installed\n- Both pip and pip3 commands available\n- Python package management ready\n\nSystem Info:\n- Python: 3.9.24\n- pip: 21.3.1\n- Install method: DNF package manager\n\nRecommendations:\n1. Upgrade pip to latest version\n2. Use virtual environments for projects\n3. Install common development tools",
      "issuetype": {"name": "Task"},
      "assignee": {"name": "lonely.h"},
      "labels": ["bmm-rng", "python", "pip", "infrastructure"]
    }
  }'
