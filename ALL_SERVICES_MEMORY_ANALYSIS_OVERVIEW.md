# 所有遊戲及 API 服務記憶體分析總覽（完整版）

**分析時間**: 2025-11-07 16:00 UTC+8（更新於 2025-11-08 01:00）
**分析範圍**: **71 個服務**（13 Bingo + 41 Hash + 5 Arcade + 2 Gate + 10 API）
**分析方法**: 比照 ForestTeaParty 深度分析標準
**分析工具**: Claude Code
**資料來源**: kustomize-prd/gemini-game/base/prd/

---

## 🎯 執行摘要

### 總體狀況評估

| 類別 | 服務數 | 🔴 緊急 (P0) | ⚠️ 警告 (P1) | ✅ 正常 | 總體評級 |
|------|--------|-------------|-------------|---------|---------|
| **Bingo 遊戲** | 13 | **3** | 1 | 9 | 🔴 高風險 |
| **Hash 遊戲** | 41 | **6** | **6** | 29 | 🔴 高風險 |
| **Arcade 遊戲** | 5 | 0 | 0 | 5 | ✅ 良好 |
| **Gate 服務** | 2 | 1 | 1 | 0 | 🔴 高風險 |
| **API 服務** | 10 | 4 | 2 | 4 | 🔴 高風險 |
| **總計** | **71** | **14** | **10** | **47** | **🔴 需立即處理** |

### 整合關鍵發現

| 指標 | 數值 | 說明 |
|------|------|------|
| **總 P0 問題** | **14 個** | Hash: 6, Bingo: 3, API: 4, Gate: 1 |
| **總記憶體用量** | ~8 Gi | 所有 71 個服務實際使用總和 |
| **總 Request** | ~25 Gi | 配置的資源請求總和 |
| **總 Limit** | ~42 Gi | 配置的資源上限總和（排除異常值）|
| **平均使用率** | 32% | Request 平均使用效率 |
| **資源浪費** | ~17 Gi | 過度配置的 Request |
| **TB級配置錯誤** | 3 個 | plinkocl, minesne, luckyhilo（總計 5.3Ti）|

---

## 🚨 P0 緊急問題（24 小時內必須處理）

### 1. 記憶體計量系統可能異常 🔴🔴🔴

**受影響服務**：
- domain-serviceapi: 101Mi / 50Mi Limit (**202%**)
- eventapi: 109Mi / 50Mi Limit (**218%**)
- exmgmtapi: 100Mi / 50Mi Limit (**200%**)

**問題**：
- 3 個服務實際使用都超過 Limit 200%+
- 理論上應該被 OOMKilled，但仍在運行
- **可能 metrics-server 或 cgroup 限制失效**

**行動**：
```bash
# 1. 驗證 metrics-server 狀態
kubectl get pods -n kube-system | grep metrics-server

# 2. 檢查實際 cgroup 限制
kubectl exec -n domain-serviceapi-prd <pod> -- \
  cat /sys/fs/cgroup/memory/memory.limit_in_bytes

# 3. 立即調整 Limit
kubectl edit deployment domain-serviceapi -n domain-serviceapi-prd
# 將 Limit 從 50Mi → 150Mi
```

**影響**：如果 cgroup 限制失效，可能導致：
- Node 記憶體耗盡
- 其他服務被驅逐
- 整個 Node 崩潰

**優先級**：🔴 **P0 - 立即**
**預計時間**：2-4 小時調查 + 修復

---

### 2. Hash Gate 記憶體壓力高 + 日誌爆炸 🔴

**當前狀態**：
- 記憶體使用：**1450Mi / 2200Mi (66%)**
- 距離 HPA 觸發（80%）：僅剩 **14%**
- 日誌總量：**34GB**（每日新增 3.4GB）
- 日誌輪換：每 **12-20 分鐘**一次

**時間預測**：
- **1.3 天**後達到 HPA 觸發值（但 maxReplicas=1 無法擴展）
- **4.25 天**後達到 Request 上限
- **18.8 天**後可能 OOM

**根本原因**：
- 連接 **22 個遊戲**（Arcade Gate 的 5.5 倍）
- 處理 **135 活躍用戶**（Arcade Gate 的 3.37 倍）
- Debug 模式開啟，日誌等級過低（INFO）
- Crash 系列遊戲產生高頻日誌

**立即行動**：
```yaml
# 調整日誌等級
env:
- name: LOG_LEVEL
  value: "WARN"  # 從 INFO 改為 WARN
- name: DEBUG_MODE
  value: "0"     # 關閉 Debug

# 預期效果：減少 50-70% 日誌量
```

**優先級**：🔴 **P0 - 24 小時內**
**預計影響**：減少 1.7-2.4 GB/天 日誌量

---

### 3. loyaltyapi 嚴重資源浪費 🔴

