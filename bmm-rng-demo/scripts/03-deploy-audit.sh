#!/bin/bash
# =============================================================================
# BMM RNG Demo - Live Audit Deployment Script
#
# THIS SCRIPT IS FOR BMM AUDIT - Run while auditors are watching
# It demonstrates:
#   1. The exact BMM_RNG.py file being used
#   2. SHA256 checksum verification
#   3. Live deployment to production
# =============================================================================

set -e

# Configuration
BMM_RNG_FILE="${BMM_RNG_FILE:-/Users/lonelyhsu/Downloads/BMM_RNG.py}"

# Load instance info
if [ ! -f instance-info.txt ]; then
    echo "Error: instance-info.txt not found. Run 01-create-ec2.sh first."
    exit 1
fi
source instance-info.txt

SSH_OPTS="-i $KEY_FILE -o StrictHostKeyChecking=no"

# Colors for visibility
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

clear
echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║                                                                  ║"
echo "║           BMM RNG AUDIT DEPLOYMENT                               ║"
echo "║                                                                  ║"
echo "║   This deployment is being performed for BMM audit purposes.    ║"
echo "║   All steps are logged and checksums are verified.              ║"
echo "║                                                                  ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""
echo "Timestamp: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo ""

# Step 1: Verify local BMM_RNG.py
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}STEP 1: Verify Local BMM_RNG.py File${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

if [ ! -f "$BMM_RNG_FILE" ]; then
    echo -e "${RED}ERROR: BMM_RNG.py not found at: $BMM_RNG_FILE${NC}"
    exit 1
fi

echo "File Location: $BMM_RNG_FILE"
echo ""
echo "File Info:"
ls -la "$BMM_RNG_FILE"
echo ""

LOCAL_CHECKSUM=$(shasum -a 256 "$BMM_RNG_FILE" | cut -d' ' -f1)
echo -e "${GREEN}LOCAL SHA256 CHECKSUM:${NC}"
echo -e "${CYAN}$LOCAL_CHECKSUM${NC}"
echo ""

# Step 2: Upload to server
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}STEP 2: Upload BMM_RNG.py to Server${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo "Target Server: $PUBLIC_IP (bmm.geminigame.cc)"
echo "Uploading..."
scp $SSH_OPTS "$BMM_RNG_FILE" ec2-user@$PUBLIC_IP:/home/ec2-user/bmm-rng-demo/BMM_RNG.py
echo -e "${GREEN}Upload complete!${NC}"
echo ""

# Step 3: Verify checksum on server
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}STEP 3: Verify Checksum on Server${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

REMOTE_CHECKSUM=$(ssh $SSH_OPTS ec2-user@$PUBLIC_IP "sha256sum /home/ec2-user/bmm-rng-demo/BMM_RNG.py | cut -d' ' -f1")
echo -e "${GREEN}REMOTE SHA256 CHECKSUM:${NC}"
echo -e "${CYAN}$REMOTE_CHECKSUM${NC}"
echo ""

if [ "$LOCAL_CHECKSUM" = "$REMOTE_CHECKSUM" ]; then
    echo -e "${GREEN}✓ CHECKSUM MATCH - File integrity verified!${NC}"
else
    echo -e "${RED}✗ CHECKSUM MISMATCH - Upload may be corrupted!${NC}"
    echo "Local:  $LOCAL_CHECKSUM"
    echo "Remote: $REMOTE_CHECKSUM"
    exit 1
fi
echo ""

# Step 4: Start service
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}STEP 4: Start Application Service${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

ssh $SSH_OPTS ec2-user@$PUBLIC_IP << 'REMOTE_SCRIPT'
cd /home/ec2-user/bmm-rng-demo

# Stop existing containers
docker-compose down 2>/dev/null || true

# Build and start
docker-compose build --no-cache
docker-compose up -d

# Wait for service
sleep 5

# Check status
echo ""
echo "Container Status:"
docker-compose ps
REMOTE_SCRIPT

echo ""

# Step 5: Verify service
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}STEP 5: Verify Service Status${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo "Checking API status..."
sleep 3
API_STATUS=$(curl -s "https://bmm.geminigame.cc/api/status" 2>/dev/null || echo '{"error":"connection failed"}')
echo "API Response:"
echo "$API_STATUS" | python3 -m json.tool 2>/dev/null || echo "$API_STATUS"
echo ""

# Final summary
echo -e "${GREEN}"
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║                                                                  ║"
echo "║           DEPLOYMENT COMPLETE                                    ║"
echo "║                                                                  ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  AUDIT VERIFICATION SUMMARY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  BMM_RNG.py SHA256:"
echo -e "  ${CYAN}$LOCAL_CHECKSUM${NC}"
echo ""
echo "  Service URL:"
echo -e "  ${CYAN}https://bmm.geminigame.cc${NC}"
echo ""
echo "  Deployment Time:"
echo "  $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "BMM auditors can now test at: https://bmm.geminigame.cc"
echo ""
