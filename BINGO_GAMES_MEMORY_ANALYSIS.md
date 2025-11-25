# Bingo 遊戲服務記憶體使用分析報告

**分析日期**: 2025-11-07（更新於 2025-11-08）
**分析範圍**: 13 個 Bingo 遊戲服務
**資料收集時間**: Pod 運行 4 天 7 小時
**分析方法**: 比照 ForestTeaParty 深度分析標準
**資料來源**: kustomize-prd/gemini-game/base/prd/bingo-svc/

---

## 執行摘要

### 關鍵發現

1. **🚨 三個服務記憶體使用率超過 HPA 閾值 80%**
   - **lostruins-prd**: 92% (129Mi / 140Mi request) 🔴 **新發現**
   - **cavebingo-prd**: 87% (122Mi / 140Mi request)
   - **caribbeanbingo-prd**: 85% (128Mi / 150Mi request)

2. **⚠️ 資源配置嚴重不一致**
   - 配置範圍從 140Mi 到 1536Mi (相差 11 倍)
   - 實際使用量差異不大 (108Mi - 391Mi)

3. **✅ 所有服務穩定運行**
   - 零重啟次數 (0 restarts)
   - 運行時長: 4 天 7 小時
   - 無記憶體 OOM 事件

4. **📊 資料庫連線池配置統一**
   - 所有服務: 40 connections (read + write DB)

---

## 詳細服務分析

### 1. arcadebingo-prd

**記憶體使用**: 137 Mi
**Request**: 400 Mi
**Limit**: 700 Mi
**使用率**: 34% of request, 20% of limit
**運行時長**: 112 小時 (4d 7h)
**重啟次數**: 0
**HPA 狀態**: memory: 34%/80% (MINPODS=1, MAXPODS=1)
**資料庫連線**: 40 connections (read) + 40 connections (write)
**Game Type**: ArcadeBingo (Server ID: 009)

**評估**: ✅ **配置合理**
- 使用率穩定在 34%，有充足 buffer
- Request 400Mi 是合理的起始配置
- Limit 700Mi 提供足夠的峰值空間
- 無需調整

---

### 2. bingbingbingo-prd

**記憶體使用**: 121 Mi
**Request**: 400 Mi
**Limit**: 700 Mi
**使用率**: 30% of request, 17% of limit
**運行時長**: 112 小時 (4d 7h)
**重啟次數**: 0
**HPA 狀態**: memory: 30%/80% (MINPODS=1, MAXPODS=1)
**資料庫連線**: 40 connections (read) + 40 connections (write)
**Game Type**: BingBingBingo (Server ID: 未顯示)

**評估**: ⚠️ **可優化 - Request 過高**
- 實際使用僅 121Mi，但 request 400Mi
- **建議 request 降至 250Mi**，limit 保持 700Mi
- 可釋放 150Mi 的 request 資源給其他 Pod 使用

---

### 3. bingobells-prd

**記憶體使用**: 108 Mi
**Request**: 400 Mi
**Limit**: 700 Mi
**使用率**: 27% of request, 15% of limit
**運行時長**: 112 小時 (4d 7h)
**重啟次數**: 0
**HPA 狀態**: memory: 27%/80% (MINPODS=1, MAXPODS=1)
**資料庫連線**: 40 connections (read) + 40 connections (write)
**Game Type**: BingoBells (Server ID: 未顯示)

**評估**: ⚠️ **可優化 - Request 過高**
- 實際使用最低 (108Mi)，但 request 400Mi
- **建議 request 降至 220Mi**，limit 保持 700Mi
- 可釋放 180Mi 的 request 資源

---

### 4. bonusbingo-prd 🔥

**記憶體使用**: 391 Mi
**Request**: 1536 Mi
**Limit**: 3 Gi (3072 Mi)
**使用率**: 25% of request, 13% of limit
**運行時長**: 112 小時 (4d 7h)
**重啟次數**: 0
**HPA 狀態**: memory: 25%/80% (MINPODS=1, MAXPODS=1)
**資料庫連線**: 40 connections (read) + 40 connections (write)
**Game Type**: BonusBingo (Server ID: 007)