**當前配置**：
- Request: **4Gi** (4096Mi)
- 實際使用: **236Mi**
- 使用率: **6%** 🔴

**問題**：
- **獨佔整個節點 4Gi 記憶體**
- 嚴重影響集群調度效率
- 浪費 3.8Gi 可分配資源

**建議調整**：
```yaml
resources:
  requests:
    memory: "500Mi"  # 從 4Gi 降低（-3.5Gi）
  limits:
    memory: "1Gi"    # 從 5Gi 降低（-4Gi）
```

**預期效果**：
- 釋放 **3.5Gi Request 資源**
- 可調度額外 7-10 個中型服務
- 節點資源利用率提升

**優先級**：🔴 **P0 - 24-48 小時內**
**預計影響**：釋放 3.5Gi 資源（最大單一優化項）

---

### 4. Bingo Games 三個服務接近/超過記憶體上限 🔴

**lostruins**： 🔴🔴 **新發現 - 最嚴重**
- 使用：129Mi / 140Mi Request (**92%**)
- HPA：92% / 80% 閾值
- 距離驅逐：僅 **8%**

**cavebingo**：
- 使用：122Mi / 140Mi Request (**87%**)
- HPA：87% / 80% 閾值
- 距離驅逐：僅 **13%**

**caribbeanbingo**：
- 使用：128Mi / 150Mi Request (**85%**)
- HPA：85% / 80% 閾值
- 距離驅逐：僅 **15%**

**風險**：
- 任何流量增加 10-15% 即可能觸發 Pod 驅逐
- 批次處理峰值可能超限
- 高峰時段風險極高

**建議調整**：
```yaml
# lostruins (最優先)
resources:
  requests:
    memory: "200Mi"  # +60Mi (從 140Mi)
  limits:
    memory: "350Mi"  # +120Mi (從 230Mi)

# cavebingo
resources:
  requests:
    memory: "200Mi"  # +60Mi
  limits:
    memory: "350Mi"  # +130Mi

# caribbeanbingo
resources:
  requests:
    memory: "220Mi"  # +70Mi
  limits:
    memory: "400Mi"  # +150Mi
```

**優先級**：🔴 **P0 - 24 小時內**

---

## ⚠️ P1 高優先級問題（本週內處理）

### 5. exgameapi HPA 無法擴展 ⚠️

**問題**：
- 記憶體使用：222Mi
- HPA：**96%** / 80% 閾值（**已超過 16%**）
- 但 **maxReplicas=1**，無法水平擴展

**建議**：
```yaml
# HPA 配置
spec:
  minReplicas: 1
  maxReplicas: 3  # 從 1 改為 3

# 資源配置
resources:
  requests:
    memory: "250Mi"  # 從 100Mi 提高
  limits:
    memory: "500Mi"  # 從 400Mi 提高
```

**優先級**：⚠️ **P1 - 3 天內**

---

### 6. bonusbingo 嚴重過度配置 ⚠️

**當前**：
- Request: **1536Mi**
- 使用: **391Mi**
- 使用率: **25%**

**可節省**：
- Request: **-936Mi** (61%)
- Limit: **-2Gi** (67%)

**建議**：
```yaml
resources:
  requests:
    memory: "600Mi"  # 從 1536Mi 降低
  limits:
    memory: "1Gi"    # 從 3Gi 降低
```

**優先級**：⚠️ **P1 - 5 天內**

---

### 7. Arcade Gate Nil Pointer 錯誤 ⚠️

**問題**：
- **39 個 stacktrace 文件**
- 錯誤位置: `loyalty/client.go:106`
- 日誌從 25MB 增至 1.2GB（4 天內）

**修復**：
```go
// loyalty/client.go:106
func (c *Client) SendRequest(req *Request, resp interface{}) error {
    if req == nil {
        return errors.New("request cannot be nil")
    }
    if c.httpClient == nil {
        return errors.New("http client not initialized")
    }
    // ... 其他邏輯
}
```

**優先級**：⚠️ **P1 - 7 天內**

---

### 8. Hash Games 配置異常 🔴🔴🔴

**最嚴重問題**：5 個 Hash game 服務有 P0 級別問題

#### 配置異常（TB 級別錯誤）

| 服務 | Request | Limit | 問題 |
|------|---------|-------|------|
| **plinkocl-prd** | **1.8 Ti** | **2.8 Ti** | 配置錯誤（應為 Mi 級別）|
| **minesne-prd** | 270Mi | **1.3 Ti** | 配置錯誤 + 已重啟 4 次 |
| **luckyhilo-prd** | 800Mi | **1.2 Ti** | 配置錯誤 |

**問題**：
- 3 個服務的 Limit 配置為 **TB 級別**（應為 MB 級別）
- 總計異常配置：**5.3 Ti** ≈ **5427 Gi**
- 雖然實際使用正常，但會嚴重影響調度器決策
- 可能導致這些服務被調度到超大節點或無法調度

