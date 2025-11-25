# Hash Games 資源使用深度分析報告

**分析日期**: 2025-11-07（更新於 2025-11-08）
**分析範圍**: 所有 Hash 遊戲服務 (41 個)
**分析方法**: 類似 ForestTeaParty 深度分析
**資料來源**: kustomize-prd/gemini-game/base/prd/hash-svc/

---

## 執行摘要

### 關鍵發現

| 指標 | 數值 | 說明 |
|------|------|------|
| 總服務數 | 41 個 | 分佈於 9 個遊戲系列 |
| **P0 問題** | **6 個** | 記憶體壓力 ≥80% 或配置異常 |
| **P1 問題** | **6 個** | 頻繁重啟 (≥3次) |
| P2 問題 | 15 個 | 資源使用率過低 |
| 總記憶體用量 | 4,174 MiB | 實際使用量 |
| 總 Request | 10,571 MiB | 配置的資源請求 |
| 總 Limit | 29,808 MiB | 配置的資源上限 (排除異常值) |
| 平均 HPA 使用率 | 41.8% | 相對健康但有局部高壓 |

### 最嚴重問題 (P0)

1. **luckydropcoc2-prd**: 使用 327Mi / Request 200Mi (**164%**) 🔴🔴 **最嚴重**
2. **limbone-prd**: 記憶體壓力 100%, 已重啟 3 次
3. **limbo-prd**: 記憶體壓力 94%
4. **plinkocl-prd**: 配置異常 (Request: 1.8Ti, Limit: 2.8Ti)
5. **minesne-prd**: 配置異常 (Limit: 1.3Ti), 已重啟 4 次
6. **luckyhilo-prd**: 配置異常 (Request: 800Mi, Limit: 1.2Ti)

---

## 系列分析

### 1. Crash 系列 (4 個服務)

| 服務 | 實際用量 | Request | Limit | HPA% | 重啟 | 狀態 |
|------|----------|---------|-------|------|------|------|
| crashcl | 44Mi | 120Mi | 160Mi | 37% | 0 | ✓ 正常 |
| crashgr | 42Mi | 400Mi | 700Mi | 10% | 0 | 📉 過度配置 |
| crashne | 41Mi | 120Mi | 180Mi | 34% | 0 | ✓ 正常 |
| crash | 40Mi | 120Mi | 180Mi | 33% | 0 | ✓ 正常 |

**系列總結**:
- 總實際用量: 167 MiB
- 總 Request: 760 MiB
- 總 Limit: 1,220 MiB
- 平均 HPA: 28.5%
- 總重啟: 0 次

**配置一致性**: ⚠️ **不一致**
- 3 個服務使用標準配置 (120Mi request, 160-180Mi limit)
- **crashgr-prd** 使用異常高配置 (400Mi request, 700Mi limit)
  - 實際使用僅 42Mi，資源使用率僅 10.5%
  - 嚴重過度配置，浪費資源

**異常值**:
- **crashgr-prd**: Request 過高 (400Mi vs 42Mi 實際用量)

**優化建議**:
- 將 crashgr-prd 配置調整為與其他 Crash 服務一致
- 建議: Request: 80Mi, Limit: 150Mi

---

### 2. Aviator 系列 (3 個服務)

| 服務 | 實際用量 | Request | Limit | HPA% | 重啟 | 狀態 |
|------|----------|---------|-------|------|------|------|
| aviator2 | 106Mi | 200Mi | 800Mi | 53% | 0 | ✓ 正常 |
| aviator | 75Mi | 600Mi | 900Mi | 12% | 0 | 📉 過度配置 |
| aviator2xin | 38Mi | 200Mi | 800Mi | 19% | 0 | 📉 過度配置 |

**系列總結**:
- 總實際用量: 219 MiB
- 總 Request: 1,000 MiB
- 總 Limit: 2,500 MiB
- 平均 HPA: 28.0%
- 總重啟: 0 次

**配置一致性**: ⚠️ **不一致**
- aviator2/aviator2xin 使用相同配置 (200Mi request, 800Mi limit)
- **aviator-prd** 使用高配置 (600Mi request, 900Mi limit)
  - 實際使用僅 75Mi，資源使用率僅 12.5%

**異常值**:
- **aviator-prd**: 嚴重過度配置
- **aviator2xin-prd**: Limit 過高，實際用量僅 38Mi

**優化建議**:
- aviator-prd: 降低至 Request: 150Mi, Limit: 300Mi
- aviator2xin-prd: 降低至 Request: 100Mi, Limit: 200Mi