**評估**: 🚨 **嚴重過度配置**
- Request 1536Mi 是實際使用 (391Mi) 的 **3.9 倍**
- Limit 3Gi 是實際使用的 **7.9 倍**
- 使用率僅 25%，遠低於其他服務
- **強烈建議調整**:
  - Request: 1536Mi → 600Mi (節省 936Mi)
  - Limit: 3Gi → 1Gi (節省 2Gi)
- 這是 10 個 Bingo 服務中配置最不合理的

**可能原因**:
- 初始配置時預期高負載，但實際未發生
- 複製自其他高負載服務的配置
- 缺乏長期監控數據支持配置決策

---

### 5. caribbeanbingo-prd 🚨

**記憶體使用**: 128 Mi
**Request**: 150 Mi
**Limit**: 250 Mi
**使用率**: 85% of request, 51% of limit
**運行時長**: 112 小時 (4d 7h)
**重啟次數**: 0
**HPA 狀態**: memory: **85%/80%** ⚠️ **超過 HPA 閾值** (MINPODS=1, MAXPODS=1)
**資料庫連線**: 40 connections (read) + 40 connections (write)
**Game Type**: CaribbeanBingo (Server ID: 未顯示)

**評估**: 🚨 **Request 不足 - 需要立即調整**
- 使用率 85% **超過 HPA 閾值 80%**
- 雖然 HPA MAXPODS=1 無法擴展，但這表示配置過低
- Request 僅 150Mi，是所有服務中第二低
- **建議立即調整**:
  - Request: 150Mi → 220Mi (+70Mi, 提供 72% 使用率)
  - Limit: 250Mi → 400Mi (+150Mi, 提供峰值緩衝)

**風險**:
- 記憶體使用接近 request，可能影響 Pod 調度優先級
- 峰值流量時可能觸及 limit
- 缺乏緩衝空間應對突發負載

---

### 6. cavebingo-prd 🚨

**記憶體使用**: 122 Mi
**Request**: 140 Mi
**Limit**: 220 Mi
**使用率**: 87% of request, 55% of limit
**運行時長**: 112 小時 (4d 7h)
**重啟次數**: 0
**HPA 狀態**: memory: **87%/80%** ⚠️ **超過 HPA 閾值** (MINPODS=1, MAXPODS=1)
**資料庫連線**: 40 connections (read) + 40 connections (write)
**Game Type**: CaveBingo (Server ID: 未顯示)

**評估**: 🚨 **Request 最不足 - 最高優先級調整**
- 使用率 87% **超過 HPA 閾值 80%**，是所有服務中最高
- Request 140Mi 是所有服務中最低
- **建議立即調整**:
  - Request: 140Mi → 200Mi (+60Mi, 提供 61% 使用率)
  - Limit: 220Mi → 350Mi (+130Mi, 提供更多峰值空間)

**風險**:
- **最高風險服務**，記憶體使用率持續接近 request
- 可能在 Node 資源緊張時被驅逐 (eviction)
- 缺乏足夠緩衝應對任何負載增長

---

### 7. egghuntbingo-prd

**記憶體使用**: 145 Mi
**Request**: 500 Mi
**Limit**: 800 Mi
**使用率**: 29% of request, 18% of limit
**運行時長**: 112 小時 (4d 7h)
**重啟次數**: 0
**HPA 狀態**: memory: 29%/80% (MINPODS=1, MAXPODS=1)
**資料庫連線**: 40 connections (read) + 40 connections (write)
**Game Type**: EggHuntBingo (Server ID: 未顯示)

**評估**: ⚠️ **可優化 - Request 過高**
- 實際使用 145Mi，但 request 500Mi
- **建議 request 降至 300Mi**，limit 保持 800Mi
- 可釋放 200Mi 的 request 資源

---

### 8. magicbingo-prd

**記憶體使用**: 144 Mi
**Request**: 500 Mi
**Limit**: 800 Mi
**使用率**: 28% of request, 18% of limit
**運行時長**: 112 小時 (4d 7h)
**重啟次數**: 0
**HPA 狀態**: memory: 28%/80% (MINPODS=1, MAXPODS=1)
**資料庫連線**: 40 connections (read) + 40 connections (write)
**Game Type**: MagicBingo (Server ID: 未顯示)