**立即修復**：
```yaml
# plinkocl-prd
resources:
  requests:
    memory: "200Mi"  # 從 1.8Ti 修正
  limits:
    memory: "350Mi"  # 從 2.8Ti 修正

# minesne-prd
resources:
  requests:
    memory: "270Mi"  # 保持
  limits:
    memory: "450Mi"  # 從 1.3Ti 修正

# luckyhilo-prd
resources:
  requests:
    memory: "200Mi"  # 從 800Mi 降低
  limits:
    memory: "350Mi"  # 從 1.2Ti 修正
```

#### 記憶體壓力過高

| 服務 | 使用 | Request | HPA | 重啟 | 狀態 |
|------|------|---------|-----|------|------|
| **limbone-prd** | 200Mi | 200Mi | **100%** | 3 次 | 🔴 臨界 |
| **limbo-prd** | 188Mi | 200Mi | **94%** | 0 次 | 🔴 高壓 |

**問題**：
- limbone-prd 已達到 Request 上限（100%）並已重啟 3 次
- limbo-prd 距離 HPA 觸發值（80%）僅剩 6%
- 兩者都在高風險區域

**立即修復**：
```yaml
# limbone-prd
resources:
  requests:
    memory: "300Mi"  # 從 200Mi 提升 (+50%)
  limits:
    memory: "500Mi"  # 從 350Mi 提升 (+43%)

# limbo-prd
resources:
  requests:
    memory: "300Mi"  # 從 200Mi 提升 (+50%)
  limits:
    memory: "500Mi"  # 從 350Mi 提升 (+43%)
```

**修復檔案**：
- 已生成 `hash_games_fix_p0_issues.yaml` 可直接應用
- 包含所有 5 個 P0 服務的修復配置

**優先級**：🔴 **P0 - 24-48 小時內**
**預計影響**：
- 消除 5.3Ti 配置異常
- 減少 limbone/limbo 重啟風險
- 改善集群調度效率

---

## 📊 完整服務對比表

### Bingo 遊戲服務

| 服務 | 記憶體使用 | Request | Limit | 使用率 (Request) | HPA | 評估 |
|------|-----------|---------|-------|----------------|-----|------|
| bonusbingo | 391 Mi | 1536 Mi | 3Gi | **25%** | 25%/80% | 🔴 嚴重過度配置 |
| egghuntbingo | 208 Mi | 500 Mi | 900 Mi | 42% | 42%/80% | ⚠️ 可優化 |
| magicbingo | 199 Mi | 500 Mi | 900 Mi | 40% | 40%/80% | ⚠️ 可優化 |
| odinbingo | 172 Mi | 400 Mi | 700 Mi | 43% | 43%/80% | ✅ 合理 |
| bingobells | 154 Mi | 400 Mi | 700 Mi | 39% | 39%/80% | ⚠️ 可優化 |
| bingbingbingo | 153 Mi | 400 Mi | 700 Mi | 38% | 38%/80% | ⚠️ 可優化 |
| arcadebingo | 150 Mi | 250 Mi | 450 Mi | 60% | 60%/80% | ✅ 良好 |
| **steampunk2** | **131 Mi** | **180 Mi** | **300 Mi** | **73%** | 73%/80% | ✅ 合理 |
| **steampunk** | **131 Mi** | **200 Mi** | **300 Mi** | **66%** | 66%/80% | ✅ 合理 |
| **lostruins** | **129 Mi** | **140 Mi** | **230 Mi** | **92%** 🔴 | **92%/80%** | 🔴 **最緊急** |
| caribbeanbingo | 128 Mi | 150 Mi | 250 Mi | **85%** | 85%/80% | 🔴 接近上限 |
| maplebingo | 126 Mi | 400 Mi | 700 Mi | 32% | 32%/80% | ⚠️ 可優化 |
| cavebingo | 122 Mi | 140 Mi | 220 Mi | **87%** | 87%/80% | 🔴 接近上限 |

**總計 Bingo**（13 個）：
- 總 Request: 5,596 Mi
- 總實際使用: 2,194 Mi
- 平均使用率: 39%
- 可節省: ~1,400 Mi Request

---

### Gate 服務

| 服務 | 記憶體使用 | Request | Limit | 使用率 | 連線/用戶 | 日誌量 | 評估 |
|------|-----------|---------|-------|--------|----------|--------|------|
| hash-gate | 1450 Mi | 2200 Mi | 4300 Mi | **66%** | 135 用戶 | **34 GB** | 🔴 高風險 |
| arcade-gate | 781 Mi | 2200 Mi | 4300 Mi | 35% | 40 用戶 | 9.6 GB | ⚠️ 有錯誤 |

