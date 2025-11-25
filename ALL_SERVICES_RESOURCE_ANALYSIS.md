# EKS 所有生產服務資源分析報告

**分析時間**: 2025-11-07
**分析範圍**: 所有 `-prd` namespace 的服務 (75 個服務)
**數據來源**: kubectl top pods, kubectl get statefulsets/deployments

---

## 📊 執行摘要

### 整體統計

- **總服務數量**: 75 個生產服務
- **StatefulSets**: 67 個 (遊戲服務)
- **Deployments**: 8 個 (API 服務)

### 嚴重度分類

| 嚴重度 | 服務數量 | 定義 | 風險 |
|--------|---------|------|------|
| 🔴 **Critical** | 3 | Memory 使用率 > 100% | OOMKilled 風險極高 |
| 🟡 **Warning** | 8 | Memory 使用率 80-100% | 接近資源上限 |
| 🟢 **Normal** | 56 | Memory 使用率 < 80% | 資源配置合理 |
| ⚠️ **Corrupted** | 3 | 配置值異常 | 需要修復配置 |
| 🔵 **Over-provisioned** | 5 | 使用率 < 20% | 可優化降低成本 |

---

## 🔴 Critical - 需立即處理 (P0)

### 1. forestteaparty-prd ⚠️ **最嚴重**

```yaml
Current Status:
  Memory Usage: 523Mi
  Memory Request: 300Mi
  Memory Limit: 600Mi
  Utilization: 174% ⚠️ (相比 request)

Current Configuration:
  resources:
    requests:
      cpu: 100m
      memory: 300Mi
    limits:
      cpu: 500m
      memory: 600Mi

Recommended Configuration:
  resources:
    requests:
      cpu: 50m          # 實際使用 34m，預留 buffer
      memory: 560Mi     # 略高於實際使用 523Mi
    limits:
      cpu: 200m
      memory: 1Gi       # 提供 90% buffer 應對流量突增
```

**問題分析**:
- ✅✅✅ Memory request 嚴重不足：實際使用 523Mi vs 配置 300Mi
- ✅✅✅ HPA 基於 request 計算，導致錯誤的 174% 使用率
- ✅✅ Memory limit 600Mi 太低，流量突增時會 OOMKilled
- ✅✅ 已有詳細分析報告: `FORESTTEAPARTY_RESOURCE_ANALYSIS.md`, `FORESTTEAPARTY_DEEP_DIVE_ANALYSIS.md`

**影響**:
- 200 concurrent WebSocket connections
- 4 個遊戲桌同時運行
- 32 個資料庫連接池
- 流量突增 +30% 會觸發 OOM

**實施優先級**: P0 - 立即修復

---

### 2. luckydropcoc2-prd

```yaml
Current Status:
  Memory Usage: 287Mi
  Memory Request: 200Mi
  Memory Limit: 1Gi
  Utilization: 143% ⚠️

Current Configuration:
  resources:
    requests:
      cpu: 40m
      memory: 200Mi
    limits:
      cpu: 120m
      memory: 1Gi

Recommended Configuration:
  resources:
    requests:
      cpu: 30m          # 實際使用 20m
      memory: 320Mi     # 覆蓋實際使用 287Mi + 10% buffer
    limits:
      cpu: 150m
      memory: 1Gi       # 維持不變，提供充足 buffer
```

**問題分析**:
- ✅✅✅ Memory request 200Mi 遠低於實際使用 287Mi
- ✅✅ HPA 計算錯誤: 143% 使用率
- ✅ Limit 1Gi 足夠，但 request 需調整

**實施優先級**: P0 - 立即修復

---

### 3. wilddiggr-prd

```yaml
Current Status:
  Memory Usage: 590Mi
  Memory Request: 500Mi
  Memory Limit: 1Gi
  Utilization: 118% ⚠️

Current Configuration:
  resources:
    requests:
      cpu: 200m
      memory: 500Mi
    limits:
      cpu: 500m
      memory: 1Gi

Recommended Configuration:
  resources:
    requests:
      cpu: 50m          # 實際使用 36m
      memory: 640Mi     # 覆蓋實際使用 590Mi + 8% buffer
    limits:
      cpu: 250m
      memory: 1280Mi    # 提供更多 buffer (2.17x usage)
```