**評估**: ⚠️ **可優化 - Request 過高**
- 實際使用 144Mi，但 request 500Mi
- **建議 request 降至 300Mi**，limit 保持 800Mi
- 可釋放 200Mi 的 request 資源

---

### 9. maplebingo-prd

**記憶體使用**: 132 Mi
**Request**: 400 Mi
**Limit**: 600 Mi
**使用率**: 33% of request, 22% of limit
**運行時長**: 112 小時 (4d 7h)
**重啟次數**: 0
**HPA 狀態**: memory: 33%/80% (MINPODS=1, MAXPODS=1)
**資料庫連線**: 40 connections (read) + 40 connections (write)
**Game Type**: MapleBingo (Server ID: 未顯示)

**評估**: ⚠️ **可優化 - Request 過高**
- 實際使用 132Mi，但 request 400Mi
- **建議 request 降至 270Mi**，limit 調整為 500Mi
- 可釋放 130Mi 的 request 資源

---

### 10. odinbingo-prd

**記憶體使用**: 133 Mi
**Request**: 200 Mi
**Limit**: 320 Mi
**使用率**: 66% of request, 42% of limit
**運行時長**: 112 小時 (4d 7h)
**重啟次數**: 0
**HPA 狀態**: memory: 66%/80% (MINPODS=1, MAXPODS=1)
**資料庫連線**: 40 connections (read) + 40 connections (write)
**Game Type**: OdinBingo (Server ID: 未顯示)

**評估**: ✅ **配置較合理，但可微調**
- 使用率 66%，接近理想範圍 (50-70%)
- 建議保持 request 200Mi，考慮將 limit 提升至 400Mi
- 提供更多峰值緩衝空間

---

### 11. lostruins-prd 🔴 **新發現 - P0 問題**

**記憶體使用**: 129 Mi
**Request**: 140 Mi
**Limit**: 230 Mi
**使用率**: 92% of request, 56% of limit
**運行時長**: 4 天+
**重啟次數**: 0
**HPA 狀態**: memory: 92%/80% 🔴 **超過閾值**
**資料庫連線**: 40 connections (read) + 40 connections (write)
**Game Type**: LostRuins

**評估**: 🚨 **緊急 - 超過 HPA 閾值**
- **使用率 92%**，超過 80% HPA 觸發值
- 距離 Request 上限僅剩 **11Mi (8%)**
- 與 cavebingo (87%) 和 caribbeanbingo (85%) 屬於同等級高風險
- **任何流量增加 > 8% 即可能觸發 OOM**

**建議修復**:
```yaml
resources:
  requests:
    memory: "200Mi"  # 從 140Mi 提升 (+43%)
  limits:
    memory: "350Mi"  # 從 230Mi 提升 (+52%)
```
**理由**: 使用率 92% 遠超 HPA 閾值，存在極高驅逐風險

---

### 12. steampunk-prd

**記憶體使用**: 131 Mi
**Request**: 200 Mi
**Limit**: 300 Mi
**使用率**: 66% of request, 44% of limit
**運行時長**: 4 天+
**重啟次數**: 0
**HPA 狀態**: memory: 66%/80% (MINPODS=1, MAXPODS=1)
**資料庫連線**: 40 connections (read) + 40 connections (write)
**Game Type**: Steampunk

**評估**: ✅ **配置合理**
- 使用率 66%，在理想範圍內 (50-70%)
- Request 200Mi 配置適當
- Limit 300Mi 提供足夠緩衝
- 無需調整

---

### 13. steampunk2-prd

**記憶體使用**: 131 Mi
**Request**: 180 Mi
**Limit**: 300 Mi
**使用率**: 73% of request, 44% of limit
**運行時長**: 4 天+
**重啟次數**: 0
**HPA 狀態**: memory: 73%/80% (MINPODS=1, MAXPODS=1)
**資料庫連線**: 40 connections (read) + 40 connections (write)
**Game Type**: Steampunk2

**評估**: ✅ **配置合理，接近上限**
- 使用率 73%，接近 HPA 警戒值
- 與 steampunk-prd 記憶體使用完全相同 (131Mi)
- Request 配置略低於 steampunk (180Mi vs 200Mi)
- 建議保持現狀，持續監控