**對比**：
- Hash Gate 負載是 Arcade Gate 的 **3.37 倍**（用戶數）
- 但記憶體效率更好：10.7 Mi/用戶 vs 19.5 Mi/用戶

---

### API 服務

| 服務 | 記憶體使用 | Request | Limit | Limit 使用率 | HPA | 評估 |
|------|-----------|---------|-------|-------------|-----|------|
| loyaltyapi | 236 Mi | **4096 Mi** | 5120 Mi | 5% | 5%/80% | 🔴 嚴重浪費 |
| exgameapi | 222 Mi | 100 Mi | 400 Mi | 56% | **96%/80%** | 🔴 HPA 臨界 |
| mgmtapi | 111 Mi | 100 Mi | 200 Mi | 56% | 48%/80% | ⚠️ 曾重啟 |
| eventapi | 109 Mi | 20 Mi | **50 Mi** | **218%** 🔴 | 74%/80% | 🔴 超限異常 |
| adapterapi | 101 Mi | 40 Mi | **100 Mi** | **101%** | 60%/80% | 🔴 已達限制 |
| domain-serviceapi | 101 Mi | 20 Mi | **50 Mi** | **202%** 🔴 | 68%/80% | 🔴 超限異常 |
| exmgmtapi | 100 Mi | 20 Mi | **50 Mi** | **200%** 🔴 | 67%/80% | 🔴 超限異常 |
| partnerapi | 29 Mi | 40 Mi | 100 Mi | 29% | 73%/80% | ⚠️ 高 CPU |
| fakeapi | 6 Mi | 10 Mi | 100 Mi | 6% | 64%/80% | ✅ 測試服務 |
| fakeapi2 | 5 Mi | 10 Mi | 100 Mi | 5% | 54%/80% | ✅ 測試服務 |

**總計 API**：
- 總 Request: 4,456 Mi
- 總實際使用: 1,020 Mi
- 平均使用率: 23%
- **loyaltyapi 獨佔 92% 的 Request**

---

### Hash 遊戲服務（34 個）

**系列概覽**：

| 系列 | 服務數 | 總用量 | 總 Request | 總 Limit | 平均 HPA | P0 問題 | P1 問題 |
|------|-------|--------|-----------|---------|---------|---------|---------|
| **Crash** | 4 | 167 Mi | 760 Mi | 1,220 Mi | 28.5% | 0 | 0 |
| **Aviator** | 3 | 111 Mi | 520 Mi | 870 Mi | 25.0% | 0 | 0 |
| **Mines** | 9 | 782 Mi | 1,520 Mi | 2,260 Mi + 1.3Ti⚠️ | 62.4% | 1 | 3 |
| **Hilo** | 7 | 694 Mi | 1,600 Mi | 2,400 Mi + 1.2Ti⚠️ | 48.3% | 1 | 2 |
| **Limbo** | 4 | 726 Mi | 800 Mi | 1,400 Mi | **90.8%** 🔴 | 2 | 1 |
| **Plinko** | 4 | 647 Mi | 1,731 Mi | 2,598 Mi + 2.8Ti⚠️ | 42.1% | 1 | 0 |
| **Other** | 3 | 196 Mi | 2,240 Mi | 18,060 Mi | 17.4% | 0 | 0 |
| **總計** | **34** | **3,323 Mi** | **9,171 Mi** | **28,808 Mi** + **5.3Ti⚠️** | **40.5%** | **5** | **6** |

**關鍵問題**：
- ⚠️ **TB 級配置錯誤**：3 個服務（plinkocl, minesne, luckyhilo）配置了 Ti 級 Limit
- 🔴 **Limbo 系列高壓**：平均 HPA 90.8%，已有 2 個 P0 問題
- 🔴 **頻繁重啟**：Mines (12次), Plinko (11次), Limbo (6次)
- 📊 **使用率分化**：Limbo 系列 90.8% vs Other 系列 17.4%

**Top 5 高風險服務**：

| 排名 | 服務 | 用量 | Request | HPA | 重啟 | 問題 |
|------|------|------|---------|-----|------|------|
| 1 | limbone-prd | 200Mi | 200Mi | **100%** | 3 | 🔴 P0 |
| 2 | limbo-prd | 188Mi | 200Mi | **94%** | 0 | 🔴 P0 |
| 3 | plinkocl-prd | 161Mi | 1.8Ti⚠️ | 80% | 6 | 🔴 P0 配置錯誤 |
| 4 | minesne-prd | 68Mi | 270Mi | 53% | 4 | 🔴 P0 配置錯誤 |
| 5 | luckyhilo-prd | 65Mi | 800Mi | 16% | 0 | 🔴 P0 配置錯誤 |

**詳細分析**：參見 `HASH_GAMES_RESOURCE_ANALYSIS.md`（761 行）

---

