#!/bin/bash

# Gate 服務監控命令參考
# 用途: 快速檢查 Gate 服務的健康狀態和資源使用
# 使用方式: ./gate_monitoring_commands.sh [arcade|hash|all]

set -e

# 顏色定義
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 函數：打印分隔線
print_separator() {
    echo -e "${BLUE}========================================${NC}"
}

# 函數：打印標題
print_header() {
    echo -e "${GREEN}$1${NC}"
    print_separator
}

# 函數：檢查 Arcade Gate
check_arcade_gate() {
    print_header "Arcade Gate 服務狀態"

    echo -e "${YELLOW}1. Pod 狀態${NC}"
    kubectl get pods -n arcade-gate-prd -o wide
    echo ""

    echo -e "${YELLOW}2. 記憶體使用${NC}"
    kubectl top pod -n arcade-gate-prd
    echo ""

    echo -e "${YELLOW}3. HPA 狀態${NC}"
    kubectl get hpa -n arcade-gate-prd
    echo ""

    echo -e "${YELLOW}4. StatefulSet 狀態${NC}"
    kubectl get statefulset -n arcade-gate-prd
    echo ""

    echo -e "${YELLOW}5. 最近事件${NC}"
    kubectl get events -n arcade-gate-prd --sort-by='.lastTimestamp' | tail -10
    echo ""

    echo -e "${YELLOW}6. 日誌總量${NC}"
    kubectl exec -n arcade-gate-prd arcade-gate-0 -- du -sh /app/log/ 2>/dev/null || echo "無法訪問日誌目錄"
    echo ""

    echo -e "${YELLOW}7. 活躍用戶數（最近 1000 條日誌）${NC}"
    USERS=$(kubectl exec -n arcade-gate-prd arcade-gate-0 -- tail -1000 /app/log/Gate-Server.log 2>/dev/null | grep -o 'loginname: [^ ,]*' | cut -d' ' -f2 | sort -u | wc -l)
    echo "唯一活躍用戶: $USERS"
    echo ""

    echo -e "${YELLOW}8. Stacktrace 錯誤數量${NC}"
    STACKTRACES=$(kubectl exec -n arcade-gate-prd arcade-gate-0 -- sh -c 'ls /app/log/GateServer*.stacktrace.log 2>/dev/null | wc -l')
    if [ "$STACKTRACES" -gt 0 ]; then
        echo -e "${RED}發現 $STACKTRACES 個 stacktrace 文件${NC}"
    else
        echo -e "${GREEN}無 stacktrace 錯誤${NC}"
    fi
    echo ""

    echo -e "${YELLOW}9. 系統負載${NC}"
    kubectl exec -n arcade-gate-prd arcade-gate-0 -- uptime 2>/dev/null
    echo ""

    echo -e "${YELLOW}10. 進程狀態${NC}"
    kubectl exec -n arcade-gate-prd arcade-gate-0 -- ps aux 2>/dev/null | grep GateServer | grep -v grep
    echo ""
}

