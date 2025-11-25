# 遺漏服務補充分析報告

**分析日期**: 2025-11-08
**分析範圍**: 13 個之前遺漏的遊戲服務
**分析師**: Claude Code

---

## 🎯 執行摘要

### 新發現的問題

| 優先級 | 服務 | 問題 | 類型 |
|-------|------|------|------|
| 🔴 **P0** | **luckydropcoc2** | 使用 327Mi / Request 200Mi (**164%**) | Hash |
| 🔴 **P0** | **lostruins** | 使用 129Mi / Request 140Mi (**92%**) | Bingo |
| ⚠️ P1 | chilifiesta | 沒有部署（namespace 空的）| Arcade |

### 統計摘要

| 類別 | 遺漏數 | 新增 P0 | 新增 P1 | 總用量 | 總 Request |
|------|--------|---------|---------|--------|-----------|
| Hash Games | 7 | 1 | 0 | 851 Mi | 1,400 Mi |
| Bingo Games | 3 | 1 | 0 | 391 Mi | 520 Mi |
| Arcade Games | 3 | 0 | 1 | 472 Mi | 1,000 Mi |
| **總計** | **13** | **2** | **1** | **1,714 Mi** | **2,920 Mi** |

---

## 🎮 Hash Games 遺漏服務（7 個）

### 完整數據表

| 服務 | 實際用量 | Request | Limit | 使用率 | HPA% | 狀態 |
|------|----------|---------|-------|--------|------|------|
| **luckydropcoc2** | **327Mi** | **200Mi** | 1Gi | **164%** 🔴 | **164%/80%** | 🔴 **超過 Request** |
| luckydropgx | 117Mi | 200Mi | 1Gi | 59% | 59%/80% | ✅ 正常 |
| luckydropcoc | 116Mi | 200Mi | 1Gi | 58% | 58%/80% | ✅ 正常 |
| luckydropoly | 107Mi | 200Mi | 1Gi | 54% | 54%/80% | ✅ 正常 |
| dragontower | 80Mi | 200Mi | 1Gi | 40% | 40%/80% | ✅ 正常 |
| videopoker | 59Mi | 200Mi | 1Gi | 30% | 30%/80% | 📉 過度配置 |
| diamonds | 45Mi | 200Mi | 1Gi | 23% | 23%/80% | 📉 過度配置 |

### LuckyDrop 系列分析（4 個）

| 服務 | 實際用量 | Request | 使用率 | 評估 |
|------|----------|---------|--------|------|
| luckydropcoc2 | 327Mi | 200Mi | **164%** 🔴 | 🔴 緊急升級 |
| luckydropgx | 117Mi | 200Mi | 59% | ✅ 良好 |
| luckydropcoc | 116Mi | 200Mi | 58% | ✅ 良好 |
| luckydropoly | 107Mi | 200Mi | 54% | ✅ 良好 |
| **平均** | **167Mi** | **200Mi** | **84%** | ⚠️ 高使用率 |

**系列總結**：
- 總實際用量: 667 Mi
- 總 Request: 800 Mi
- 平均 HPA: 84% (接近 80% 觸發值)
- **問題**: luckydropcoc2 已超過 Request 64%
- **建議**: 立即升級 luckydropcoc2 的 Request

### Other 系列新增（3 個）

| 服務 | 實際用量 | Request | 使用率 |
|------|----------|---------|--------|
| dragontower | 80Mi | 200Mi | 40% |
| videopoker | 59Mi | 200Mi | 30% |
| diamonds | 45Mi | 200Mi | 23% |

**觀察**: 這 3 個服務使用率都偏低（23-40%），可考慮降低 Request。

---

## 🎰 Bingo Games 遺漏服務（3 個）

### 完整數據表

| 服務 | 實際用量 | Request | Limit | 使用率 | HPA% | 狀態 |
|------|----------|---------|-------|--------|------|------|
| **lostruins** | **129Mi** | **140Mi** | 230Mi | **92%** 🔴 | **92%/80%** | 🔴 高壓 |
| steampunk | 131Mi | 200Mi | 300Mi | 66% | 66%/80% | ✅ 正常 |
| steampunk2 | 131Mi | 180Mi | 300Mi | 73% | 73%/80% | ✅ 正常 |

