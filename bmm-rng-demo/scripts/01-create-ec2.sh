#!/bin/bash
# =============================================================================
# BMM RNG Demo - EC2 Infrastructure Setup
# Creates: Key Pair, Security Group, EC2 Instance
# =============================================================================

set -e

# Configuration (can be overridden by environment variables)
AWS_PROFILE="${AWS_PROFILE:-gemini-pro_ck}"
REGION="${AWS_DEFAULT_REGION:-ap-east-1}"  # Hong Kong
KEY_NAME="bmm-rng-demo-key"
SECURITY_GROUP_NAME="bmm-rng-demo-sg"
INSTANCE_TYPE="t3.small"
INSTANCE_NAME="bmm-rng-demo"

# Export profile for all aws commands
export AWS_PROFILE
export AWS_DEFAULT_REGION="$REGION"

# Get latest Amazon Linux 2023 AMI dynamically
echo "Looking up latest Amazon Linux 2023 AMI for $REGION..."
AMI_ID=$(aws ec2 describe-images \
    --owners amazon \
    --filters "Name=name,Values=al2023-ami-2023*-x86_64" "Name=state,Values=available" \
    --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
    --output text)

if [ -z "$AMI_ID" ] || [ "$AMI_ID" = "None" ]; then
    echo "Error: Could not find Amazon Linux 2023 AMI"
    exit 1
fi
echo "Using AMI: $AMI_ID"

echo "=============================================="
echo "  BMM RNG Demo - EC2 Setup"
echo "=============================================="
echo ""
echo "  AWS Profile: $AWS_PROFILE"
echo "  Region:      $REGION"
echo "  AMI:         $AMI_ID"
echo ""

# Step 1: Create Key Pair
echo "[1/4] Creating Key Pair: $KEY_NAME"
if aws ec2 describe-key-pairs --key-names "$KEY_NAME" --region "$REGION" 2>/dev/null; then
    echo "  Key pair already exists, skipping..."
else
    aws ec2 create-key-pair \
        --key-name "$KEY_NAME" \
        --region "$REGION" \
        --query 'KeyMaterial' \
        --output text > "${KEY_NAME}.pem"
    chmod 400 "${KEY_NAME}.pem"
    echo "  Created: ${KEY_NAME}.pem"
fi

# Step 2: Get Default VPC
echo ""
echo "[2/4] Getting Default VPC..."
VPC_ID=$(aws ec2 describe-vpcs \
    --region "$REGION" \
    --filters "Name=isDefault,Values=true" \
    --query 'Vpcs[0].VpcId' \
    --output text)
echo "  VPC ID: $VPC_ID"

# Step 3: Create Security Group
echo ""
echo "[3/4] Creating Security Group: $SECURITY_GROUP_NAME"
SG_ID=$(aws ec2 describe-security-groups \
    --region "$REGION" \
    --filters "Name=group-name,Values=$SECURITY_GROUP_NAME" \
    --query 'SecurityGroups[0].GroupId' \
    --output text 2>/dev/null || echo "None")

if [ "$SG_ID" != "None" ] && [ -n "$SG_ID" ]; then
    echo "  Security group already exists: $SG_ID"
else
    SG_ID=$(aws ec2 create-security-group \
        --group-name "$SECURITY_GROUP_NAME" \
        --description "BMM RNG Demo - HTTP/HTTPS/SSH access" \
        --vpc-id "$VPC_ID" \
        --region "$REGION" \
        --query 'GroupId' \
        --output text)

    # Add rules
    aws ec2 authorize-security-group-ingress \
        --group-id "$SG_ID" \
        --region "$REGION" \
        --protocol tcp --port 22 --cidr 0.0.0.0/0

    aws ec2 authorize-security-group-ingress \
        --group-id "$SG_ID" \
        --region "$REGION" \
        --protocol tcp --port 80 --cidr 0.0.0.0/0

    aws ec2 authorize-security-group-ingress \
        --group-id "$SG_ID" \
        --region "$REGION" \
        --protocol tcp --port 443 --cidr 0.0.0.0/0

    echo "  Created: $SG_ID"
fi

# Step 4: Launch EC2 Instance
echo ""
echo "[4/4] Launching EC2 Instance..."

# User data script for initial setup
USER_DATA=$(cat <<'EOF'
#!/bin/bash
yum update -y
yum install -y docker git
systemctl start docker
systemctl enable docker
usermod -a -G docker ec2-user

# Install Docker Compose
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Create app directory
mkdir -p /home/ec2-user/bmm-rng-demo
chown ec2-user:ec2-user /home/ec2-user/bmm-rng-demo
EOF
)

INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --security-group-ids "$SG_ID" \
    --region "$REGION" \
    --user-data "$USER_DATA" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
    --query 'Instances[0].InstanceId' \
    --output text)

echo "  Instance ID: $INSTANCE_ID"
echo ""
echo "Waiting for instance to be running..."
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --region "$REGION"

# Get Public IP
PUBLIC_IP=$(aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --region "$REGION" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text)

echo ""
echo "=============================================="
echo "  EC2 Instance Created Successfully!"
echo "=============================================="
echo ""
echo "  Instance ID:  $INSTANCE_ID"
echo "  Public IP:    $PUBLIC_IP"
echo "  Key File:     ${KEY_NAME}.pem"
echo ""
echo "  SSH Command:"
echo "    ssh -i ${KEY_NAME}.pem ec2-user@$PUBLIC_IP"
echo ""
echo "  Next Steps:"
echo "    1. Configure DNS: bmm.geminigame.cc -> $PUBLIC_IP"
echo "    2. Run: ./02-setup-ssl.sh"
echo "    3. Run: ./03-deploy-audit.sh (during BMM audit)"
echo ""

# Save instance info
cat > instance-info.txt <<EOL
INSTANCE_ID=$INSTANCE_ID
PUBLIC_IP=$PUBLIC_IP
KEY_FILE=${KEY_NAME}.pem
REGION=$REGION
EOL
echo "Instance info saved to: instance-info.txt"