**觀察**: steampunk 和 steampunk2 記憶體使用完全相同，可能是相同版本或姐妹服務。

---

## 總結比較表格

### 記憶體使用總覽

| 服務名稱 | 記憶體使用 | Request | Limit | Request 使用率 | Limit 使用率 | HPA 狀態 | 運行時長 | 重啟次數 | 評估 |
|---------|-----------|---------|-------|--------------|-------------|----------|---------|---------|------|
| **lostruins** 🔴 | 129 Mi | 140 Mi | 230 Mi | **92%** 🔴🔴 | 56% | **92%/80%** ⚠️ | 112h | 0 | 🔴 **最緊急** |
| **cavebingo** | 122 Mi | 140 Mi | 220 Mi | **87%** 🚨 | 55% | **87%/80%** ⚠️ | 112h | 0 | 🚨 最高優先級 |
| **caribbeanbingo** | 128 Mi | 150 Mi | 250 Mi | **85%** 🚨 | 51% | **85%/80%** ⚠️ | 112h | 0 | 🚨 立即調整 |
| **steampunk2** | 131 Mi | 180 Mi | 300 Mi | 73% | 44% | 73%/80% ✅ | 112h | 0 | ✅ 合理 |
| **steampunk** | 131 Mi | 200 Mi | 300 Mi | 66% | 44% | 66%/80% ✅ | 112h | 0 | ✅ 合理 |
| **odinbingo** | 133 Mi | 200 Mi | 320 Mi | 66% | 42% | 66%/80% ✅ | 112h | 0 | ✅ 較合理 |
| **arcadebingo** | 137 Mi | 400 Mi | 700 Mi | 34% | 20% | 34%/80% ✅ | 112h | 0 | ✅ 合理 |
| **maplebingo** | 132 Mi | 400 Mi | 600 Mi | 33% | 22% | 33%/80% ✅ | 112h | 0 | ⚠️ 可優化 |
| **bingbingbingo** | 121 Mi | 400 Mi | 700 Mi | 30% | 17% | 30%/80% ✅ | 112h | 0 | ⚠️ 可優化 |
| **egghuntbingo** | 145 Mi | 500 Mi | 800 Mi | 29% | 18% | 29%/80% ✅ | 112h | 0 | ⚠️ 可優化 |
| **magicbingo** | 144 Mi | 500 Mi | 800 Mi | 28% | 18% | 28%/80% ✅ | 112h | 0 | ⚠️ 可優化 |
| **bingobells** | 108 Mi | 400 Mi | 700 Mi | 27% | 15% | 27%/80% ✅ | 112h | 0 | ⚠️ 可優化 |
| **bonusbingo** | 391 Mi | 1536 Mi | 3072 Mi | **25%** 🔥 | 13% | 25%/80% ✅ | 112h | 0 | 🚨 嚴重過配 |

### 按使用率排序（Request）

1. **lostruins**: 92% 🔴🔴 - **最緊急 - 新發現**
2. **cavebingo**: 87% 🚨 - 立即需要增加 request
2. **caribbeanbingo**: 85% 🚨 - 立即需要增加 request
3. **odinbingo**: 66% ✅ - 合理範圍
4. **arcadebingo**: 34% ✅ - 合理範圍
5. **maplebingo**: 33% ⚠️ - 可以降低 request
6. **bingbingbingo**: 30% ⚠️ - 可以降低 request
7. **egghuntbingo**: 29% ⚠️ - 可以降低 request
8. **magicbingo**: 28% ⚠️ - 可以降低 request
9. **bingobells**: 27% ⚠️ - 可以降低 request
10. **bonusbingo**: 25% 🚨 - 嚴重過度配置

### 資源配置不一致分析

**Request 配置範圍**: 140 Mi - 1536 Mi (相差 **11 倍**)
**Limit 配置範圍**: 220 Mi - 3072 Mi (相差 **14 倍**)
**實際使用範圍**: 108 Mi - 391 Mi (相差 **3.6 倍**)

