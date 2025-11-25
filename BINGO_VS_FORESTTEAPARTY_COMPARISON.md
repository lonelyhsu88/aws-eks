# Bingo Games vs ForestTeaParty 記憶體配置對比分析

**分析日期**: 2025-11-07
**對比基準**: 運行時長約 4 天 7 小時

---

## 執行摘要

### 關鍵發現

1. **ForestTeaParty 是保守配置的典範**
   - 使用率 29.5%，有充足緩衝空間
   - 配置統一，易於管理

2. **Bingo Games 存在嚴重配置不一致問題**
   - 配置範圍從 140Mi 到 1536Mi（相差 11 倍）
   - 2 個服務使用率超過 80% HPA 閾值
   - 1 個服務嚴重過度配置（使用率僅 25%）

3. **資源利用效率對比**
   - ForestTeaParty: 29.5% 使用率 → 適度保守
   - Bingo Games: 25-87% 使用率 → 配置混亂

---

## 詳細對比表格

### 基礎指標對比

| 指標 | ForestTeaParty | Bingo (最低) | Bingo (最高) | Bingo (平均) | Bingo (中位數) |
|------|---------------|-------------|-------------|-------------|--------------|
| **記憶體使用** | 177 Mi | 108 Mi (bingobells) | 391 Mi (bonusbingo) | 156 Mi | 133 Mi |
| **Request** | 600 Mi | 140 Mi (cavebingo) | 1536 Mi (bonusbingo) | 512 Mi | 400 Mi |
| **Limit** | 1024 Mi | 220 Mi (cavebingo) | 3072 Mi (bonusbingo) | 946 Mi | 700 Mi |
| **Request 使用率** | 29.5% | 25% (bonusbingo) | 87% (cavebingo) | 44% | 33% |
| **Limit 使用率** | 17.3% | 13% (bonusbingo) | 55% (cavebingo) | 24% | 19% |
| **HPA 狀態** | 29%/80% ✅ | 25%/80% ✅ | 87%/80% 🚨 | 44%/80% | 33%/80% |
| **運行時長** | 112h | 112h | 112h | 112h | 112h |
| **重啟次數** | 0 | 0 | 0 | 0 | 0 |
| **資料庫連線** | 40 (read) + 40 (write) | 40 + 40 | 40 + 40 | 40 + 40 | 40 + 40 |

---

## 服務分類對比

### 按配置策略分類

#### 保守配置（使用率 < 35%）

| 服務 | 記憶體使用 | Request | 使用率 | 評估 |
|------|-----------|---------|--------|------|
| **ForestTeaParty** | 177 Mi | 600 Mi | 29.5% | ✅ 保守但合理 |
| bonusbingo | 391 Mi | 1536 Mi | 25% | 🚨 過度保守（浪費資源） |
| bingobells | 108 Mi | 400 Mi | 27% | ⚠️ 過度配置 |
| magicbingo | 144 Mi | 500 Mi | 28% | ⚠️ 過度配置 |
| egghuntbingo | 145 Mi | 500 Mi | 29% | ⚠️ 過度配置 |
| bingbingbingo | 121 Mi | 400 Mi | 30% | ⚠️ 過度配置 |
| maplebingo | 132 Mi | 400 Mi | 33% | ⚠️ 過度配置 |
| arcadebingo | 137 Mi | 400 Mi | 34% | ✅ 合理 |

#### 理想配置（使用率 50-70%）

| 服務 | 記憶體使用 | Request | 使用率 | 評估 |
|------|-----------|---------|--------|------|
| odinbingo | 133 Mi | 200 Mi | 66% | ✅ 理想範圍 |

#### 激進配置（使用率 > 80%）

| 服務 | 記憶體使用 | Request | 使用率 | 評估 |
|------|-----------|---------|--------|------|
| caribbeanbingo | 128 Mi | 150 Mi | 85% | 🚨 過於激進 |
| cavebingo | 122 Mi | 140 Mi | 87% | 🚨 風險最高 |

---

## 配置一致性分析

### ForestTeaParty（單一服務）

```
記憶體配置: [177 Mi] → Request: [600 Mi] → Limit: [1024 Mi]
標準差: 0（單一服務）
配置一致性: ✅ 完美（N/A for single service）
```

### Bingo Games（10 服務）

```
記憶體使用分佈: 108Mi ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ 391Mi
                    │        │        │        │        │
                   108      150      200      300      391

Request 分佈:      140Mi ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ 1536Mi
                    │        │        │         │         │
                   140      250      400       750      1536

配置範圍:
- 記憶體使用: 108-391 Mi (變異係數: 3.6x)
- Request: 140-1536 Mi (變異係數: 11x) 🚨
- Limit: 220-3072 Mi (變異係數: 14x) 🚨

配置一致性: ❌ 極差
```