**問題分析**:
- ✅✅✅ Memory request 500Mi 低於實際使用 590Mi
- ✅✅ 已知有 nil pointer dereference bugs (376 stacktraces)
- ✅✅ 存在記憶體洩漏風險
- ⚠️ 需同時修復程式碼 bugs 和資源配置

**實施優先級**: P0 - 立即修復 (程式碼 + 配置)

**相關文件**: `SCRATCH_CARD_GAMES_STACKTRACE_ANALYSIS.md`

---

## 🟡 Warning - 需要關注 (P1)

### 4. limbone-prd

```yaml
Current Status:
  Memory Usage: 184Mi
  Memory Request: 200Mi
  Utilization: 92%

Recommended Configuration:
  resources:
    requests:
      cpu: 25m
      memory: 200Mi     # 維持不變 (仍有 8% buffer)
    limits:
      cpu: 150m
      memory: 640Mi     # 增加 limit 提供更多安全空間
```

**建議**: 監控 1-2 天，如持續接近 200Mi 則調整為 220Mi

---

### 5. lostruins-prd

```yaml
Current Status:
  Memory Usage: 129Mi
  Memory Request: 140Mi
  Utilization: 92%

Recommended Configuration:
  resources:
    requests:
      cpu: 10m
      memory: 150Mi     # 小幅調整
    limits:
      cpu: 100m
      memory: 280Mi     # 增加 limit
```

---

### 6. exgameapi-prd (API Service)

```yaml
Current Status:
  Memory Usage: 233Mi
  Memory Request: 100Mi
  Memory Limit: 400Mi
  Utilization: 233% ⚠️⚠️

Recommended Configuration:
  resources:
    requests:
      cpu: 100m         # 實際使用 67m
      memory: 256Mi     # 覆蓋實際使用 233Mi + 10% buffer
    limits:
      cpu: 800m
      memory: 512Mi     # 提供 2x buffer
```

**問題分析**:
- ✅✅✅ API 服務但 request 嚴重不足
- ✅✅ 使用率高達 233%，HPA 計算完全錯誤

**實施優先級**: P1 - 高優先級修復

---

### 7. goldenclover-prd

```yaml
Current Status:
  Memory Usage: 228Mi
  Memory Request: 500Mi
  Utilization: 46%

Recommended Configuration:
  resources:
    requests:
      cpu: 20m
      memory: 260Mi     # 降低 request，更符合實際使用
    limits:
      cpu: 250m
      memory: 640Mi     # 降低 limit，節省資源
```

**建議**: 配置過度，可優化降低成本

---

### 8. mgmtapi-prd

```yaml
Current Status:
  Memory Usage: 110Mi
  Memory Request: 100Mi
  Utilization: 110% ⚠️

Recommended Configuration:
  resources:
    requests:
      cpu: 10m
      memory: 128Mi     # 增加至 128Mi
    limits:
      cpu: 100m
      memory: 256Mi     # 提供充足 buffer
```

---

### 9. limbocl-prd

```yaml
Current Status:
  Memory Usage: 130Mi
  Memory Request: 200Mi
  Utilization: 65%

Recommended Configuration:
  resources:
    requests:
      cpu: 15m
      memory: 150Mi     # 降低 request
    limits:
      cpu: 150m
      memory: 640Mi
```

---

### 10. egypthilo-prd

```yaml
Current Status:
  Memory Usage: 140Mi
  Memory Request: 200Mi
  Utilization: 70%

Recommended Configuration:
  resources:
    requests:
      cpu: 15m
      memory: 160Mi     # 降低 request
    limits:
      cpu: 150m
      memory: 640Mi
```

---

### 11. egghuntbingo-prd

