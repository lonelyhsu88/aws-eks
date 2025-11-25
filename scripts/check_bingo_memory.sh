#!/bin/bash

# Bingo Games Memory Usage Monitoring Script
# Purpose: Quick health check for all Bingo game services
# Usage: ./check_bingo_memory.sh [--verbose] [--alert-only]

set -euo pipefail

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
BINGO_SERVICES=(
    "arcadebingo-prd"
    "bingbingbingo-prd"
    "bingobells-prd"
    "bonusbingo-prd"
    "caribbeanbingo-prd"
    "cavebingo-prd"
    "egghuntbingo-prd"
    "magicbingo-prd"
    "maplebingo-prd"
    "odinbingo-prd"
)

HPA_THRESHOLD=80
WARN_THRESHOLD=75
CRITICAL_THRESHOLD=85

VERBOSE=false
ALERT_ONLY=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose)
            VERBOSE=true
            shift
            ;;
        --alert-only)
            ALERT_ONLY=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--verbose] [--alert-only]"
            exit 1
            ;;
    esac
done

# Function to get memory usage in Mi
get_memory_usage() {
    local namespace=$1
    local pod=$(kubectl get pods -n "$namespace" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

    if [[ -z "$pod" ]]; then
        echo "0"
        return
    fi

    local mem=$(kubectl top pod -n "$namespace" 2>/dev/null | grep "$pod" | awk '{print $3}' | sed 's/Mi//')
    echo "${mem:-0}"
}

# Function to get memory request in Mi
get_memory_request() {
    local namespace=$1
    local request=$(kubectl get pod -n "$namespace" -o jsonpath='{.items[0].spec.containers[0].resources.requests.memory}' 2>/dev/null | sed 's/Mi//')
    echo "${request:-0}"
}

# Function to get memory limit in Mi
get_memory_limit() {
    local namespace=$1
    local limit=$(kubectl get pod -n "$namespace" -o jsonpath='{.items[0].spec.containers[0].resources.limits.memory}' 2>/dev/null)

    # Handle Gi units
    if [[ "$limit" == *"Gi"* ]]; then
        limit=$(echo "$limit" | sed 's/Gi//')
        limit=$((limit * 1024))
    else
        limit=$(echo "$limit" | sed 's/Mi//')
    fi

    echo "${limit:-0}"
}

# Function to get HPA status
get_hpa_status() {
    local namespace=$1
    local hpa_status=$(kubectl get hpa -n "$namespace" 2>/dev/null | tail -n 1 | awk '{print $4}')
    echo "${hpa_status:-N/A}"
}

# Function to get pod restart count
get_restart_count() {
    local namespace=$1
    local restarts=$(kubectl get pod -n "$namespace" -o jsonpath='{.items[0].status.containerStatuses[0].restartCount}' 2>/dev/null)
    echo "${restarts:-0}"
}

# Function to calculate percentage
calc_percentage() {
    local usage=$1
    local request=$2

    if [[ $request -eq 0 ]]; then
        echo "0"
        return
    fi

    echo "$((usage * 100 / request))"
}

# Function to get status icon
get_status_icon() {
    local percentage=$1

    if [[ $percentage -ge $CRITICAL_THRESHOLD ]]; then
        echo "🚨"
    elif [[ $percentage -ge $WARN_THRESHOLD ]]; then
        echo "⚠️ "
    else
        echo "✅"
    fi
}

# Function to get status color
get_status_color() {
    local percentage=$1

    if [[ $percentage -ge $CRITICAL_THRESHOLD ]]; then
        echo "$RED"
    elif [[ $percentage -ge $WARN_THRESHOLD ]]; then
        echo "$YELLOW"
    else
        echo "$GREEN"
    fi
}

# Header
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Bingo Games Memory Usage Monitor${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "Thresholds:"
echo "  - Warning:  >= ${WARN_THRESHOLD}%"
echo "  - Critical: >= ${CRITICAL_THRESHOLD}%"
echo "  - HPA:      ${HPA_THRESHOLD}%"
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl not found${NC}"
    exit 1
fi

# Array to store results
declare -a results

# Collect data
echo "Collecting data..."
echo ""

for namespace in "${BINGO_SERVICES[@]}"; do
    # Get metrics
    usage=$(get_memory_usage "$namespace")
    request=$(get_memory_request "$namespace")
    limit=$(get_memory_limit "$namespace")
    hpa=$(get_hpa_status "$namespace")
    restarts=$(get_restart_count "$namespace")

    # Calculate percentage
    if [[ $request -gt 0 ]]; then
        percentage=$(calc_percentage "$usage" "$request")
    else
        percentage=0
    fi

    # Store result
    results+=("$namespace|$usage|$request|$limit|$percentage|$hpa|$restarts")
done

# Sort results by percentage (descending)
IFS=$'\n' sorted_results=($(sort -t'|' -k5 -rn <<<"${results[*]}"))
unset IFS

# Display results
if [[ "$ALERT_ONLY" == true ]]; then
    echo -e "${YELLOW}Showing only alerts (>= ${WARN_THRESHOLD}%)${NC}"
    echo ""
fi

printf "%-20s | %8s | %8s | %8s | %6s | %10s | %4s | %s\n" \
    "Service" "Usage" "Request" "Limit" "Usage%" "HPA" "RS" "Status"
echo "--------------------------------------------------------------------------------"

alert_count=0
critical_count=0

for result in "${sorted_results[@]}"; do
    IFS='|' read -r namespace usage request limit percentage hpa restarts <<< "$result"

    # Get service name (remove -prd suffix)
    service_name=${namespace%-prd}

    # Get status
    icon=$(get_status_icon "$percentage")
    color=$(get_status_color "$percentage")

    # Count alerts
    if [[ $percentage -ge $CRITICAL_THRESHOLD ]]; then
        ((critical_count++))
    fi
    if [[ $percentage -ge $WARN_THRESHOLD ]]; then
        ((alert_count++))
    fi

    # Skip if alert-only and below threshold
    if [[ "$ALERT_ONLY" == true && $percentage -lt $WARN_THRESHOLD ]]; then
        continue
    fi

    # Display row
    printf "${color}%-20s${NC} | %6s Mi | %6s Mi | %6s Mi | %5s%% | %10s | %4s | %s\n" \
        "$service_name" "$usage" "$request" "$limit" "$percentage" "$hpa" "$restarts" "$icon"
done

# Summary
echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "Total Services:    ${#BINGO_SERVICES[@]}"
echo -e "Critical (>= ${CRITICAL_THRESHOLD}%): ${RED}${critical_count}${NC}"
echo -e "Warnings (>= ${WARN_THRESHOLD}%): ${YELLOW}${alert_count}${NC}"
echo -e "Healthy:           ${GREEN}$((${#BINGO_SERVICES[@]} - alert_count))${NC}"
echo ""

# Recommendations
if [[ $critical_count -gt 0 ]]; then
    echo -e "${RED}⚠️  CRITICAL: $critical_count service(s) need immediate attention!${NC}"
    echo ""
    echo "Recommended actions:"
    for result in "${sorted_results[@]}"; do
        IFS='|' read -r namespace usage request limit percentage hpa restarts <<< "$result"

        if [[ $percentage -ge $CRITICAL_THRESHOLD ]]; then
            service_name=${namespace%-prd}
            suggested_request=$((usage * 150 / 100))  # 1.5x current usage

            echo -e "${YELLOW}  - $service_name: Increase request from ${request}Mi to ${suggested_request}Mi${NC}"
        fi
    done
    echo ""
elif [[ $alert_count -gt 0 ]]; then
    echo -e "${YELLOW}⚠️  WARNING: $alert_count service(s) approaching limits${NC}"
    echo "  Consider reviewing these services during next maintenance window."
    echo ""
else
    echo -e "${GREEN}✅ All services are healthy!${NC}"
    echo ""
fi

# Verbose output
if [[ "$VERBOSE" == true ]]; then
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Detailed Analysis${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    for namespace in "${BINGO_SERVICES[@]}"; do
        echo -e "${BLUE}--- $namespace ---${NC}"

        echo "Pod Status:"
        kubectl get pods -n "$namespace" 2>/dev/null || echo "  No pods found"

        echo ""
        echo "HPA Status:"
        kubectl get hpa -n "$namespace" 2>/dev/null || echo "  No HPA found"

        echo ""
        echo "Recent Events:"
        kubectl get events -n "$namespace" --sort-by='.lastTimestamp' 2>/dev/null | tail -n 3 || echo "  No events"

        echo ""
        echo "----------------------------------------"
        echo ""
    done
fi

# Exit code based on status
if [[ $critical_count -gt 0 ]]; then
    exit 2
elif [[ $alert_count -gt 0 ]]; then
    exit 1
else
    exit 0
fi