**結論**: Bingo Games 的 request 和 limit 配置缺乏標準化，變異係數高達 11-14 倍。

---

## 資源效率對比

### 單位記憶體成本（Request / 實際使用）

| 服務 | 實際使用 | Request | 成本倍率 | 效率評級 |
|------|---------|---------|---------|---------|
| **ForestTeaParty** | 177 Mi | 600 Mi | **3.4x** | ✅ 合理 buffer |
| cavebingo | 122 Mi | 140 Mi | 1.15x | ⚠️ 過於緊湊 |
| caribbeanbingo | 128 Mi | 150 Mi | 1.17x | ⚠️ 過於緊湊 |
| odinbingo | 133 Mi | 200 Mi | 1.50x | ✅ 理想 |
| arcadebingo | 137 Mi | 400 Mi | 2.92x | ✅ 合理 |
| maplebingo | 132 Mi | 400 Mi | 3.03x | ✅ 合理 |
| bingbingbingo | 121 Mi | 400 Mi | 3.31x | ✅ 合理 |
| egghuntbingo | 145 Mi | 500 Mi | 3.45x | ✅ 合理 |
| magicbingo | 144 Mi | 500 Mi | 3.47x | ✅ 合理 |
| bingobells | 108 Mi | 400 Mi | 3.70x | ⚠️ 略高 |
| bonusbingo | 391 Mi | 1536 Mi | **3.93x** | 🚨 浪費嚴重 |

**理想成本倍率**: 1.5x - 2.5x（提供 50-150% buffer）
**ForestTeaParty**: 3.4x（保守，但單一服務可接受）
**Bingo 問題**:
- 2 個服務 < 1.2x → 過於緊湊，風險高
- 1 個服務 > 3.9x → 浪費資源

---

## HPA 觸發風險分析

### HPA 閾值: 80%

**ForestTeaParty**: 29%/80% → 距離閾值 **51 個百分點** ✅
**Bingo Games**:

| 服務 | HPA 狀態 | 距離閾值 | 風險等級 |
|------|---------|---------|---------|
| cavebingo | 87%/80% | **+7 點** | 🚨 已超過 |
| caribbeanbingo | 85%/80% | **+5 點** | 🚨 已超過 |
| odinbingo | 66%/80% | -14 點 | ✅ 安全 |
| arcadebingo | 34%/80% | -46 點 | ✅ 安全 |
| maplebingo | 33%/80% | -47 點 | ✅ 安全 |
| bingbingbingo | 30%/80% | -50 點 | ✅ 安全 |
| egghuntbingo | 29%/80% | -51 點 | ✅ 安全 |
| magicbingo | 28%/80% | -52 點 | ✅ 安全 |
| bingobells | 27%/80% | -53 點 | ✅ 安全 |
| bonusbingo | 25%/80% | -55 點 | ✅ 安全 |

**ForestTeaParty**: 100% 服務安全
**Bingo Games**: 80% 服務安全，20% 服務超過閾值（2/10）

---

## 如果所有服務採用 ForestTeaParty 配置策略

### 假設情境：統一使用 30% 使用率目標

| 服務 | 當前使用 | 建議 Request | 當前 Request | 差異 |
|------|---------|-------------|-------------|-----|
| cavebingo | 122 Mi | 407 Mi | 140 Mi | **+267 Mi** |
| caribbeanbingo | 128 Mi | 427 Mi | 150 Mi | **+277 Mi** |
| odinbingo | 133 Mi | 443 Mi | 200 Mi | **+243 Mi** |
| arcadebingo | 137 Mi | 457 Mi | 400 Mi | **+57 Mi** |
| maplebingo | 132 Mi | 440 Mi | 400 Mi | **+40 Mi** |
| bingbingbingo | 121 Mi | 403 Mi | 400 Mi | **+3 Mi** |
| egghuntbingo | 145 Mi | 483 Mi | 500 Mi | **-17 Mi** |
| magicbingo | 144 Mi | 480 Mi | 500 Mi | **-20 Mi** |
| bingobells | 108 Mi | 360 Mi | 400 Mi | **-40 Mi** |
| bonusbingo | 391 Mi | 1303 Mi | 1536 Mi | **-233 Mi** |

**總 Request 變化**: +577 Mi（增加 11%）
**標準化效果**: 配置統一，易於管理

**結論**: ForestTeaParty 的保守策略應用到 Bingo Games 會需要更多資源，但可顯著降低風險。

---

## 推薦的標準化配置方案

### 方案 A: 保守策略（類似 ForestTeaParty）

**目標使用率**: 30-40%
**適用場景**: 高可用性要求、峰值流量不可預測