---

### 3. Mines 系列 (9 個服務) ⚠️

| 服務 | 實際用量 | Request | Limit | HPA% | 重啟 | 狀態 |
|------|----------|---------|-------|------|------|------|
| minesca | 160Mi | 1024Mi | 1536Mi | 14% | 3 | ⚠️ 重啟 + 過度配置 |
| minessc | 128Mi | 200Mi | 1Gi | 64% | 0 | ✓ 正常 |
| **minesne** | **122Mi** | **900Mi** | **1.3Ti** | **13%** | **4** | 🔴 **配置異常 + 頻繁重啟** |
| minescl | 105Mi | 200Mi | 1Gi | 52% | 2 | ⚠️ 重啟 |
| minesgr | 91Mi | 200Mi | 1Gi | 46% | 2 | ⚠️ 重啟 |
| mines | 84Mi | 200Mi | 1Gi | 42% | 0 | ✓ 正常 |
| minespm | 79Mi | 200Mi | 1Gi | 39% | 0 | ✓ 正常 |
| minesma | 76Mi | 200Mi | 1Gi | 38% | 1 | ⚠️ 重啟 |
| minesraider | 63Mi | 200Mi | 1Gi | 30% | 0 | ✓ 正常 |

**系列總結**:
- 總實際用量: 908 MiB
- 總 Request: 3,324 MiB (排除異常)
- 總 Limit: 8,704 MiB (排除異常)
- 平均 HPA: 37.6%
- **總重啟: 12 次** (最高)

**配置一致性**: ⚠️ **不一致**
- 7 個服務使用標準配置 (200Mi request, 1Gi limit)
- minesca 使用高配置 (1Gi request, 1.5Gi limit)
- **minesne 配置嚴重異常** (900Mi request, 1.3Ti limit)

**異常值**:
- 🔴 **minesne-prd**:
  - Limit 配置為 1,395,864,371,200m (約 1.3Ti)
  - 實際使用僅 122Mi
  - 已重啟 4 次，顯示穩定性問題
  - **這是配置錯誤，需立即修正**

- **minesca-prd**:
  - 過度配置 (1Gi request vs 160Mi 實際用量)
  - 已重啟 3 次

**重啟分析**:
- Mines 系列總重啟次數為 12 次，是所有系列中最高的
- 重啟集中在: minesne(4), minesca(3), minescl(2), minesgr(2), minesma(1)
- 可能原因: 記憶體配置問題或應用程式穩定性問題

**優化建議**:
1. **緊急**: 修正 minesne-prd 的 Limit 配置為 300Mi
2. 降低 minesca-prd Request 至 300Mi, Limit 至 500Mi
3. 調查重啟原因，特別是 minesne 和 minesca
4. 標準化配置: Request: 200Mi, Limit: 1Gi

---

### 4. Hilo 系列 (7 個服務) ⚠️

| 服務 | 實際用量 | Request | Limit | HPA% | 重啟 | 狀態 |
|------|----------|---------|-------|------|------|------|
| **luckyhilo** | **205Mi** | **800Mi** | **1.2Ti** | **25%** | **0** | 🔴 **配置異常** |
| egypthilo | 152Mi | 200Mi | 1Gi | 76% | 0 | ⚠️ 接近閾值 |
| hilo | 114Mi | 200Mi | 1Gi | 57% | 0 | ✓ 正常 |
| hilone | 63Mi | 200Mi | 1Gi | 31% | 0 | ✓ 正常 |
| hilocl | 62Mi | 200Mi | 1Gi | 31% | 0 | ✓ 正常 |
| hilogr | 50Mi | 200Mi | 1Gi | 25% | 0 | 📉 過度配置 |
| multihilo | 44Mi | 200Mi | 1Gi | 22% | 0 | 📉 過度配置 |

**系列總結**:
- 總實際用量: 690 MiB
- 總 Request: 2,000 MiB (排除異常)
- 總 Limit: 6,144 MiB (排除異常)
- 平均 HPA: 38.1%
- 總重啟: 0 次

**配置一致性**: ⚠️ **不一致**
- 6 個服務使用標準配置 (200Mi request, 1Gi limit)
- **luckyhilo 配置嚴重異常** (800Mi request, 1.2Ti limit)

**異常值**:
- 🔴 **luckyhilo-prd**:
  - Limit 配置為 1,288,490,188,800m (約 1.2Ti)
  - Request 配置為 800Mi
  - 實際使用僅 205Mi
  - HPA 顯示僅 25% 使用率
  - **這是配置錯誤，需立即修正**