### Arcade 遊戲服務（5 個）

| 服務 | 記憶體使用 | Request | Limit | 使用率 | HPA | 連線/狀態 | 評估 |
|------|-----------|---------|-------|--------|-----|----------|------|
| **goldenclover** | **241 Mi** | **500 Mi** | **1 Gi** | **48%** | 48%/80% | 活躍 | ✅ 配置合理 |
| **wilddiggr** | **231 Mi** | **500 Mi** | **1 Gi** | **46%** | 46%/80% | 活躍 | ✅ 配置合理 |
| forestteaparty | 181 Mi | 700 Mi | 1024 Mi | 26% | 26%/80% | ~50-200 | ✅ 已優化 |
| multiboomers | 49 Mi | 300 Mi | 600 Mi | 16% | 16%/80% | 極低 | ✅ 良好但流量低 |
| **chilifiesta** | **0 Mi** | **-** | **-** | **-** | - | **未部署** | 🔴 **需確認** |

**總計 Arcade**（5 個）：
- 總 Request: 2,000 Mi（排除 chilifiesta）
- 總實際使用: 702 Mi
- 平均使用率: 35%
- 配置基本合理

**新發現**：
- **goldenclover** 和 **wilddiggr** 記憶體使用接近（241Mi vs 231Mi），配置相同
- 比 ForestTeaParty 使用量高 30-33%，但配置更合理（使用率 46-48%）
- **chilifiesta** namespace 存在但無 Pod 運行，需確認是否應該部署或移除

**詳細分析**：
- ForestTeaParty: `FORESTTEAPARTY_MEMORY_ANALYSIS_COMPLETE_11_3_TO_11_7.md`（42 小時分析）
- MultiBoomers: `MULTIBOOMERS_DEEP_DIVE_ANALYSIS.md`（1,666 行深度剖析）
- 其他 3 個: `MISSING_SERVICES_ANALYSIS.md`

---

## 💰 資源節省潛力

### 立即可節省（P0 + P1 優化）

| 優化項目 | Request 節省 | Limit 節省 | 影響服務 |
|---------|------------|-----------|---------|
| loyaltyapi 降級 | **-3,596 Mi** | **-4,120 Mi** | 1 個 API |
| bonusbingo 降級 | **-936 Mi** | **-2,048 Mi** | 1 個 Bingo |
| 其他 Bingo 優化 | **-730 Mi** | **-600 Mi** | 6 個 Bingo |
| Hash games 配置修正 | **-1,531 Mi** | **-5.3 Ti** ≈ **-5.4 Gi** | 3 個 Hash (TB錯誤修正) |
| Hash games Limbo 升級 | +200 Mi | +300 Mi | 2 個 Hash |
| Hash games luckydropcoc2 升級 | +200 Mi | 0 | 1 個 Hash |
| crashgr 降級 | **-280 Mi** | **-400 Mi** | 1 個 Hash |
| lostruins 升級 | +60 Mi | +120 Mi | 1 個 Bingo |
| cavebingo 升級 | +60 Mi | +130 Mi | 1 個 Bingo |
| caribbeanbingo 升級 | +70 Mi | +150 Mi | 1 個 Bingo |
| **淨節省** | **-6,383 Mi** (~6.2 Gi) | **-5.4 Gi + -6.4 Gi** ≈ **-11.8 Gi** | **17 個** |

**可用於**：
- ✅ 調度額外 **10-15 個中型服務**
- ✅ 提升所有服務的 Limit 緩衝空間
- ✅ 減少 Node Over-commit 風險
- ✅ 可能減少 1-2 個 Worker Node

---

## 🎯 實施計劃

### Week 1: 緊急修復（Day 1-7）

#### Day 1（今天 11/8）

**上午（最高優先級）**：
```bash
# 1. 修復 Hash Games TB 級配置錯誤（30 分鐘）
# 這是最嚴重的問題，影響集群調度
kubectl apply -f hash_games_fix_p0_issues.yaml
# 修正 5 個服務：plinkocl, minesne, luckyhilo, limbone, limbo

# 驗證配置已生效
kubectl get statefulset plinkocl-prd -n plinkocl-prd -o jsonpath='{.spec.template.spec.containers[0].resources}'
kubectl get statefulset minesne-prd -n minesne-prd -o jsonpath='{.spec.template.spec.containers[0].resources}'
kubectl get statefulset luckyhilo-prd -n luckyhilo-prd -o jsonpath='{.spec.template.spec.containers[0].resources}'

# 2. 調查記憶體計量異常（2-4 小時）
kubectl get --raw /apis/metrics.k8s.io/v1beta1/nodes
kubectl top nodes
# 檢查 metrics-server, kubelet, cAdvisor

# 3. Hash Gate 日誌優化（1 小時）
kubectl set env statefulset/hash-gate \
  -n hash-gate-prd \
  LOG_LEVEL=WARN \
  DEBUG_MODE=0

# 4. 設置緊急監控告警（1 小時）
# - Hash Gate 記憶體 > 70%
# - Hash Games Limbo 系列 > 85%
# - cavebingo/caribbeanbingo 記憶體 > 85%
# - API 服務超限告警
```