# 函數：檢查 Hash Gate
check_hash_gate() {
    print_header "Hash Gate 服務狀態"

    echo -e "${YELLOW}1. Pod 狀態${NC}"
    kubectl get pods -n hash-gate-prd -o wide
    echo ""

    echo -e "${YELLOW}2. 記憶體使用${NC}"
    kubectl top pod -n hash-gate-prd
    MEM_USAGE=$(kubectl top pod -n hash-gate-prd --no-headers | awk '{print $3}' | sed 's/Mi//')
    MEM_PERCENT=$(echo "scale=1; $MEM_USAGE / 2048 * 100" | bc)

    if (( $(echo "$MEM_PERCENT > 70" | bc -l) )); then
        echo -e "${RED}警告: 記憶體使用 ${MEM_PERCENT}% 超過 70% 閾值${NC}"
    elif (( $(echo "$MEM_PERCENT > 60" | bc -l) )); then
        echo -e "${YELLOW}注意: 記憶體使用 ${MEM_PERCENT}%，接近警戒值${NC}"
    else
        echo -e "${GREEN}記憶體使用 ${MEM_PERCENT}%，正常${NC}"
    fi
    echo ""

    echo -e "${YELLOW}3. HPA 狀態${NC}"
    kubectl get hpa -n hash-gate-prd
    echo ""

    echo -e "${YELLOW}4. StatefulSet 狀態${NC}"
    kubectl get statefulset -n hash-gate-prd
    echo ""

    echo -e "${YELLOW}5. 最近事件${NC}"
    kubectl get events -n hash-gate-prd --sort-by='.lastTimestamp' | tail -10
    echo ""

    echo -e "${YELLOW}6. 日誌總量${NC}"
    LOG_SIZE=$(kubectl exec -n hash-gate-prd hash-gate-0 -- du -sh /app/log/ 2>/dev/null | awk '{print $1}')
    echo "日誌總大小: $LOG_SIZE"
    if [[ "$LOG_SIZE" == *G* ]]; then
        SIZE_NUM=$(echo "$LOG_SIZE" | sed 's/G//')
        if (( $(echo "$SIZE_NUM > 30" | bc -l) )); then
            echo -e "${RED}警告: 日誌大小 $LOG_SIZE 超過 30GB${NC}"
        fi
    fi
    echo ""

    echo -e "${YELLOW}7. 活躍用戶數（最近 1000 條日誌）${NC}"
    USERS=$(kubectl exec -n hash-gate-prd hash-gate-0 -- tail -1000 /app/log/Gate-Server.log 2>/dev/null | grep -o 'loginname: [^ ,]*' | cut -d' ' -f2 | sort -u | wc -l)
    echo "唯一活躍用戶: $USERS"
    echo ""

    echo -e "${YELLOW}8. Stacktrace 錯誤數量${NC}"
    STACKTRACES=$(kubectl exec -n hash-gate-prd hash-gate-0 -- sh -c 'ls /app/log/GateServer*.stacktrace.log 2>/dev/null | wc -l')
    if [ "$STACKTRACES" -gt 0 ]; then
        echo -e "${RED}發現 $STACKTRACES 個 stacktrace 文件${NC}"
    else
        echo -e "${GREEN}無 stacktrace 錯誤${NC}"
    fi
    echo ""

    echo -e "${YELLOW}9. 系統負載${NC}"
    kubectl exec -n hash-gate-prd hash-gate-0 -- uptime 2>/dev/null
    echo ""

    echo -e "${YELLOW}10. 進程狀態${NC}"
    kubectl exec -n hash-gate-prd hash-gate-0 -- ps aux 2>/dev/null | grep GateServer | grep -v grep
    echo ""

    echo -e "${YELLOW}11. 最近 5 次日誌輪換${NC}"
    kubectl exec -n hash-gate-prd hash-gate-0 -- sh -c 'ls -lht /app/log/Gate-Server-*.log 2>/dev/null | head -5'
    echo ""
}

# 函數：比較分析
compare_gates() {
    print_header "Gate 服務比較分析"

    echo -e "${YELLOW}記憶體使用對比${NC}"
    echo "Arcade Gate:"
    kubectl top pod -n arcade-gate-prd 2>/dev/null || echo "  無法獲取資料"
    echo "Hash Gate:"
    kubectl top pod -n hash-gate-prd 2>/dev/null || echo "  無法獲取資料"
    echo ""

    echo -e "${YELLOW}日誌大小對比${NC}"
    echo -n "Arcade Gate: "
    kubectl exec -n arcade-gate-prd arcade-gate-0 -- du -sh /app/log/ 2>/dev/null | awk '{print $1}' || echo "無法獲取"
    echo -n "Hash Gate: "
    kubectl exec -n hash-gate-prd hash-gate-0 -- du -sh /app/log/ 2>/dev/null | awk '{print $1}' || echo "無法獲取"
    echo ""

    echo -e "${YELLOW}活躍用戶對比${NC}"
    ARCADE_USERS=$(kubectl exec -n arcade-gate-prd arcade-gate-0 -- tail -1000 /app/log/Gate-Server.log 2>/dev/null | grep -o 'loginname: [^ ,]*' | cut -d' ' -f2 | sort -u | wc -l)
    HASH_USERS=$(kubectl exec -n hash-gate-prd hash-gate-0 -- tail -1000 /app/log/Gate-Server.log 2>/dev/null | grep -o 'loginname: [^ ,]*' | cut -d' ' -f2 | sort -u | wc -l)
    echo "Arcade Gate: $ARCADE_USERS 用戶"
    echo "Hash Gate: $HASH_USERS 用戶"
    RATIO=$(echo "scale=2; $HASH_USERS / $ARCADE_USERS" | bc)
    echo "比率: ${RATIO}x"
    echo ""
}

# 函數：顯示詳細日誌資訊
show_log_details() {
    local NAMESPACE=$1
    local POD=$2

    print_header "$POD 日誌詳細資訊"

    echo -e "${YELLOW}1. 日誌文件列表（最新 10 個）${NC}"
    kubectl exec -n $NAMESPACE $POD -- sh -c 'ls -lht /app/log/ | head -11'
    echo ""

    echo -e "${YELLOW}2. 壓縮日誌歸檔${NC}"
    kubectl exec -n $NAMESPACE $POD -- sh -c 'ls -lh /app/log/*.tar.gz 2>/dev/null | tail -5' || echo "無壓縮日誌"
    echo ""

    echo -e "${YELLOW}3. 日誌輪換速度（最近 5 個文件的時間間隔）${NC}"
    kubectl exec -n $NAMESPACE $POD -- sh -c 'ls -lt /app/log/Gate-Server-*.log 2>/dev/null | head -5 | awk "{print \$6, \$7, \$8, \$9}"'
    echo ""
}

