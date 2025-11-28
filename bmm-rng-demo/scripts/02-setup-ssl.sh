#!/bin/bash
# =============================================================================
# BMM RNG Demo - SSL Certificate Setup
# Uses Let's Encrypt (certbot) for bmm.geminigame.cc
# =============================================================================

set -e

# Load instance info
if [ ! -f instance-info.txt ]; then
    echo "Error: instance-info.txt not found. Run 01-create-ec2.sh first."
    exit 1
fi
source instance-info.txt

DOMAIN="bmm.geminigame.cc"
SSH_OPTS="-i $KEY_FILE -o StrictHostKeyChecking=no"

echo "=============================================="
echo "  BMM RNG Demo - SSL Setup"
echo "=============================================="
echo ""
echo "  Domain:    $DOMAIN"
echo "  Server:    $PUBLIC_IP"
echo ""

# Check DNS
echo "[1/3] Checking DNS resolution..."
RESOLVED_IP=$(dig +short $DOMAIN | tail -1)
if [ "$RESOLVED_IP" != "$PUBLIC_IP" ]; then
    echo "  WARNING: DNS not configured correctly!"
    echo "  Expected: $PUBLIC_IP"
    echo "  Got:      $RESOLVED_IP"
    echo ""
    echo "  Please configure DNS first:"
    echo "    $DOMAIN -> $PUBLIC_IP"
    echo ""
    read -p "  Continue anyway? (y/n): " CONTINUE
    if [ "$CONTINUE" != "y" ]; then
        exit 1
    fi
else
    echo "  DNS OK: $DOMAIN -> $PUBLIC_IP"
fi

# Install certbot and get certificate
echo ""
echo "[2/3] Installing certbot and obtaining certificate..."
ssh $SSH_OPTS ec2-user@$PUBLIC_IP << 'REMOTE_SCRIPT'
set -e

# Install certbot
sudo yum install -y certbot

# Stop any running services on port 80
sudo docker stop $(sudo docker ps -q) 2>/dev/null || true

# Get certificate (standalone mode)
sudo certbot certonly \
    --standalone \
    --non-interactive \
    --agree-tos \
    --email admin@geminigame.cc \
    -d bmm.geminigame.cc

# Create ssl directory for nginx
mkdir -p /home/ec2-user/bmm-rng-demo/ssl
sudo cp /etc/letsencrypt/live/bmm.geminigame.cc/fullchain.pem /home/ec2-user/bmm-rng-demo/ssl/
sudo cp /etc/letsencrypt/live/bmm.geminigame.cc/privkey.pem /home/ec2-user/bmm-rng-demo/ssl/
sudo chown -R ec2-user:ec2-user /home/ec2-user/bmm-rng-demo/ssl/

echo "SSL certificates installed successfully!"
REMOTE_SCRIPT

echo ""
echo "[3/3] Uploading application files..."
scp $SSH_OPTS ../Dockerfile ec2-user@$PUBLIC_IP:/home/ec2-user/bmm-rng-demo/
scp $SSH_OPTS ../docker-compose.yml ec2-user@$PUBLIC_IP:/home/ec2-user/bmm-rng-demo/
scp $SSH_OPTS ../nginx.conf ec2-user@$PUBLIC_IP:/home/ec2-user/bmm-rng-demo/
scp $SSH_OPTS ../app.py ec2-user@$PUBLIC_IP:/home/ec2-user/bmm-rng-demo/

echo ""
echo "=============================================="
echo "  SSL Setup Complete!"
echo "=============================================="
echo ""
echo "  SSL certificates installed for: $DOMAIN"
echo "  Application files uploaded."
echo ""
echo "  Ready for BMM audit!"
echo "  When audit starts, run: ./03-deploy-audit.sh"
echo ""