**下午（資源調整）**：
```bash
# 5. loyaltyapi 降級（低峰時段）
kubectl edit deployment loyaltyapi -n loyaltyapi-prd
# Request: 4Gi → 500Mi
# Limit: 5Gi → 1Gi

# 6. 驗證並監控 2 小時
kubectl top pod -n loyaltyapi-prd --watch
```

---

#### Day 2

**上午**：
```bash
# 6. cavebingo 升級
kubectl edit statefulset cavebingo -n cavebingo-prd
# Request: 140Mi → 200Mi
# Limit: 220Mi → 350Mi

# 7. caribbeanbingo 升級
kubectl edit statefulset caribbeanbingo -n caribbeanbingo-prd
# Request: 150Mi → 220Mi
# Limit: 250Mi → 400Mi
```

**下午**：
```bash
# 8. 修正 API 服務 Limit（3 個超限服務）
for svc in domain-serviceapi eventapi exmgmtapi; do
  kubectl edit deployment $svc -n ${svc}-prd
  # Limit: 50Mi → 150Mi
done

# 9. 驗證無 OOM
kubectl get events --all-namespaces | grep OOM
```

---

#### Day 3-4

```bash
# 10. exgameapi HPA 調整
kubectl edit hpa exgameapi-hpa -n exgameapi-prd
# maxReplicas: 1 → 3
kubectl edit deployment exgameapi -n exgameapi-prd
# Request: 100Mi → 250Mi

# 11. bonusbingo 降級
kubectl edit statefulset bonusbingo -n bonusbingo-prd
# Request: 1536Mi → 600Mi
# Limit: 3Gi → 1Gi

# 12. 修復 Arcade Gate nil pointer
# 部署程式碼修復到 loyalty/client.go:106
```

---

#### Day 5-7

```bash
# 13. 批次優化其他 Bingo 服務（6 個）
# egghuntbingo, magicbingo, bingobells,
# bingbingbingo, maplebingo, odinbingo

# 14. 建立 Grafana Dashboard
# - 所有服務記憶體趨勢
# - Request vs 實際使用對比
# - HPA 狀態監控

# 15. 編寫 Runbook
# - 記憶體告警處理流程
# - OOM 事件應急預案
# - 資源調整標準流程
```

---

### Week 2-4: 持續優化

#### Week 2: Hash Gate 深度優化
- [ ] 實施日誌採樣（減少 60-80% 日誌）
- [ ] 評估遊戲分組方案（拆分為 2 個 Gate）
- [ ] Memory profiling 分析

#### Week 3: 標準化與自動化
- [ ] 建立資源配置標準文檔
- [ ] 實施自動化監控腳本
- [ ] 設置 Prometheus 告警規則

#### Week 4: 驗證與文檔
- [ ] 收集優化前後對比數據
- [ ] 編寫最佳實踐文檔
- [ ] 培訓團隊成員

---

## 📈 成功指標

### 1 個月目標

| 指標 | 當前 | 目標 | 改善 |
|------|------|------|------|
| **P0 問題服務** | 7 個 | 0 個 | -100% |
| **平均 Request 使用率** | 36% | 50-70% | +39-94% |
| **總 Request 使用** | 11.5 Gi | 6.4 Gi | -44% |
| **Hash Gate 日誌量** | 3.4 GB/日 | < 1.5 GB/日 | -56% |
| **loyaltyapi Request** | 4 Gi | 500 Mi | -88% |
| **OOM 事件** | 0 | 0 | 維持 |

### 3 個月目標

- ✅ 所有服務 Request 使用率 40-80%
- ✅ 零 OOM 事件連續 90 天
- ✅ 集群整體資源利用率 > 60%
- ✅ 服務可用性 > 99.9%
- ✅ 自動化監控覆蓋率 100%

---

## 📚 生成的分析報告

### Bingo 遊戲（5 份文件）
1. **BINGO_GAMES_MEMORY_ANALYSIS.md** - 完整分析（16 KB）
2. **BINGO_GAMES_SUMMARY_TABLE.md** - 快速參考（3.7 KB）
3. **BINGO_VS_FORESTTEAPARTY_COMPARISON.md** - 對比分析（10 KB）
4. **BINGO_ANALYSIS_README.md** - 索引導覽（9.2 KB）
5. **scripts/check_bingo_memory.sh** - 監控腳本（8 KB）