# 函數：健康檢查摘要
health_summary() {
    print_header "Gate 服務健康摘要"

    # Arcade Gate
    echo -e "${GREEN}Arcade Gate:${NC}"
    ARCADE_MEM=$(kubectl top pod -n arcade-gate-prd --no-headers 2>/dev/null | awk '{print $3}' | sed 's/Mi//')
    ARCADE_PERCENT=$(echo "scale=0; $ARCADE_MEM / 2048 * 100" | bc)

    if [ "$ARCADE_PERCENT" -lt 50 ]; then
        echo -e "  記憶體: ${GREEN}$ARCADE_PERCENT% (健康)${NC}"
    elif [ "$ARCADE_PERCENT" -lt 70 ]; then
        echo -e "  記憶體: ${YELLOW}$ARCADE_PERCENT% (良好)${NC}"
    else
        echo -e "  記憶體: ${RED}$ARCADE_PERCENT% (警告)${NC}"
    fi

    ARCADE_STACK=$(kubectl exec -n arcade-gate-prd arcade-gate-0 -- sh -c 'ls /app/log/GateServer*.stacktrace.log 2>/dev/null | wc -l')
    if [ "$ARCADE_STACK" -eq 0 ]; then
        echo -e "  穩定性: ${GREEN}無錯誤${NC}"
    else
        echo -e "  穩定性: ${YELLOW}發現 $ARCADE_STACK 個 stacktrace${NC}"
    fi

    # Hash Gate
    echo -e "${GREEN}Hash Gate:${NC}"
    HASH_MEM=$(kubectl top pod -n hash-gate-prd --no-headers 2>/dev/null | awk '{print $3}' | sed 's/Mi//')
    HASH_PERCENT=$(echo "scale=0; $HASH_MEM / 2048 * 100" | bc)

    if [ "$HASH_PERCENT" -lt 50 ]; then
        echo -e "  記憶體: ${GREEN}$HASH_PERCENT% (健康)${NC}"
    elif [ "$HASH_PERCENT" -lt 70 ]; then
        echo -e "  記憶體: ${YELLOW}$HASH_PERCENT% (良好)${NC}"
    else
        echo -e "  記憶體: ${RED}$HASH_PERCENT% (警告)${NC}"
    fi

    HASH_STACK=$(kubectl exec -n hash-gate-prd hash-gate-0 -- sh -c 'ls /app/log/GateServer*.stacktrace.log 2>/dev/null | wc -l')
    if [ "$HASH_STACK" -eq 0 ]; then
        echo -e "  穩定性: ${GREEN}無錯誤${NC}"
    else
        echo -e "  穩定性: ${YELLOW}發現 $HASH_STACK 個 stacktrace${NC}"
    fi

    echo ""
    echo -e "${BLUE}建議行動:${NC}"
    if [ "$HASH_PERCENT" -gt 70 ]; then
        echo -e "${RED}🔴 Hash Gate 記憶體使用超過 70%，需要緊急處理${NC}"
        echo "   - 調整日誌等級"
        echo "   - 實施日誌過濾"
        echo "   - 考慮增加資源配置"
    elif [ "$HASH_PERCENT" -gt 60 ]; then
        echo -e "${YELLOW}🟡 Hash Gate 記憶體接近警戒值，建議預防性優化${NC}"
    fi

    if [ "$ARCADE_STACK" -gt 0 ]; then
        echo -e "${YELLOW}🟡 Arcade Gate 存在 stacktrace 錯誤，建議修復${NC}"
        echo "   - 檢查 loyalty/client.go:106 的 nil pointer 問題"
    fi
}

# 主程序
case "${1:-all}" in
    arcade)
        check_arcade_gate
        ;;
    hash)
        check_hash_gate
        ;;
    compare)
        compare_gates
        ;;
    logs-arcade)
        show_log_details "arcade-gate-prd" "arcade-gate-0"
        ;;
    logs-hash)
        show_log_details "hash-gate-prd" "hash-gate-0"
        ;;
    summary)
        health_summary
        ;;
    all)
        health_summary
        echo ""
        check_arcade_gate
        echo ""
        check_hash_gate
        echo ""
        compare_gates
        ;;
    *)
        echo "使用方式: $0 [arcade|hash|compare|logs-arcade|logs-hash|summary|all]"
        echo ""
        echo "選項:"
        echo "  arcade        - 檢查 Arcade Gate"
        echo "  hash          - 檢查 Hash Gate"
        echo "  compare       - 比較兩個服務"
        echo "  logs-arcade   - Arcade Gate 日誌詳情"
        echo "  logs-hash     - Hash Gate 日誌詳情"
        echo "  summary       - 健康摘要（預設）"
        echo "  all           - 完整檢查"
        exit 1
        ;;
esac