### 詳細分析

#### lostruins - P0 問題 🔴

**當前狀態**：
- 使用: 129Mi
- Request: 140Mi
- 使用率: **92%** (超過 80% HPA 觸發值)
- 距離上限: 僅剩 **11Mi** (8%)

**風險**：
- 任何流量增加 > 8% 即會觸發 OOM
- 與 cavebingo (87%) 和 caribbeanbingo (85%) 同等高風險
- 屬於 Bingo 遊戲中使用率最高的服務之一

**建議修復**：
```yaml
resources:
  requests:
    memory: "200Mi"  # 從 140Mi 提升 (+43%)
  limits:
    memory: "350Mi"  # 從 230Mi 提升 (+52%)
```

#### steampunk / steampunk2

**共同特徵**：
- 記憶體使用完全相同: 131Mi
- 配置略有不同（Request: 200Mi vs 180Mi）
- 都在安全範圍內（66-73%）

**觀察**: 可能是姐妹服務或不同版本，運行狀況健康。

---

## 🎪 Arcade Games 遺漏服務（3 個）

### 完整數據表

| 服務 | 實際用量 | Request | Limit | 使用率 | HPA% | 狀態 |
|------|----------|---------|-------|--------|------|------|
| goldenclover | 241Mi | 500Mi | 1Gi | 48% | 48%/80% | ✅ 正常 |
| wilddiggr | 231Mi | 500Mi | 1Gi | 46% | 46%/80% | ✅ 正常 |
| **chilifiesta** | **0Mi** | **-** | **-** | **-** | **-** | 🔴 **未部署** |

### 詳細分析

#### goldenclover / wilddiggr

**共同特徵**：
- 配置完全相同: 500Mi Request / 1Gi Limit
- 使用量非常接近: 241Mi vs 231Mi (僅差 10Mi)
- 使用率健康: 46-48%

**對比 ForestTeaParty**：
- ForestTeaParty: 181Mi 用量 / 700Mi Request (26%)
- goldenclover: 241Mi 用量 / 500Mi Request (48%)
- wilddiggr: 231Mi 用量 / 500Mi Request (46%)

**觀察**: 這兩個服務的記憶體使用比 ForestTeaParty 高 30-33%，但配置更合理（使用率接近 50%）。

#### chilifiesta - P1 問題 🔴

**狀態**:
- Namespace 存在但**沒有任何 Pod 運行**
- 沒有 StatefulSet 或 Deployment

**可能原因**：
1. 服務尚未部署
2. 服務已下線
3. 部署失敗

**建議**:
- 與團隊確認此服務是否應該運行
- 如已廢棄，應從 kustomize 配置中移除
- 如需部署，應檢查部署失敗原因

---

## 🚨 新增的 P0 問題

### 1. luckydropcoc2 超過 Request 🔴🔴

**嚴重性**: 極高

**問題**：
- 當前使用 **327Mi**
- Request 配置僅 **200Mi**
- 超過 Request **127Mi** (64%)
- HPA 已達 **164%**

**為何未 OOM**：
- Limit 為 1Gi，實際用量遠低於 Limit
- 但已超過 Request，可能在資源緊張時被驅逐

**立即修復**：
```yaml
# luckydropcoc2-prd
resources:
  requests:
    memory: "400Mi"  # 從 200Mi 翻倍 (+100%)
  limits:
    memory: "1Gi"    # 保持不變
```

**優先級**: 🔴 **P0 - 24 小時內**

---

### 2. lostruins 接近記憶體上限 🔴

**嚴重性**: 高

**問題**：
- 當前使用 **129Mi**
- Request **140Mi**
- 使用率 **92%** (超過 80% HPA 觸發值)
- 距離驅逐僅剩 **11Mi** (8%)

**風險**：
- 與 cavebingo (87%) 和 caribbeanbingo (85%) 同等級風險
- 任何連線增加都可能觸發 OOM

**立即修復**：
```yaml
# lostruins-prd
resources:
  requests:
    memory: "200Mi"  # 從 140Mi 提升 (+43%)
  limits:
    memory: "350Mi"  # 從 230Mi 提升 (+52%)
```