| 記憶體使用範圍 | 建議 Request | 建議 Limit |
|--------------|-------------|-----------|
| 100-150 Mi | 400 Mi | 700 Mi |
| 150-200 Mi | 500 Mi | 800 Mi |
| 200-300 Mi | 600 Mi | 1000 Mi |
| 300-500 Mi | 1000 Mi | 1500 Mi |

### 方案 B: 平衡策略（推薦）

**目標使用率**: 50-70%
**適用場景**: 一般業務場景、可接受短暫壓力

| 記憶體使用範圍 | 建議 Request | 建議 Limit |
|--------------|-------------|-----------|
| 100-150 Mi | 250 Mi | 500 Mi |
| 150-200 Mi | 300 Mi | 600 Mi |
| 200-300 Mi | 400 Mi | 700 Mi |
| 300-500 Mi | 650 Mi | 1100 Mi |

### 方案 C: 激進策略（不推薦）

**目標使用率**: 70-80%
**適用場景**: 資源極度受限、可承受高風險

| 記憶體使用範圍 | 建議 Request | 建議 Limit |
|--------------|-------------|-----------|
| 100-150 Mi | 180 Mi | 350 Mi |
| 150-200 Mi | 230 Mi | 450 Mi |
| 200-300 Mi | 300 Mi | 550 Mi |
| 300-500 Mi | 500 Mi | 900 Mi |

---

## Bingo Games 應用推薦方案 B（平衡策略）

| 服務 | 當前使用 | 當前 Request | 建議 Request | 建議 Limit | 變化 |
|------|---------|-------------|-------------|-----------|------|
| cavebingo | 122 Mi | 140 Mi | **200 Mi** | **350 Mi** | +60 Mi |
| caribbeanbingo | 128 Mi | 150 Mi | **220 Mi** | **400 Mi** | +70 Mi |
| odinbingo | 133 Mi | 200 Mi | **220 Mi** | **400 Mi** | +20 Mi |
| arcadebingo | 137 Mi | 400 Mi | **250 Mi** | **500 Mi** | -150 Mi |
| maplebingo | 132 Mi | 400 Mi | **250 Mi** | **500 Mi** | -150 Mi |
| bingbingbingo | 121 Mi | 400 Mi | **250 Mi** | **500 Mi** | -150 Mi |
| egghuntbingo | 145 Mi | 500 Mi | **250 Mi** | **500 Mi** | -250 Mi |
| magicbingo | 144 Mi | 500 Mi | **250 Mi** | **500 Mi** | -250 Mi |
| bingobells | 108 Mi | 400 Mi | **250 Mi** | **500 Mi** | -150 Mi |
| bonusbingo | 391 Mi | 1536 Mi | **650 Mi** | **1100 Mi** | -886 Mi |

**總 Request 變化**: -1,846 Mi（節省 36%）
**預期使用率**: 50-60% (理想範圍)
**配置一致性**: ✅ 高度統一（只有 bonusbingo 例外）

---

## 關鍵洞察與建議

### 1. ForestTeaParty 的經驗

✅ **值得學習**:
- 統一的配置策略
- 適度保守的資源預留
- 穩定的長期運行

⚠️ **不需照搬**:
- 單一服務與多服務場景不同
- 29% 使用率對多服務來說過於保守
- 建議目標使用率提升至 50-70%

### 2. Bingo Games 的問題

🚨 **立即修復**:
- cavebingo, caribbeanbingo: request 不足
- bonusbingo: 嚴重過度配置

📋 **長期改善**:
- 建立標準化配置框架
- 統一 request 配置（除非有明確差異化需求）
- 定期複查和調整

### 3. 配置哲學

**ForestTeaParty**: "寧可浪費，不可缺乏"
**建議**: "合理預留，持續監控"

**理想目標**:
- Request 使用率: 50-70%
- Limit 使用率: 30-50%
- HPA 觸發距離: > 15 個百分點

---

## 執行路線圖

### Phase 1: 緊急修復（1-2 天）
- 修復 cavebingo, caribbeanbingo 的 request 不足問題
- 目標: 消除超過 HPA 閾值的服務

### Phase 2: 資源回收（3-7 天）
- 調整 bonusbingo 的過度配置
- 目標: 釋放 ~900 Mi request 資源

### Phase 3: 標準化（2-4 週）
- 統一其他 8 個服務的配置
- 採用方案 B（平衡策略）
- 目標: 建立可維護的配置標準

### Phase 4: 持續優化（ongoing）
- 每週監控記憶體使用趨勢
- 季度複查配置合理性
- 根據業務變化調整標準

---

**報告完成**: 2025-11-07
**參考報告**:
- `/Users/lonelyhsu/gemini/claude-project/aws-eks/BINGO_GAMES_MEMORY_ANALYSIS.md`
- `/Users/lonelyhsu/gemini/claude-project/aws-eks/FORESTTEAPARTY_DEEP_DIVE_ANALYSIS.md`