```yaml
Current Status:
  Memory Usage: 148Mi
  Memory Request: 500Mi
  Utilization: 30%

Recommended Configuration:
  resources:
    requests:
      cpu: 15m
      memory: 170Mi     # 大幅降低 request
    limits:
      cpu: 120m
      memory: 480Mi     # 降低 limit
```

---

## ⚠️ Configuration Corrupted - 需要修復配置

### 12. luckyhilo-prd

```yaml
Current Status:
  Memory Usage: 187Mi
  Memory Request: 800Mi
  Memory Limit: 1288490188800m ⚠️ 配置錯誤
  Utilization: 23%

Current Configuration (CORRUPTED):
  resources:
    requests:
      cpu: 150m
      memory: 800Mi
    limits:
      cpu: 280m
      memory: 1288490188800m  # ← 明顯錯誤

Recommended Configuration:
  resources:
    requests:
      cpu: 20m
      memory: 210Mi     # 符合實際使用 187Mi
    limits:
      cpu: 150m
      memory: 640Mi     # 修復配置錯誤
```

**問題**: Limit 值異常，可能是單位轉換錯誤 (應該是 1.2Gi 誤寫為 m 單位)

**實施優先級**: P1 - 需要修復配置檔

---

### 13. plinkocl-prd

```yaml
Current Status:
  Memory Usage: 164Mi
  Memory Request: 1932735283200m ⚠️ 配置錯誤
  Memory Limit: 3006477107200m ⚠️ 配置錯誤
  Utilization: N/A (無法計算)

Recommended Configuration:
  resources:
    requests:
      cpu: 20m
      memory: 190Mi     # 修復為正常值
    limits:
      cpu: 250m
      memory: 640Mi     # 修復為正常值
```

**問題**: Request 和 Limit 都異常，完全無法使用

**實施優先級**: P0 - 立即修復配置

---

### 14. minesne-prd

```yaml
Current Status:
  Memory Usage: 111Mi
  Memory Request: 900Mi
  Memory Limit: 1395864371200m ⚠️ 配置錯誤
  Utilization: 12%

Recommended Configuration:
  resources:
    requests:
      cpu: 25m
      memory: 130Mi     # 符合實際使用
    limits:
      cpu: 200m
      memory: 640Mi     # 修復配置錯誤
```

**實施優先級**: P1 - 需要修復配置

---

## 🔵 Over-Provisioned - 可優化降低成本

### 15. schedule-prd

```yaml
Current Status:
  Memory Usage: 15Mi
  Memory Request: 300Mi
  Utilization: 5% (嚴重過度配置)

Recommended Configuration:
  resources:
    requests:
      cpu: 10m
      memory: 32Mi      # 大幅降低 (實際只用 15Mi)
    limits:
      cpu: 100m
      memory: 128Mi     # 提供充足 buffer
```

**節省**: Request 從 300Mi → 32Mi，節省 268Mi (89%)

**注意**: 此服務有 OOMKilled 歷史，需確認是否有記憶體洩漏問題修復後才能降低配置

**相關文件**: `SCHEDULE_SYNC_SERVICE_ANALYSIS.md`

---

### 16. loyaltyapi-prd (大服務過度配置)

```yaml
Current Status:
  Memory Usage: 242Mi
  Memory Request: 4Gi
  Utilization: 6% (極度過度配置)

Recommended Configuration:
  resources:
    requests:
      cpu: 50m
      memory: 280Mi     # 大幅降低
    limits:
      cpu: 1500m
      memory: 1Gi       # 提供充足 buffer
```

**節省**: Request 從 4Gi → 280Mi，節省 3.7Gi (93%)

**影響**: 這是一個大型 API 服務，建議分階段調整

---

### 17. bg-gate-prd

```yaml
Current Status:
  Memory Usage: 816Mi
  Memory Request: 4Gi
  Utilization: 20%

Recommended Configuration:
  resources:
    requests:
      cpu: 50m
      memory: 920Mi     # 降低但保留 buffer
    limits:
      cpu: 800m
      memory: 3Gi       # 降低 limit
```

**節省**: Request 從 4Gi → 920Mi，節省 3.1Gi (77%)

