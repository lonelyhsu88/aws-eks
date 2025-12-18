#!/bin/bash
# =============================================================================
# BMM RNG Demo - Fix GitLab Access
# 診斷並修復 EC2 到 GitLab 的連線問題
# =============================================================================

set -e

# Configuration
AWS_PROFILE="${AWS_PROFILE:-gemini-pro_ck}"
REGION="${AWS_DEFAULT_REGION:-ap-east-1}"
SECURITY_GROUP_NAME="bmm-rng-demo-sg"
GITLAB_IP="16.162.37.5"

# Export profile
export AWS_PROFILE
export AWS_DEFAULT_REGION="$REGION"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║                                                                  ║"
echo "║           GitLab Access Diagnostics & Fix                        ║"
echo "║                                                                  ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""

# Load instance info
if [ ! -f instance-info.txt ]; then
    echo -e "${RED}Error: instance-info.txt not found${NC}"
    exit 1
fi
source instance-info.txt

# Step 1: Get Security Group ID
echo -e "${YELLOW}[1/4] Getting Security Group ID${NC}"
SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=$SECURITY_GROUP_NAME" \
    --query 'SecurityGroups[0].GroupId' \
    --output text 2>/dev/null)

if [ -z "$SG_ID" ] || [ "$SG_ID" = "None" ]; then
    echo -e "${RED}Error: Security Group not found${NC}"
    exit 1
fi
echo -e "Security Group ID: ${GREEN}$SG_ID${NC}"
echo ""

# Step 2: Check Current Outbound Rules
echo -e "${YELLOW}[2/4] Checking Current Outbound Rules${NC}"
echo "Current egress rules:"
aws ec2 describe-security-groups \
    --group-ids "$SG_ID" \
    --query 'SecurityGroups[0].IpPermissionsEgress' \
    --output table

# Check if we have a rule allowing all outbound traffic
ALL_OUTBOUND=$(aws ec2 describe-security-groups \
    --group-ids "$SG_ID" \
    --query 'SecurityGroups[0].IpPermissionsEgress[?IpProtocol==`-1` && IpRanges[?CidrIp==`0.0.0.0/0`]]' \
    --output json)

echo ""

if [ "$ALL_OUTBOUND" = "[]" ] || [ -z "$ALL_OUTBOUND" ]; then
    echo -e "${YELLOW}No 'allow all outbound' rule found${NC}"
    echo -e "${YELLOW}Adding rule to allow all outbound traffic...${NC}"

    # Step 3: Add Outbound Rule
    echo -e "${YELLOW}[3/4] Adding Outbound Rule${NC}"
    aws ec2 authorize-security-group-egress \
        --group-id "$SG_ID" \
        --ip-permissions IpProtocol=-1,IpRanges='[{CidrIp=0.0.0.0/0}]' 2>&1 || \
        echo -e "${YELLOW}Rule may already exist${NC}"

    echo -e "${GREEN}✓ Outbound rule configured${NC}"
else
    echo -e "${GREEN}✓ Outbound traffic already allowed${NC}"
fi
echo ""

# Step 4: Test Connectivity
echo -e "${YELLOW}[4/4] Testing Connectivity to GitLab${NC}"
echo "GitLab Server: gitlab.ftgaming.cc ($GITLAB_IP)"
echo "Testing connection from EC2..."
echo ""

SSH_OPTS="-i $KEY_FILE -o StrictHostKeyChecking=no -o ConnectTimeout=10"

# Test ping
echo -e "${CYAN}Testing ICMP (ping)...${NC}"
ssh $SSH_OPTS ec2-user@$PUBLIC_IP "ping -c 3 $GITLAB_IP 2>&1 | tail -2" || true
echo ""

# Test SSH port
echo -e "${CYAN}Testing SSH port 22...${NC}"
ssh $SSH_OPTS ec2-user@$PUBLIC_IP "timeout 5 bash -c 'cat < /dev/null > /dev/tcp/$GITLAB_IP/22' && echo 'Port 22 is open' || echo 'Port 22 is closed or filtered'" 2>&1
echo ""

# Test Git clone
echo -e "${CYAN}Testing Git clone...${NC}"
CLONE_RESULT=$(ssh $SSH_OPTS ec2-user@$PUBLIC_IP 'cd /tmp && rm -rf bmm-rng-test && timeout 30 git clone git@gitlab.ftgaming.cc:core/bmm-rng.git bmm-rng-test 2>&1 && ls -d bmm-rng-test/.git 2>/dev/null && echo "SUCCESS" || echo "FAILED"')

if echo "$CLONE_RESULT" | grep -q "SUCCESS"; then
    echo -e "${GREEN}✓ Git clone successful!${NC}"
    ssh $SSH_OPTS ec2-user@$PUBLIC_IP 'rm -rf /tmp/bmm-rng-test'
else
    echo -e "${RED}✗ Git clone failed${NC}"
    echo "Output:"
    echo "$CLONE_RESULT"
fi
echo ""

# Summary
echo -e "${GREEN}"
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║                                                                  ║"
echo "║           Diagnostics Complete                                   ║"
echo "║                                                                  ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""
echo "If connection still fails, check:"
echo "1. GitLab server Security Group allows inbound from $PUBLIC_IP"
echo "2. Network ACLs in both VPCs"
echo "3. Route tables"
echo "4. VPC peering or transit gateway configuration (if different VPCs)"
echo ""