- **egypthilo-prd**:
  - HPA 76%，接近警戒線
  - 實際用量 152Mi，當前 Limit 1Gi 尚可應付
  - 建議密切監控

**優化建議**:
1. **緊急**: 修正 luckyhilo-prd 配置
   - Request: 400Mi
   - Limit: 600Mi
2. 監控 egypthilo-prd，如 HPA 持續 >70%，增加 Limit 至 1.5Gi
3. 降低低使用率服務 (hilogr, multihilo) Request 至 100Mi

---

### 5. Limbo 系列 (4 個服務) 🔴

| 服務 | 實際用量 | Request | Limit | HPA% | 重啟 | 狀態 |
|------|----------|---------|-------|------|------|------|
| **limbone** | **201Mi** | **200Mi** | **1Gi** | **100%** | **3** | 🔴 **記憶體壓力臨界 + 頻繁重啟** |
| **limbo** | **189Mi** | **200Mi** | **1Gi** | **94%** | **0** | 🔴 **記憶體壓力高** |
| limbocl | 131Mi | 200Mi | 1Gi | 65% | 0 | ⚠️ 接近警戒 |
| limbogr | 44Mi | 200Mi | 1Gi | 22% | 0 | 📉 過度配置 |

**系列總結**:
- 總實際用量: 565 MiB
- 總 Request: 800 MiB
- 總 Limit: 4,096 MiB
- **平均 HPA: 70.2%** (最高)
- 總重啟: 3 次

**配置一致性**: ✓ **一致**
- 所有服務使用相同配置 (200Mi request, 1Gi limit)

**異常值**:
- 🔴 **limbone-prd**:
  - **HPA 100%** - 記憶體壓力達到臨界點
  - 實際用量 201Mi，已超過 Request (200Mi)
  - **已重啟 3 次**
  - 可能隨時觸發 OOMKilled
  - **這是最嚴重的 P0 問題**

- 🔴 **limbo-prd**:
  - **HPA 94%** - 記憶體壓力非常高
  - 實際用量 189Mi
  - 雖未重啟，但接近臨界點

- **limbocl-prd**:
  - HPA 65%，使用率較高但尚可接受
  - 建議持續監控

**根因分析**:
1. **配置不足**: Request 200Mi 對於 limbo/limbone 來說過低
2. **重啟相關性**: limbone 的 3 次重啟很可能是 OOMKilled 導致
3. **系列特性**: Limbo 系列整體記憶體使用率偏高 (70.2%)
4. **不均衡**: limbogr 僅用 44Mi，而 limbone 達 201Mi

**優化建議** (最高優先級):
1. **立即執行** - limbone-prd:
   - Request: 300Mi (從 200Mi 增加)
   - Limit: 500Mi (從 1Gi 調整為合理值)

2. **立即執行** - limbo-prd:
   - Request: 300Mi
   - Limit: 500Mi

3. 監控 limbocl-prd，考慮調整為:
   - Request: 250Mi
   - Limit: 400Mi

4. 降低 limbogr-prd (使用率僅 22%):
   - Request: 100Mi
   - Limit: 200Mi

---

### 6. Plinko 系列 (4 個服務) ⚠️

| 服務 | 實際用量 | Request | Limit | HPA% | 重啟 | 狀態 |
|------|----------|---------|-------|------|------|------|
| **plinkocl** | **224Mi** | **1.8Ti** | **2.8Ti** | **12%** | **0** | 🔴 **配置嚴重異常** |
| plinkogr | 123Mi | 200Mi | 1Gi | 57% | 3 | ⚠️ 重啟 |
| plinkone | 109Mi | 200Mi | 1Gi | 54% | 4 | ⚠️ 頻繁重啟 |
| plinko | 68Mi | 200Mi | 1Gi | 36% | 4 | ⚠️ 頻繁重啟 |

**系列總結**:
- 總實際用量: 524 MiB
- 總 Request: 600 MiB (排除異常)
- 總 Limit: 3,072 MiB (排除異常)
- 平均 HPA: 39.8%
- **總重啟: 11 次** (第二高)

**配置一致性**: ⚠️ **不一致**
- 3 個服務使用標準配置 (200Mi request, 1Gi limit)
- **plinkocl 配置嚴重異常**