---

### 18. arcade-gate-prd

```yaml
Current Status:
  Memory Usage: 816Mi
  Memory Request: 2Gi
  Utilization: 40%

Recommended Configuration:
  resources:
    requests:
      cpu: 120m
      memory: 920Mi     # 降低 request
    limits:
      cpu: 1800m
      memory: 2560Mi    # 微調 limit
```

**節省**: Request 從 2Gi → 920Mi，節省 1.1Gi (55%)

---

### 19. hash-gate-prd

```yaml
Current Status:
  Memory Usage: 1441Mi
  Memory Request: 2Gi
  Utilization: 70%

Recommended Configuration:
  resources:
    requests:
      cpu: 250m
      memory: 1536Mi    # 微調 request (略高於實際使用)
    limits:
      cpu: 1800m
      memory: 3Gi       # 降低 limit
```

**節省**: Request 從 2Gi → 1536Mi，節省 512Mi (25%)

---

## 🟢 Normal - 配置合理的服務 (51 個)

以下服務配置合理，使用率在 20-80% 之間，暫不需要調整：

### Hash Games (21 個)
- crash-prd: 39Mi / 120Mi = 33%
- crashcl-prd: 44Mi / 120Mi = 37%
- crashgr-prd: 40Mi / 400Mi = 10%
- crashne-prd: 40Mi / 120Mi = 33%
- diamonds-prd: 43Mi / 200Mi = 22%
- dice-prd: 67Mi / 200Mi = 34%
- dragontower-prd: 97Mi / 200Mi = 49%
- hilo-prd: 88Mi / 200Mi = 44%
- hilocl-prd: 60Mi / 200Mi = 30%
- hilogr-prd: 49Mi / 200Mi = 25%
- hilone-prd: 65Mi / 200Mi = 33%
- keno-prd: 117Mi / 200Mi = 59%
- limbo-prd: 174Mi / 200Mi = 87% ⚠️ (接近上限，建議調為 190Mi)
- limbogr-prd: 44Mi / 200Mi = 22%
- luckydropcoc-prd: 113Mi / 200Mi = 57%
- luckydropgx-prd: 114Mi / 200Mi = 57%
- luckydropoly-prd: 106Mi / 200Mi = 53%
- multihilo-prd: 46Mi / 200Mi = 23%
- plinko-prd: 59Mi / 200Mi = 30%
- videopoker-prd: 61Mi / 200Mi = 31%
- wheel-prd: 56Mi / 200Mi = 28%

### Mines Variants (9 個)
- mines-prd: 67Mi / 200Mi = 34%
- minesca-prd: 139Mi / 1Gi = 14%
- minescl-prd: 78Mi / 200Mi = 39%
- minesgr-prd: 98Mi / 200Mi = 49%
- minesma-prd: 77Mi / 200Mi = 39%
- minespm-prd: 80Mi / 200Mi = 40%
- minesraider-prd: 55Mi / 200Mi = 28%
- minessc-prd: 114Mi / 200Mi = 57%
- plinkogr-prd: 101Mi / 200Mi = 51%
- plinkone-prd: 93Mi / 200Mi = 47%

### Bingo Games (9 個)
- arcadebingo-prd: 136Mi / 400Mi = 34%
- bingbingbingo-prd: 121Mi / 400Mi = 30%
- bingobells-prd: 107Mi / 400Mi = 27%
- bonusbingo-prd: 409Mi / 1536Mi = 27%
- caribbeanbingo-prd: 128Mi / 150Mi = 85% ⚠️ (接近上限，建議調為 140Mi)
- cavebingo-prd: 122Mi / 140Mi = 87% ⚠️ (接近上限，建議調為 135Mi)
- magicbingo-prd: 140Mi / 500Mi = 28%
- maplebingo-prd: 129Mi / 400Mi = 32%
- odinbingo-prd: 133Mi / 200Mi = 67%

### Aviator Games (3 個)
- aviator-prd: 73Mi / 600Mi = 12%
- aviator2-prd: 110Mi / 200Mi = 55%
- aviator2xin-prd: 37Mi / 200Mi = 19%