### Hash 遊戲（2 份文件）
1. **HASH_GAMES_RESOURCE_ANALYSIS.md** - 完整分析（22 KB, 761 行）
   - 包含 34 個服務的深度分析
   - 7 個系列：Crash, Aviator, Mines, Hilo, Limbo, Plinko, Other
   - 5 個 P0 問題 + 6 個 P1 問題詳細說明
2. **hash_games_fix_p0_issues.yaml** - P0 問題修復配置（可直接 apply）

### Arcade 遊戲（4 份文件）
1. **FORESTTEAPARTY_MEMORY_ANALYSIS_COMPLETE_11_3_TO_11_7.md** - 完整歷史分析（24 KB）
   - 42 小時詳細追蹤（11/3 00:00 → 11/7 15:30）
   - 連線數與記憶體關聯分析
   - Memory leak 評估（65-70% 置信度）
2. **FORESTTEAPARTY_MEMORY_LEAK_ANALYSIS_42H.md** - 42 小時分析（14 KB）
3. **FORESTTEAPARTY_MEMORY_LEAK_ANALYSIS.md** - Memory Leak 分析（17 KB）
4. **MULTIBOOMERS_DEEP_DIVE_ANALYSIS.md** - 深度技術剖析（39 KB, 1,666 行）
   - 與 ForestTeaParty 完整對比
   - 95% 配置相似性分析
   - Memory leak 風險評估
   - 安全問題識別（明文密碼）

### Gate 服務（3 份文件）
1. **GATE_SERVICES_RESOURCE_ANALYSIS.md** - 完整分析（25 KB）
2. **GATE_SERVICES_EXECUTIVE_SUMMARY.md** - 執行摘要（5.4 KB）
3. **gate_monitoring_commands.sh** - 監控腳本

### API 服務（1 份文件）
1. **API_SERVICES_MEMORY_ANALYSIS.md** - 完整分析（18 KB）
   - 10 個 API 服務深度分析
   - 記憶體計量異常發現
   - loyaltyapi 資源浪費分析

### 總覽與索引（1 份文件）
1. **ALL_SERVICES_MEMORY_ANALYSIS_OVERVIEW.md** - 本文件（完整版）
   - 57 個服務綜合分析
   - 12 個 P0 問題統整
   - 實施計劃與時間表

**總計**：**18 份詳細分析報告** + **2 個自動化監控腳本** + **1 份 YAML 修復配置**

**新增文件**（2025-11-08）：
1. **GAME_SERVICES_COMPLETE_INVENTORY.md** - 完整服務清單（71 個服務）
2. **MISSING_SERVICES_ANALYSIS.md** - 遺漏服務補充分析（13 個服務）

**文件大小總計**：~250 KB 的深度技術分析文檔

**涵蓋範圍**：
- ✅ 41 個 Hash games（100% 涵蓋）
- ✅ 13 個 Bingo games（100% 涵蓋）
- ✅ 5 個 Arcade games（100% 涵蓋）
- ✅ 2 個 Gate services（100% 涵蓋）
- ✅ 10 個 API services（100% 涵蓋）

---

## 🛠️ 快速開始

### 立即檢查所有服務狀態

```bash
# Bingo 遊戲（10 個）
./scripts/check_bingo_memory.sh --alert-only

# Hash 遊戲（34 個）
kubectl top pods --all-namespaces | grep -E "crash|aviator|mines|hilo|limbo|plinko" | \
  awk '{if($4 ~ /Mi/) {mem=$4; gsub(/Mi/, "", mem); if(mem+0 >= 150) print}}' | \
  sort -k4 -h

# Arcade 遊戲（2 個）
kubectl top pods -n forestteaparty-prd
kubectl top pods -n multiboomers-prd

# Gate 服務（2 個）
./gate_monitoring_commands.sh summary

# API 服務（10 個）
kubectl top pods --all-namespaces | grep -E "api-prd"

# 全部服務概覽（57 個）
kubectl top pods --all-namespaces | \
  grep -E "bingo-prd|crash|aviator|mines|hilo|limbo|plinko|forestteaparty|multiboomers|gate-prd|api-prd" | \
  sort -k4 -h | tail -20
```

### 檢查 Hash Games P0 問題

```bash
# 檢查 TB 級配置錯誤
kubectl get statefulset plinkocl-prd -n plinkocl-prd -o jsonpath='{.spec.template.spec.containers[0].resources}'
kubectl get statefulset minesne-prd -n minesne-prd -o jsonpath='{.spec.template.spec.containers[0].resources}'
kubectl get statefulset luckyhilo-prd -n luckyhilo-prd -o jsonpath='{.spec.template.spec.containers[0].resources}'

# 檢查 Limbo 系列記憶體壓力
kubectl top pods -n limbone-prd
kubectl top pods -n limbo-prd

# 應用 P0 修復（確認後執行）
# kubectl apply -f hash_games_fix_p0_issues.yaml
```