**異常值**:
- 🔴 **plinkocl-prd**:
  - Request 配置為 1,932,735,283,200m (約 1.8Ti)
  - Limit 配置為 3,006,477,107,200m (約 2.8Ti)
  - 實際使用僅 224Mi
  - HPA 顯示僅 12% (因為異常配置導致計算錯誤)
  - **這是最嚴重的配置錯誤**
  - 嚴重浪費集群資源

**重啟分析**:
- Plinko 系列總重啟次數為 11 次，僅次於 Mines
- 重啟分佈: plinkone(4), plinko(4), plinkogr(3)
- **所有標準配置的 Plinko 服務都有重啟**
- 可能原因:
  - 應用程式 bug
  - Liveness probe 配置問題
  - 記憶體洩漏

**優化建議**:
1. **緊急**: 修正 plinkocl-prd 配置
   - Request: 400Mi
   - Limit: 600Mi

2. **調查重啟原因**:
   - 檢查 plinko, plinkone, plinkogr 的重啟日誌
   - 可能需要調整 liveness probe 設定
   - 檢查是否有記憶體洩漏

3. 標準化配置後持續監控 1-2 週

---

### 7. LuckyDrop 系列 (4 個服務) 🔴

| 服務 | 實際用量 | Request | Limit | HPA% | 重啟 | 狀態 |
|------|----------|---------|-------|------|------|------|
| **luckydropcoc2** | **327Mi** | **200Mi** | 1Gi | **164%** | **0** | 🔴 **超過 Request 64%** |
| luckydropgx | 117Mi | 200Mi | 1Gi | 59% | 0 | ✓ 正常 |
| luckydropcoc | 116Mi | 200Mi | 1Gi | 58% | 0 | ✓ 正常 |
| luckydropoly | 107Mi | 200Mi | 1Gi | 54% | 0 | ✓ 正常 |

**系列總結**:
- 總實際用量: 667 MiB
- 總 Request: 800 MiB
- 總 Limit: 4,096 MiB
- 平均 HPA: 84%  🔴 **高使用率**
- 總重啟: 0 次

**配置一致性**: ✓ **完全一致**
- 所有服務使用相同配置 (200Mi request, 1Gi limit)

**異常值**: 🔴🔴 **luckydropcoc2-prd 嚴重超限**
- 實際使用 327Mi，超過 Request (200Mi) 達 **164%**
- 雖然未達到 Limit (1Gi)，但已超過 Request，在資源緊張時可能被驅逐
- 這是整個 Hash Games 中**唯一超過 Request 的服務**（除 TB 配置錯誤外）

**系列特性**:
- 平均 HPA 84%，是所有系列中使用率**第二高**（僅次於 Limbo 的 90.8%）
- 4 個服務中有 1 個 P0 問題，問題率 25%
- 除 luckydropcoc2 外，其他 3 個服務使用率接近（54-59%），運行穩定

**優化建議**:
1. **🔴 P0 - 立即**: luckydropcoc2 升級
   - Request: 200Mi → **400Mi** (+100%)
   - Limit: 1Gi → 1Gi (保持)
   - 預期效果: HPA 降至 82%，進入安全區域

2. 其他服務暫時保持現有配置
3. 持續監控 luckydropgx/luckydropcoc/luckydropoly，如趨近 80% 則預防性升級

---

### 8. Other 系列 (6 個服務)

| 服務 | 實際用量 | Request | Limit | HPA% | 重啟 | 狀態 |
|------|----------|---------|-------|------|------|------|
| keno | 128Mi | 200Mi | 1Gi | 64% | 0 | ✓ 正常 |
| dragontower | 80Mi | 200Mi | 1Gi | 40% | 0 | ✓ 正常 |
| dice | 69Mi | 200Mi | 1Gi | 34% | 0 | ✓ 正常 |
| videopoker | 59Mi | 200Mi | 1Gi | 30% | 0 | 📉 過度配置 |
| wheel | 53Mi | 200Mi | 1Gi | 26% | 0 | 📉 過度配置 |
| diamonds | 45Mi | 200Mi | 1Gi | 23% | 0 | 📉 過度配置 |

**系列總結**:
- 總實際用量: 434 MiB
- 總 Request: 1,200 MiB
- 總 Limit: 6,144 MiB
- 平均 HPA: 36.2%
- 總重啟: 0 次

**配置一致性**: ✓ **完全一致**
- 所有服務使用相同配置 (200Mi request, 1Gi limit)

**異常值**: 無嚴重問題