### Arcade Games (2 個)
- multiboomers-prd: 49Mi / 300Mi = 16%
- steampunk-prd: 132Mi / 200Mi = 66%
- steampunk2-prd: 130Mi / 180Mi = 72%

### API Services (4 個)
- adapterapi-prd: 100Mi / 40Mi = 250% ⚠️ (需要調整)
- domain-serviceapi-prd: 101Mi / 20Mi = 505% ⚠️⚠️ (嚴重不足)
- eventapi-prd: 101Mi / 20Mi = 505% ⚠️⚠️ (嚴重不足)
- exmgmtapi-prd: 102Mi / 20Mi = 510% ⚠️⚠️ (嚴重不足)
- partnerapi-prd: 29Mi / 40Mi = 73%

### Other Services (3 個)
- center-prd: 167Mi / 500Mi = 33%
- redis-prd: 31Mi / 60Mi = 52%
- syncservice-prd: 50Mi / 200Mi = 25%

**注意**: 標記 ⚠️ 的服務建議微調，標記 ⚠️⚠️ 的需要優先處理

---

## 📋 API 服務專項分析

API 服務需要特別關注，因為它們通常是無狀態且流量波動大：

| Service | Usage | Request | Limit | Utilization | Status |
|---------|-------|---------|-------|-------------|--------|
| exgameapi | 233Mi | 100Mi | 400Mi | 233% | 🔴 Critical |
| domain-serviceapi | 101Mi | 20Mi | 50Mi | 505% | 🔴 Critical |
| eventapi | 101Mi | 20Mi | 50Mi | 505% | 🔴 Critical |
| exmgmtapi | 102Mi | 20Mi | 50Mi | 510% | 🔴 Critical |
| adapterapi | 100Mi | 40Mi | 100Mi | 250% | 🔴 Critical |
| mgmtapi | 110Mi | 100Mi | 200Mi | 110% | 🟡 Warning |
| partnerapi | 29Mi | 40Mi | 100Mi | 73% | 🟢 Normal |
| loyaltyapi | 242Mi | 4Gi | 5Gi | 6% | 🔵 Over-provisioned |

**發現**: 5 個 API 服務的 request 嚴重不足 (>100% utilization)

---

## 🎯 實施建議與優先級

### Phase 1: 立即修復 (本週內) - P0

**目標**: 修復 Critical 和 Corrupted 配置

1. **forestteaparty-prd** (最高優先級)
   - 調整 memory request: 300Mi → 560Mi
   - 調整 memory limit: 600Mi → 1Gi
   - 預期影響: 消除 OOMKilled 風險

2. **plinkocl-prd** (配置損壞)
   - 修復 request: 1932735283200m → 190Mi
   - 修復 limit: 3006477107200m → 640Mi
   - 預期影響: 恢復正常資源管理

3. **luckydropcoc2-prd**
   - 調整 memory request: 200Mi → 320Mi
   - 預期影響: 修正 HPA 計算

4. **wilddiggr-prd**
   - 調整 memory request: 500Mi → 640Mi
   - 調整 memory limit: 1Gi → 1280Mi
   - **同時**: 修復程式碼 nil pointer bugs
   - 預期影響: 穩定服務運行

5. **API Services (5 個)**
   - domain-serviceapi: 20Mi → 128Mi
   - eventapi: 20Mi → 128Mi
   - exmgmtapi: 20Mi → 128Mi
   - adapterapi: 40Mi → 128Mi
   - exgameapi: 100Mi → 256Mi

**預期成果**:
- 消除 8 個 Critical 問題
- 修復 3 個配置損壞的服務
- 總計修復 11 個高風險服務

---

### Phase 2: 優化配置 (下週) - P1

**目標**: 調整 Warning 級別服務

1. **limbone-prd**: 監控後決定是否調整
2. **lostruins-prd**: 140Mi → 150Mi
3. **mgmtapi-prd**: 100Mi → 128Mi
4. **luckyhilo-prd**: 修復 limit 配置錯誤
5. **minesne-prd**: 修復 limit 配置錯誤

