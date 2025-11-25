# Bingo 遊戲服務記憶體使用快速參考表

**數據收集時間**: 2025-11-07
**Pod 運行時長**: 4 天 7 小時
**所有服務重啟次數**: 0

---

## 🚨 立即處理（超過 HPA 閾值 80%）

| 服務 | 使用 | Request | 使用率 | HPA | 建議 Request | 建議 Limit | 優先級 |
|-----|------|---------|--------|-----|-------------|-----------|--------|
| **cavebingo** | 122 Mi | 140 Mi | **87%** | 87%/80% ⚠️ | 200 Mi (+60) | 350 Mi (+130) | 🚨 P0 |
| **caribbeanbingo** | 128 Mi | 150 Mi | **85%** | 85%/80% ⚠️ | 220 Mi (+70) | 400 Mi (+150) | 🚨 P0 |

---

## 🔥 嚴重過度配置（資源浪費）

| 服務 | 使用 | Request | Limit | 使用率 | 建議 Request | 建議 Limit | 可節省 |
|-----|------|---------|-------|--------|-------------|-----------|-------|
| **bonusbingo** | 391 Mi | 1536 Mi | 3072 Mi | 25% | 600 Mi | 1024 Mi | **-936 Mi** |

---

## ⚠️ 可優化（Request 過高）

| 服務 | 使用 | Request | Limit | 使用率 | 建議 Request | 可節省 |
|-----|------|---------|-------|--------|-------------|-------|
| **bingobells** | 108 Mi | 400 Mi | 700 Mi | 27% | 220 Mi | -180 Mi |
| **bingbingbingo** | 121 Mi | 400 Mi | 700 Mi | 30% | 250 Mi | -150 Mi |
| **maplebingo** | 132 Mi | 400 Mi | 600 Mi | 33% | 270 Mi | -130 Mi |
| **egghuntbingo** | 145 Mi | 500 Mi | 800 Mi | 29% | 300 Mi | -200 Mi |
| **magicbingo** | 144 Mi | 500 Mi | 800 Mi | 28% | 300 Mi | -200 Mi |

---

## ✅ 配置合理

| 服務 | 使用 | Request | Limit | 使用率 | HPA | 評估 |
|-----|------|---------|-------|--------|-----|------|
| **arcadebingo** | 137 Mi | 400 Mi | 700 Mi | 34% | 34%/80% | ✅ 合理 |
| **odinbingo** | 133 Mi | 200 Mi | 320 Mi | 66% | 66%/80% | ✅ 較理想 |

---

## 總資源影響

### 優化後資源節省

| 項目 | Request | Limit |
|-----|---------|-------|
| **總增加** | +130 Mi | +280 Mi |
| **總減少** | -1,796 Mi | ~-2,100 Mi |
| **淨節省** | **-1,666 Mi** (~1.63 Gi) | **~-1,820 Mi** (~1.78 Gi) |

### 實施優先級

1. **P0 - 立即** (24h 內): cavebingo, caribbeanbingo
2. **P1 - 高** (1 週內): bonusbingo
3. **P2 - 中** (2-4 週內): 其他 5 個服務

---

## 與 ForestTeaParty 對比

| 指標 | ForestTeaParty | Bingo (最佳) | Bingo (最差) | Bingo (平均) |
|------|---------------|-------------|-------------|-------------|
| 記憶體使用 | 177 Mi | 108 Mi | 391 Mi | 156 Mi |
| Request | 600 Mi | 140 Mi | 1536 Mi | 512 Mi |
| 使用率 | 29.5% | 27% | 87% | 44% |
| HPA 狀態 | ✅ 29%/80% | 🚨 87%/80% | ✅ 25%/80% | ~44%/80% |
| 配置一致性 | 統一 | 差異 11 倍 | - | 不一致 |

**關鍵差異**:
- ForestTeaParty: 保守配置，單一服務，統一標準
- Bingo Games: 配置範圍極大（140Mi - 1536Mi），缺乏標準化

---

## 快速執行指令

### 檢查當前狀態
```bash
# 檢查所有 Bingo 服務記憶體使用
for ns in arcadebingo-prd bingbingbingo-prd bingobells-prd bonusbingo-prd caribbeanbingo-prd cavebingo-prd egghuntbingo-prd magicbingo-prd maplebingo-prd odinbingo-prd; do
  echo "=== $ns ==="
  kubectl top pod -n $ns
  kubectl get hpa -n $ns
done
```

### 調整資源配置範例（cavebingo）
```bash
# 1. 備份當前配置
kubectl get statefulset cavebingo -n cavebingo-prd -o yaml > cavebingo-backup.yaml

# 2. 編輯配置
kubectl edit statefulset cavebingo -n cavebingo-prd

# 3. 在 resources 區段修改為:
# resources:
#   requests:
#     memory: "200Mi"
#   limits:
#     memory: "350Mi"

# 4. 檢查 rollout 狀態
kubectl rollout status statefulset/cavebingo -n cavebingo-prd

# 5. 驗證新配置
kubectl get pod cavebingo-0 -n cavebingo-prd -o yaml | grep -A 10 resources:
kubectl top pod -n cavebingo-prd
```

---

**報告生成**: 2025-11-07
**下次檢查**: 調整後 7 天