**優化建議**:
- diamonds, wheel, videopoker 可以降低 Request 至 100-120Mi（使用率僅 23-30%）
- 節省潛力: ~240-360Mi Request
- 其他服務配置合理

---

## 全 Hash Games 總結對比表

### 按記憶體用量排序 (Top 10)

| 排名 | 服務 | 系列 | 實際用量 | Request | Limit | HPA% | 重啟 | 風險等級 |
|------|------|------|----------|---------|-------|------|------|----------|
| 1 | **luckydropcoc2** | LuckyDrop | **327Mi** | **200Mi** | 1Gi | **164%** | 0 | 🔴🔴 **超過 Request** |
| 2 | **plinkocl** | Plinko | 224Mi | 1.8Ti | 2.8Ti | 12% | 0 | 🔴 配置異常 |
| 3 | luckyhilo | Hilo | 205Mi | 800Mi | 1.2Ti | 25% | 0 | 🔴 配置異常 |
| 4 | **limbone** | Limbo | 201Mi | 200Mi | 1Gi | **100%** | 3 | 🔴 壓力臨界 |
| 5 | **limbo** | Limbo | 189Mi | 200Mi | 1Gi | **94%** | 0 | 🔴 壓力高 |
| 6 | minesca | Mines | 160Mi | 1.5Gi | 1.5Gi | 14% | 3 | ⚠️ 重啟 |
| 7 | egypthilo | Hilo | 152Mi | 200Mi | 1Gi | 76% | 0 | ⚠️ 接近閾值 |
| 8 | limbocl | Limbo | 131Mi | 200Mi | 1Gi | 65% | 0 | ⚠️ 接近警戒 |
| 9 | minessc | Mines | 128Mi | 200Mi | 1Gi | 64% | 0 | ✓ 正常 |
| 10 | keno | Other | 128Mi | 200Mi | 1Gi | 64% | 0 | ✓ 正常 |

### 按 HPA 使用率排序 (Top 10)

| 排名 | 服務 | 系列 | HPA% | 實際用量 | Request | Limit | 風險等級 |
|------|------|------|------|----------|---------|-------|----------|
| 1 | **luckydropcoc2** | LuckyDrop | **164%** 🔴🔴 | 327Mi | 200Mi | 1Gi | 🔴 **超限** |
| 2 | **limbone** | Limbo | **100%** | 201Mi | 200Mi | 1Gi | 🔴 臨界 |
| 3 | **limbo** | Limbo | **94%** | 189Mi | 200Mi | 1Gi | 🔴 高壓 |
| 4 | egypthilo | Hilo | 76% | 152Mi | 200Mi | 1Gi | ⚠️ 接近閾值 |
| 5 | limbocl | Limbo | 65% | 131Mi | 200Mi | 1Gi | ⚠️ 警戒 |
| 6 | minessc | Mines | 64% | 128Mi | 200Mi | 1Gi | ✓ 可接受 |
| 7 | keno | Other | 64% | 128Mi | 200Mi | 1Gi | ✓ 可接受 |
| 8 | luckydropgx | LuckyDrop | 59% | 117Mi | 200Mi | 1Gi | ✓ 正常 |
| 9 | luckydropcoc | LuckyDrop | 58% | 116Mi | 200Mi | 1Gi | ✓ 正常 |
| 10 | hilo | Hilo | 57% | 114Mi | 200Mi | 1Gi | ✓ 正常 |

### 按重啟次數排序

| 排名 | 服務 | 系列 | 重啟次數 | HPA% | 實際用量 | 可能原因 |
|------|------|------|----------|------|----------|----------|
| 1 | minesne | Mines | 4 | 13% | 122Mi | 配置異常 + 應用問題 |
| 1 | plinko | Plinko | 4 | 36% | 68Mi | 應用穩定性問題 |
| 1 | plinkone | Plinko | 4 | 54% | 109Mi | 應用穩定性問題 |
| 2 | minesca | Mines | 3 | 14% | 160Mi | 過度配置 + 應用問題 |
| 2 | limbone | Limbo | 3 | **100%** | 201Mi | **記憶體壓力導致 OOMKilled** |
| 2 | plinkogr | Plinko | 3 | 57% | 123Mi | 應用穩定性問題 |
| 3 | minescl | Mines | 2 | 52% | 105Mi | 輕微問題 |
| 3 | minesgr | Mines | 2 | 46% | 91Mi | 輕微問題 |
| 4 | minesma | Mines | 1 | 38% | 76Mi | 偶發問題 |