**預期成果**:
- 修復 5 個 Warning 級別服務
- 消除所有配置錯誤

---

### Phase 3: 成本優化 (兩週內) - P2

**目標**: 降低 Over-provisioned 服務的資源配置

1. **loyaltyapi-prd**: 4Gi → 280Mi (節省 3.7Gi)
2. **bg-gate-prd**: 4Gi → 920Mi (節省 3.1Gi)
3. **arcade-gate-prd**: 2Gi → 920Mi (節省 1.1Gi)
4. **hash-gate-prd**: 2Gi → 1536Mi (節省 512Mi)
5. **schedule-prd**: 300Mi → 32Mi (節省 268Mi)
6. **egghuntbingo-prd**: 500Mi → 170Mi (節省 330Mi)
7. **goldenclover-prd**: 500Mi → 260Mi (節省 240Mi)

**預期成果**:
- 總節省 memory request: **9.26 Gi**
- 降低 node 資源壓力
- 減少 over-commit 風險

---

### Phase 4: 微調優化 (持續進行)

**目標**: 調整接近上限的服務 (80-90%)

1. **caribbeanbingo-prd**: 150Mi → 140Mi
2. **cavebingo-prd**: 140Mi → 135Mi
3. **limbo-prd**: 200Mi → 190Mi (87% utilization)

---

## 📊 預期影響總結

### Memory Request 調整統計

| Phase | 增加 | 減少 | 淨變化 | 服務數量 |
|-------|------|------|--------|---------|
| Phase 1 (P0) | +1.6 Gi | 0 | +1.6 Gi | 11 |
| Phase 2 (P1) | +0.15 Gi | -0.27 Gi | -0.12 Gi | 5 |
| Phase 3 (P2) | 0 | -9.26 Gi | -9.26 Gi | 7 |
| **總計** | **+1.75 Gi** | **-9.53 Gi** | **-7.78 Gi** | **23** |

### 風險消除

- **消除 OOMKilled 風險**: 3 個服務
- **修正 HPA 計算錯誤**: 11 個服務
- **修復配置損壞**: 3 個服務
- **降低 node over-commit**: 減少 7.78 Gi request

### 成本節省

- **Memory Request 節省**: 7.78 Gi
- **預估成本節省**: ~15-20% node 資源利用率改善
- **穩定性提升**: 消除 OOMKilled 風險，減少服務中斷

---

## 🔧 實施指南

### 1. 更新配置檔案

所有服務的配置應該在 StatefulSet/Deployment YAML 中更新：

```bash
# 編輯配置
kubectl edit statefulset <service-name> -n <namespace>

# 或使用 kubectl patch
kubectl patch statefulset <service-name> -n <namespace> --type='json' \
  -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/memory", "value": "560Mi"}]'
```

### 2. 逐步 Rollout

**重要**: 不要同時更新所有服務，建議分批進行：

```bash
# Batch 1: Critical services (forestteaparty, plinkocl, API services)
# 等待 24 小時觀察

# Batch 2: luckydropcoc2, wilddiggr
# 等待 24 小時觀察

# Batch 3: Warning level services
# 等待 24 小時觀察

# Batch 4: Over-provisioned services (分批降低配置)
```

### 3. 監控指標

更新後需要監控以下指標：

```bash
# 監控 memory 使用率
kubectl top pods -n <namespace> --watch

# 檢查 OOMKilled events
kubectl get events -n <namespace> | grep OOMKilled

# 檢查 pod restarts
kubectl get pods -n <namespace> -o wide

# 監控 HPA 狀態
kubectl get hpa -n <namespace> --watch
```

### 4. Rollback 計劃

如果更新後出現問題：

```bash
# 快速 rollback
kubectl rollout undo statefulset/<service-name> -n <namespace>

# 檢查 rollout history
kubectl rollout history statefulset/<service-name> -n <namespace>
```

---

## 🔍 持續監控建議