**優先級**: 🔴 **P0 - 24-48 小時內**

---

## 📊 更新後的總體統計

### 所有服務統計（含遺漏服務）

| 類別 | 原分析 | 新增 | 總計 | P0 問題 | P1 問題 |
|------|--------|------|------|---------|---------|
| Hash Games | 34 | 7 | **41** | 5 → **6** | 6 |
| Bingo Games | 10 | 3 | **13** | 2 → **3** | 1 |
| Arcade Games | 2 | 3 | **5** | 0 | 0 → **1** |
| Gate Services | 2 | 0 | **2** | 1 | 1 |
| API Services | 10 | 0 | **10** | 4 | 2 |
| **總計** | **58** | **13** | **71** | **7** → **14** | **10** → **11** |

### P0 問題更新清單（14 個）

#### Hash Games（6 個）
1. plinkocl: TB 級配置錯誤
2. minesne: TB 級配置錯誤
3. luckyhilo: TB 級配置錯誤
4. limbone: 記憶體壓力 100%
5. limbo: 記憶體壓力 94%
6. **luckydropcoc2**: 超過 Request 164% ⚡ **新增**

#### Bingo Games（3 個）
1. cavebingo: 記憶體壓力 87%
2. caribbeanbingo: 記憶體壓力 85%
3. **lostruins**: 記憶體壓力 92% ⚡ **新增**

#### API Services（4 個）
1. domain-serviceapi: 超限 202%
2. eventapi: 超限 218%
3. exmgmtapi: 超限 200%
4. loyaltyapi: 嚴重資源浪費

#### Gate Services（1 個）
1. hash-gate: 日誌爆炸 + 記憶體壓力

---

## 💰 資源優化更新

### 新增節省潛力

| 優化項目 | Request 變化 | Limit 變化 | 數量 |
|---------|------------|-----------|------|
| luckydropcoc2 升級 | +200Mi | 0 | 1 |
| lostruins 升級 | +60Mi | +120Mi | 1 |
| diamonds/videopoker 降級 | -80Mi | -400Mi | 2 |
| **原有優化** | -6,643Mi | -11.9Gi | 15 |
| **新總計** | **-6,463Mi** | **-11.7Gi** | **19** |

### 更新後可節省資源

- **Request**: 約 **6.3 Gi** (扣除新增升級後)
- **Limit**: 約 **11.7 Gi**
- **影響服務**: 19 個

---

## 🎯 立即行動建議

### 今天（11/8）新增任務

**上午**（在原計劃前執行）：
```bash
# 1. 修復 luckydropcoc2（最緊急）
kubectl edit statefulset luckydropcoc2-prd -n luckydropcoc2-prd
# Request: 200Mi → 400Mi

# 2. 修復 lostruins
kubectl edit statefulset lostruins-prd -n lostruins-prd
# Request: 140Mi → 200Mi
# Limit: 230Mi → 350Mi

# 3. 檢查 chilifiesta 狀態
kubectl describe namespace chilifiesta-prd
# 確認是否需要部署或移除
```

**然後執行原計劃**：
- 應用 hash_games_fix_p0_issues.yaml
- 調查記憶體計量異常
- 其他 P0 問題修復

---

## 📝 後續分析任務

### 需要更新的文件

1. ✅ **MISSING_SERVICES_ANALYSIS.md** - 本文件（已完成）
2. ⭕ **HASH_GAMES_RESOURCE_ANALYSIS.md** - 需新增 7 個服務
3. ⭕ **BINGO_GAMES_MEMORY_ANALYSIS.md** - 需新增 3 個服務
4. ⭕ **MultiBoomers vs All Arcade Games 對比** - 需新增 3 個服務對比
5. ⭕ **ALL_SERVICES_MEMORY_ANALYSIS_OVERVIEW.md** - 需更新所有統計
6. ⭕ **hash_games_fix_p0_issues.yaml** - 需新增 luckydropcoc2 修復

---

**報告生成**: 2025-11-08 00:45 UTC+8
**分析師**: Claude Code
**狀態**: 補充分析完成，等待整合到主報告