**問題識別**:
1. **bonusbingo** 的配置是異常值，顯著高於其他服務
2. **caribbeanbingo** 和 **cavebingo** 的配置顯著低於實際需求
3. 缺乏統一的資源配置標準

---

## 優化建議

### 立即執行（高優先級）

#### 1. cavebingo-prd 🚨 **最高優先級**
```yaml
resources:
  requests:
    memory: "200Mi"  # 從 140Mi 增加 (實際使用 122Mi)
  limits:
    memory: "350Mi"  # 從 220Mi 增加
```
**理由**: 使用率 87% 超過 HPA 閾值，存在驅逐風險

#### 2. caribbeanbingo-prd 🚨 **高優先級**
```yaml
resources:
  requests:
    memory: "220Mi"  # 從 150Mi 增加 (實際使用 128Mi)
  limits:
    memory: "400Mi"  # 從 250Mi 增加
```
**理由**: 使用率 85% 超過 HPA 閾值，缺乏峰值緩衝

#### 3. bonusbingo-prd 🔥 **資源回收優先級**
```yaml
resources:
  requests:
    memory: "600Mi"  # 從 1536Mi 減少（節省 936Mi）
  limits:
    memory: "1Gi"    # 從 3Gi 減少（節省 2Gi）
```
**理由**: 嚴重過度配置，可釋放大量資源

**預期效果**:
- 立即釋放 936Mi request 資源
- 可用於調度其他 Pod 或提升集群整體資源利用率

---

### 短期優化（中優先級）

#### 4-9. 降低過度配置的服務

**bingobells-prd**:
```yaml
resources:
  requests:
    memory: "220Mi"  # 從 400Mi 減少（節省 180Mi）
  limits:
    memory: "700Mi"  # 保持不變
```

**bingbingbingo-prd**:
```yaml
resources:
  requests:
    memory: "250Mi"  # 從 400Mi 減少（節省 150Mi）
  limits:
    memory: "700Mi"  # 保持不變
```

**maplebingo-prd**:
```yaml
resources:
  requests:
    memory: "270Mi"  # 從 400Mi 減少（節省 130Mi）
  limits:
    memory: "500Mi"  # 從 600Mi 減少
```

**egghuntbingo-prd**:
```yaml
resources:
  requests:
    memory: "300Mi"  # 從 500Mi 減少（節省 200Mi）
  limits:
    memory: "800Mi"  # 保持不變
```

**magicbingo-prd**:
```yaml
resources:
  requests:
    memory: "300Mi"  # 從 500Mi 減少（節省 200Mi）
  limits:
    memory: "800Mi"  # 保持不變
```

---

### 總資源節省估算

**Request 總節省**: 936 + 180 + 150 + 130 + 200 + 200 = **1,796 Mi** (~1.75 Gi)
**Request 總增加**: 60 (cavebingo) + 70 (caribbeanbingo) = **130 Mi**
**淨 Request 節省**: **1,666 Mi** (~1.63 Gi)

**Limit 總節省**: 2048 (bonusbingo) + 100 (maplebingo) + 100 (caribbeanbingo-增加前) = **~2 Gi**

**節省資源可用於**:
- 調度額外的 3-4 個小型服務 Pod
- 為現有服務提供更多 burst 空間
- 提升 Node 資源利用率，減少 Node 數量需求

---

## 與 ForestTeaParty 的比較

### 相似點

1. **穩定性**: 所有服務都零重啟，運行穩定
2. **運行時長**: 都是 4 天 7 小時左右
3. **資料庫連線池**: 都使用 40 connections 配置
4. **HPA 配置**: 都設置 80% 記憶體閾值

### 差異點

| 指標 | ForestTeaParty | Bingo Games (平均) | Bingo Games (範圍) |
|------|----------------|-------------------|-------------------|
| **記憶體使用** | 177 Mi | 156 Mi | 108-391 Mi |
| **Request** | 600 Mi | 512 Mi | 140-1536 Mi |
| **Limit** | 1 Gi | 946 Mi | 220-3072 Mi |
| **Request 使用率** | 29.5% | 44% | 25-87% |
| **HPA 狀態** | 29%/80% | 44%/80% | 25-87%/80% |
| **配置一致性** | N/A | 差異極大 | 11倍差異 |
| **問題數量** | 可優化 1 個 | 🚨 緊急 2 個<br>⚠️ 可優化 6 個 | - |