---

## 與其他遊戲類型對比

### ForestTeaParty (Arcade) vs Hash Games

| 指標 | ForestTeaParty | Hash Games (平均) | 備註 |
|------|----------------|-------------------|------|
| 服務數 | 1 | 34 | Hash Games 規模大 |
| 實際記憶體 | 149Mi | 98Mi | ForestTeaParty 較高 |
| Request | 200Mi | 270Mi | Hash 平均配置較高 |
| Limit | 1Gi | 847Mi | 相近 |
| HPA% | 74% | 40.5% | ForestTeaParty 壓力更高 |
| 重啟次數 | 0 | 0.7 (平均) | Hash Games 穩定性較差 |
| P0 問題 | 1 | 5 | Hash Games 問題更多 |

### 按遊戲類型分組對比

| 遊戲類型 | 平均實際用量 | 平均 HPA% | 總重啟次數 | P0 問題數 |
|----------|--------------|-----------|------------|-----------|
| **Arcade (ForestTeaParty)** | 149Mi | 74% | 0 | 1 |
| **Hash - Limbo** | 141Mi | 70.2% | 3 | 2 |
| **Hash - Hilo** | 99Mi | 38.1% | 0 | 1 |
| **Hash - Mines** | 101Mi | 37.6% | 12 | 1 |
| **Hash - Plinko** | 131Mi | 39.8% | 11 | 1 |
| **Hash - Aviator** | 73Mi | 28.0% | 0 | 0 |
| **Hash - Crash** | 42Mi | 28.5% | 0 | 0 |
| **Hash - Other** | 83Mi | 41.3% | 0 | 0 |

**關鍵洞察**:
1. **Limbo 系列**與 ForestTeaParty 記憶體使用模式相似，都是高壓力遊戲
2. **Crash 系列**記憶體用量最低，配置最保守
3. **Mines 和 Plinko 系列**重啟頻繁，顯示穩定性問題
4. **Aviator 系列**配置過度但穩定

---

## 問題清單與優先級

### P0 問題 (需立即處理) - 5 個

#### P0-1: limbone-prd 記憶體壓力臨界 🔴🔴🔴
- **問題**: HPA 100%, 已重啟 3 次
- **現狀**: 實際 201Mi, Request 200Mi, Limit 1Gi
- **風險**: 隨時可能 OOMKilled
- **建議**:
  ```yaml
  resources:
    requests:
      memory: 300Mi
      cpu: 60m
    limits:
      memory: 500Mi
      cpu: 120m
  ```
- **執行時間**: 立即 (24小時內)

#### P0-2: limbo-prd 記憶體壓力高 🔴🔴
- **問題**: HPA 94%
- **現狀**: 實際 189Mi, Request 200Mi, Limit 1Gi
- **風險**: 接近臨界點
- **建議**: 同 limbone-prd 配置
- **執行時間**: 立即 (24小時內)

#### P0-3: plinkocl-prd 配置嚴重異常 🔴🔴
- **問題**: Request 1.8Ti, Limit 2.8Ti (應為配置錯誤)
- **現狀**: 實際僅 224Mi
- **風險**: 浪費集群資源，阻塞其他 Pod 調度
- **建議**:
  ```yaml
  resources:
    requests:
      memory: 400Mi
      cpu: 120m
    limits:
      memory: 600Mi
      cpu: 200m
  ```
- **執行時間**: 立即 (24小時內)

#### P0-4: minesne-prd 配置異常 + 頻繁重啟 🔴
- **問題**: Limit 1.3Ti (配置錯誤), 已重啟 4 次
- **現狀**: 實際 122Mi, Request 900Mi
- **風險**: 資源浪費 + 穩定性問題
- **建議**:
  ```yaml
  resources:
    requests:
      memory: 200Mi
      cpu: 60m
    limits:
      memory: 300Mi
      cpu: 120m
  ```
- **執行時間**: 立即 (24小時內)

#### P0-5: luckyhilo-prd 配置異常 🔴
- **問題**: Limit 1.2Ti (配置錯誤)
- **現狀**: 實際 205Mi, Request 800Mi
- **風險**: 資源浪費
- **建議**:
  ```yaml
  resources:
    requests:
      memory: 400Mi
      cpu: 150m
    limits:
      memory: 600Mi
      cpu: 280m
  ```
- **執行時間**: 立即 (24小時內)

---

### P1 問題 (需盡快處理) - 6 個