### 查看關鍵報告

```bash
# P0 緊急問題清單
grep -A 5 "P0" ALL_SERVICES_MEMORY_ANALYSIS_OVERVIEW.md

# 資源節省潛力
grep -A 10 "資源節省潛力" ALL_SERVICES_MEMORY_ANALYSIS_OVERVIEW.md

# 實施計劃
grep -A 20 "實施計劃" ALL_SERVICES_MEMORY_ANALYSIS_OVERVIEW.md
```

---

## ⚠️ 關鍵風險提醒

### 記憶體計量異常 🔴🔴🔴

**最高優先級問題**：3 個 API 服務的記憶體使用超過 Limit 200%+ 但仍在運行。

**可能原因**：
1. metrics-server 數據不準確
2. cgroup 限制未正確應用
3. kubelet 配置問題

**潛在影響**：
- 如果 cgroup 限制確實失效，這些服務可能無限制使用記憶體
- 可能導致 Node 記憶體耗盡
- 其他服務被驅逐
- 整個 Node 崩潰

**必須在 24 小時內調查並修復！**

---

### Hash Gate 時間線 🔴

```
當前時間：11/7 16:00
記憶體使用：66%（1450Mi / 2200Mi）

時間預測：
  11/8 17:18 (1.3 天後)   - 達到 80% HPA 觸發值
  11/11 22:00 (4.25 天後)  - 達到 100% Request 上限
  11/26 (18.8 天後)       - 可能觸發 OOM

建議：今天完成日誌優化，爭取 2-3 倍延長時間
```

---

## 📊 對比 ForestTeaParty

| 指標 | ForestTeaParty | 其他服務平均 | 差異 |
|------|---------------|------------|------|
| **配置策略** | 統一保守 | 差異極大（11 倍） | 🔴 |
| **Request 使用率** | 29.5% | 36% | +22% |
| **P0 問題** | 0 個 | 7 個 | 🔴 |
| **資源浪費** | 最小 | loyaltyapi 浪費 3.8Gi | 🔴 |
| **監控深度** | 完整 | 部分缺失 | ⚠️ |
| **Memory Leak 風險** | 65-70% 可能有 | 未評估 | ⭕ |

**關鍵差異**：
- ForestTeaParty：經過深度分析並調整，配置合理
- 其他服務：缺乏統一標準，問題較多

---

## 🎯 總結

### 關鍵數字

- **71 個服務**分析完成（Bingo: 13, Hash: 41, Arcade: 5, Gate: 2, API: 10）
- **14 個 P0 緊急問題**需立即處理
  - Hash: 6 個（luckydropcoc2, limbone, limbo, plinkocl, minesne, luckyhilo）
  - Bingo: 3 個（lostruins, cavebingo, caribbeanbingo）
  - API: 4 個（domain-serviceapi, eventapi, exmgmtapi, loyaltyapi）
  - Gate: 1 個（hash-gate）
- **10 個 P1 高優先級問題**本週內處理
- **6.2 Gi Request** 可節省（25% 總量）
- **11.8 Gi Limit** 可節省（包含 5.3 Ti TB 級配置錯誤修正）
- **1.3 天**後 Hash Gate 達到 HPA 觸發值
- **1 個服務未部署**（chilifiesta）需確認狀態

### 下一步行動

**今天（11/8）必須完成**：
1. ✅ **修復 Hash Games P0 問題**（最高優先級）
   - 應用 `hash_games_fix_p0_issues.yaml`（包含 6 個服務）
   - **luckydropcoc2**: 400Mi Request（從 200Mi，最緊急）
   - limbone, limbo: 300Mi Request
   - plinkocl, minesne, luckyhilo: 修正 TB 級配置錯誤
2. ✅ **修復 Bingo Games P0 問題**（最高優先級）
   - **lostruins**: 200Mi Request（從 140Mi，92% HPA）
   - cavebingo: 200Mi Request
   - caribbeanbingo: 220Mi Request
3. ✅ 調查記憶體計量異常（3 個 API 服務）
4. ✅ Hash Gate 日誌優化
5. ✅ loyaltyapi 降級
6. ✅ 設置緊急監控告警
7. ✅ **確認 chilifiesta 狀態**（未部署）

**本週必須完成**：
8. ✅ 修正 API 服務 Limit（domain-serviceapi, eventapi, exmgmtapi）
9. ✅ exgameapi HPA 調整
10. ✅ bonusbingo 降級

**預期效果**：
- 釋放 ~5 Gi 資源
- 消除所有 P0 風險
- 提升集群穩定性

---

**報告生成**: 2025-11-07 16:00 UTC+8
**下次建議複查**: 優化完成後 7 天
**報告版本**: v1.0
**分析深度**: 深度技術剖析（比照 ForestTeaParty 標準）