### 每日檢查

```bash
# 檢查所有 -prd 服務的 memory 使用率
kubectl top pods --all-namespaces | grep '\-prd' | \
  awk '{usage=$4; gsub("Mi","",$4); if($4+0 > 0) print $1"\t"$2"\t"usage}'

# 檢查 OOMKilled events (最近 1 小時)
kubectl get events --all-namespaces --field-selector reason=OOMKilling \
  --sort-by='.lastTimestamp' | grep '\-prd'
```

### 每週檢查

1. 生成 memory usage 趨勢報告
2. 識別新的資源瓶頸
3. 檢視 HPA scaling events
4. 檢查 node 資源使用率

### 每月檢查

1. 全面資源配置審查
2. 成本優化分析
3. 容量規劃
4. SLA/SLO 達成率分析

---

## 📌 重要注意事項

### 1. StatefulSet 更新特性

- StatefulSet 更新會觸發 pod 重啟
- 順序更新: pod-0 → pod-1 → ...
- 每個 pod 更新前需確保前一個 pod ready
- 建議在低峰時段進行更新

### 2. API Services 特殊考量

- API 服務流量波動大，需要更多 buffer
- 建議 limit 設置為 request 的 2-3 倍
- 使用 HPA 配合 CPU/Memory metrics
- 考慮使用 PodDisruptionBudget (PDB)

### 3. Game Services 特殊考量

- WebSocket 長連接會佔用持續 memory
- 需考慮玩家數量突增場景
- 建議 limit 設置為 request 的 1.5-2 倍
- 監控 concurrent connections 指標

### 4. 配置更新驗證

更新前務必驗證：
```bash
# 驗證 YAML 語法
kubectl apply --dry-run=client -f <manifest.yaml>

# 驗證 YAML 語法和 API server 規則
kubectl apply --dry-run=server -f <manifest.yaml>
```

---

## 🎓 學習總結

### 關鍵發現

1. **HPA 基於 Request 計算**:
   - HPA memory utilization = (actual usage / memory request) × 100%
   - Request 設置不當會導致 HPA 錯誤判斷

2. **Over-Commit 風險**:
   - Node memory limits 總和遠超 node capacity (247%)
   - 當多個 pod 同時達到 limit 時會觸發 node OOM
   - 需要合理設置 request 和 limit

3. **API vs Game Services**:
   - API 服務: 無狀態，流量波動大，需要更高 limit/request ratio
   - Game 服務: 有狀態，連接數可預測，可精確設置資源

4. **配置損壞問題**:
   - 3 個服務存在明顯的配置錯誤 (單位轉換問題)
   - 需要建立配置驗證流程

### 改進建議

1. **建立配置標準**:
   - API 服務: request × 2-3 = limit
   - Game 服務: request × 1.5-2 = limit
   - 使用率目標: 50-80%

2. **自動化監控**:
   - 建立 Grafana dashboard 監控所有服務
   - 設置 alert rules (>80% utilization)
   - 每週生成資源使用報告

3. **配置管理**:
   - 使用 GitOps 管理配置
   - 配置變更需要 review + approval
   - 建立配置驗證 CI/CD pipeline

4. **容量規劃**:
   - 每月評估 node capacity
   - 預測未來 3-6 個月資源需求
   - 提前規劃 node scaling

---

## 📁 相關文件

- `FORESTTEAPARTY_RESOURCE_ANALYSIS.md` - forestteaparty 詳細分析
- `FORESTTEAPARTY_DEEP_DIVE_ANALYSIS.md` - forestteaparty 深度技術分析
- `SCHEDULE_SYNC_SERVICE_ANALYSIS.md` - schedule & sync service 分析
- `SCRATCH_CARD_GAMES_STACKTRACE_ANALYSIS.md` - wilddiggr/goldenclover bugs 分析
- `EKS_RESOURCE_ANALYSIS_REPORT.md` - 集群級資源短缺分析

---

**報告生成者**: Claude Code
**最後更新**: 2025-11-07
**狀態**: ✅ 完成