#### P1-1: minesca-prd 頻繁重啟
- **問題**: 已重啟 3 次
- **現狀**: 實際 160Mi, Request 1Gi (過度配置)
- **建議**: 調整配置並調查重啟原因
  ```yaml
  resources:
    requests:
      memory: 300Mi
      cpu: 100m
    limits:
      memory: 500Mi
      cpu: 160m
  ```
- **執行時間**: 1 週內

#### P1-2: plinko-prd 頻繁重啟
- **問題**: 已重啟 4 次
- **建議**: 調查應用程式日誌，檢查 liveness probe 配置
- **執行時間**: 1 週內

#### P1-3: plinkone-prd 頻繁重啟
- **問題**: 已重啟 4 次
- **建議**: 同 plinko-prd
- **執行時間**: 1 週內

#### P1-4: plinkogr-prd 頻繁重啟
- **問題**: 已重啟 3 次
- **建議**: 同 plinko-prd
- **執行時間**: 1 週內

#### P1-5: minescl-prd 重啟
- **問題**: 已重啟 2 次
- **建議**: 監控並調查
- **執行時間**: 2 週內

#### P1-6: minesgr-prd 重啟
- **問題**: 已重啟 2 次
- **建議**: 監控並調查
- **執行時間**: 2 週內

---

### P2 問題 (可逐步優化) - 11 個

所有 P2 問題都是**資源使用率過低** (實際用量 < 30% Request)

**建議**: 統一降低 Request 配置，回收浪費的資源

| 服務 | 當前 Request | 實際用量 | 建議 Request | 節省資源 |
|------|--------------|----------|--------------|----------|
| crashgr | 400Mi | 42Mi | 80Mi | 320Mi |
| aviator | 600Mi | 75Mi | 150Mi | 450Mi |
| aviator2xin | 200Mi | 38Mi | 100Mi | 100Mi |
| minesca | 1024Mi | 160Mi | 300Mi | 724Mi |
| minesne | 900Mi | 122Mi | 200Mi | 700Mi |
| hilogr | 200Mi | 50Mi | 100Mi | 100Mi |
| luckyhilo | 800Mi | 205Mi | 400Mi | 400Mi |
| multihilo | 200Mi | 44Mi | 100Mi | 100Mi |
| limbogr | 200Mi | 44Mi | 100Mi | 100Mi |
| plinkocl | 1887437Mi | 224Mi | 400Mi | 1887037Mi |
| wheel | 200Mi | 53Mi | 100Mi | 100Mi |

**總計可回收**: ~1,891,031 Mi (約 1.8 Ti)

---

## 配置標準化建議

### 建議的標準配置模板

#### 小型遊戲 (Crash, Wheel, Dice)
```yaml
resources:
  requests:
    memory: 100Mi
    cpu: 40m
  limits:
    memory: 200Mi
    cpu: 80m
```

#### 中型遊戲 (Mines, Hilo, Plinko)
```yaml
resources:
  requests:
    memory: 200Mi
    cpu: 60m
  limits:
    memory: 400Mi
    cpu: 120m
```

#### 大型遊戲 (Aviator, Limbo, 特殊變體)
```yaml
resources:
  requests:
    memory: 400Mi
    cpu: 100m
  limits:
    memory: 600Mi
    cpu: 150m
```

#### 超大型遊戲 (高流量變體)
```yaml
resources:
  requests:
    memory: 600Mi
    cpu: 150m
  limits:
    memory: 900Mi
    cpu: 200m
```

---

## 執行計劃

### 第一階段: 緊急修復 (24-48 小時內)

1. ✅ 修正配置異常服務 (P0-3, P0-4, P0-5)
   - plinkocl-prd
   - minesne-prd
   - luckyhilo-prd

2. ✅ 增加高壓力服務資源 (P0-1, P0-2)
   - limbone-prd
   - limbo-prd

3. ✅ 驗證修復效果
   - 監控 HPA 使用率
   - 檢查是否有新重啟

### 第二階段: 穩定性修復 (1-2 週內)

1. 調查頻繁重啟的服務
   - Plinko 系列 (plinko, plinkone, plinkogr)
   - Mines 系列 (minesca, minescl, minesgr)

2. 調整過度配置的服務
   - 開始降低 P2 問題中的 Request 配置
   - 每週處理 3-4 個服務

### 第三階段: 標準化與優化 (1 個月內)

1. 制定並實施標準配置模板
2. 統一同系列遊戲的配置
3. 建立配置變更流程
4. 設置資源使用監控告警

---