### 關鍵洞察

1. **ForestTeaParty 配置相對保守**: 29.5% 使用率，有充足 buffer
2. **Bingo Games 配置更激進**: 兩個服務超過 HPA 閾值
3. **配置標準化程度**:
   - ForestTeaParty: 單一服務，配置統一
   - Bingo Games: 10 個服務，配置差異巨大（缺乏標準化）

---

## 風險評估

### 高風險 🚨

**cavebingo-prd** 和 **caribbeanbingo-prd**:
- 記憶體使用率超過 HPA 閾值
- 可能在 Node 資源緊張時被優先驅逐
- 缺乏峰值流量緩衝
- **建議在 24 小時內調整配置**

### 中風險 ⚠️

**bonusbingo-prd**:
- 雖然穩定運行，但浪費大量集群資源
- 可能阻礙其他 Pod 的調度
- **建議在 1 週內調整配置**

### 低風險 ✅

其他 7 個服務:
- 運行穩定，無立即風險
- 可在下次維護窗口進行優化

---

## 監控建議

### 1. 持續監控指標

為所有 Bingo 服務設置以下監控:

```promql
# 記憶體使用率（相對於 request）
container_memory_working_set_bytes{namespace=~".*bingo-prd"} /
on(pod) kube_pod_container_resource_requests{resource="memory",namespace=~".*bingo-prd"} * 100

# Alert 條件
> 75% for 15m  # Warning
> 85% for 5m   # Critical
```

### 2. 記憶體趨勢分析

定期（每週）檢查:
- 記憶體使用的 P50, P95, P99 百分位數
- 峰值使用時段（對應玩家活躍時段）
- 長期趨勢（是否持續增長）

### 3. 連線數 vs 記憶體相關性

建議添加 metrics:
```go
// 當前活躍連線數
active_player_connections{game_type="ArcadeBingo"}

// 記憶體使用與連線數的比率
memory_per_connection = memory_usage_bytes / active_player_connections
```

---

## 實施計劃

### Phase 1: 緊急修復（Day 1-2）

1. **調整 cavebingo-prd**
2. **調整 caribbeanbingo-prd**
3. 部署並監控 2 小時

### Phase 2: 資源回收（Day 3-5）

4. **調整 bonusbingo-prd**（釋放最多資源）
5. 驗證服務穩定性
6. 監控集群整體資源利用率變化

### Phase 3: 批量優化（Week 2）

7. 批量調整其他 6 個服務
8. 使用 rolling update 策略
9. 持續監控 7 天

### Phase 4: 標準化（Week 3-4）

10. 建立 Bingo 遊戲服務資源配置標準
11. 文檔化配置決策邏輯
12. 設置自動化監控和告警

---

## 附錄

### A. 完整 kubectl 命令記錄

```bash
# 檢查記憶體使用
kubectl top pod -n <namespace>

# 檢查資源配置
kubectl get pod -n <namespace> -o yaml | grep -A 10 resources:

# 檢查 HPA 狀態
kubectl get hpa -n <namespace>

# 檢查 Pod 狀態
kubectl get pods -n <namespace> -o wide

# 檢查日誌
kubectl logs -n <namespace> <pod-name> --tail=1000
```

### B. 資料庫連線池配置

所有 Bingo 服務使用統一配置:
```json
{
  "database": {
    "connections": 40  // read replica
  },
  "writedatabase": {
    "connections": 40  // primary
  }
}
```

總連線數: **80 connections per service**
10 個服務總計: **800 database connections**

### C. 服務列表與 Server ID 映射

| 服務名稱 | Game Type | Server ID | Port |
|---------|-----------|-----------|------|
| arcadebingo | ArcadeBingo | 009 | 29009 |
| bonusbingo | BonusBingo | 007 | 29007 |
| (其他服務 Server ID 未在日誌中顯示) | - | - | - |

---

**分析完成日期**: 2025-11-07
**下次建議複查**: 調整完成後 7 天
**報告版本**: v1.0