## 監控建議

### Grafana Dashboard 應包含

1. **Hash Games 總覽面板**
   - 所有 Hash Games 的記憶體使用趨勢
   - HPA 使用率熱圖
   - 重啟次數統計

2. **系列對比面板**
   - 按系列分組的資源使用對比
   - 配置一致性檢查

3. **異常檢測面板**
   - HPA > 80% 的服務列表
   - 24小時內重啟的服務
   - 配置異常的服務

### Prometheus Alert Rules

```yaml
# 記憶體壓力告警
- alert: HashGameHighMemoryPressure
  expr: |
    (container_memory_working_set_bytes{namespace=~".*-prd",pod=~"(crash|aviator|mines|hilo|limbo|plinko|dice|keno|wheel)-.*"}
    / on(namespace,pod)
    kube_pod_container_resource_limits{resource="memory"}) > 0.8
  for: 10m
  labels:
    severity: critical
  annotations:
    summary: "Hash game {{ $labels.pod }} high memory pressure"

# 頻繁重啟告警
- alert: HashGameFrequentRestarts
  expr: |
    rate(kube_pod_container_status_restarts_total{namespace=~".*-prd",pod=~"(crash|aviator|mines|hilo|limbo|plinko|dice|keno|wheel)-.*"}[1h]) > 0
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Hash game {{ $labels.pod }} restarting frequently"

# 配置異常檢測
- alert: HashGameAbnormalConfiguration
  expr: |
    kube_pod_container_resource_requests{namespace=~".*-prd",pod=~"(crash|aviator|mines|hilo|limbo|plinko|dice|keno|wheel)-.*",resource="memory"} > 1e+12
  labels:
    severity: critical
  annotations:
    summary: "Hash game {{ $labels.pod }} has abnormal memory configuration"
```

---

## 結論

### 關鍵發現總結

1. **🔴🔴 記憶體超限**: 1 個服務超過 Request
   - **luckydropcoc2-prd: 使用 327Mi / Request 200Mi (164%)** - 最嚴重問題

2. **嚴重配置錯誤**: 3 個服務有 TB 級別的配置錯誤
   - plinkocl-prd: 2.8Ti
   - luckyhilo-prd: 1.2Ti
   - minesne-prd: 1.3Ti

3. **記憶體壓力臨界**: Limbo 系列面臨嚴重壓力
   - limbone-prd: HPA 100%, 已重啟 3 次
   - limbo-prd: HPA 94%

4. **穩定性問題**: Mines 和 Plinko 系列頻繁重啟
   - Mines: 12 次重啟
   - Plinko: 11 次重啟

5. **資源浪費**: 大量過度配置
   - 可回收約 1.8Ti Request 資源（配置錯誤修正）
   - 15 個服務使用率 < 30%
   - Other 系列可節省 ~300Mi Request

6. **配置不一致**: 同系列服務配置差異大
   - Crash: 1 個異常 (crashgr)
   - Aviator: 1 個異常 (aviator)
   - Hilo: 1 個異常 (luckyhilo)

7. **新增 LuckyDrop 系列**: 高使用率系列
   - 平均 HPA 84%（第二高）
   - 1 個 P0 問題（luckydropcoc2）

### 預期改善

執行修復後預期效果:

| 指標 | 修復前 | 修復後 | 改善 |
|------|--------|--------|------|
| 總服務數 | 41 | 41 | - |
| P0 問題數 | **6** | 0 | -100% |
| HPA > 80% 服務數 | 3 (limbone, limbo, luckydropcoc2) | 0 | -100% |
| 超過 Request 服務數 | **1** (luckydropcoc2) | 0 | -100% |
| 配置異常服務數 | 3 | 0 | -100% |
| 浪費的 Request | 1.8Ti | <200Mi | -99.9% |
| 重啟次數/週 | ~26 | <10 | -60% |

### 長期建議

1. **建立配置審查流程**
   - 所有配置變更需經過 review
   - 使用 GitOps 管理配置

2. **自動化監控**
   - 部署 Grafana Dashboard
   - 設置 Prometheus Alert Rules
   - 建立 Slack 告警通道

3. **定期資源審計**
   - 每月檢查資源使用情況
   - 調整過度配置的服務

4. **標準化配置模板**
   - 使用 Helm Chart 統一管理
   - 按遊戲規模分類配置

---

**報告產生時間**: 2025-11-07
**下次審查時間**: 2025-11-14 (修復後 1 週)
**負責人**: DevOps Team
