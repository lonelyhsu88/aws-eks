# 分析深度差距與後續行動計劃

**建立日期**: 2025-11-08
**狀態**: 🔴 待處理
**標準**: ForestTeaParty 深度技術剖析標準

---

## ⚠️ 核心問題

**承諾**: 所有服務比照 ForestTeaParty 深度分析標準
**現實**: 新發現的 13 個服務僅完成基礎靜態分析

---

## 📊 ForestTeaParty 分析標準（基準）

### 完整深度分析包含

1. **時間序列追蹤**
   - ✅ 42 小時連續監控（11/3 00:00 → 11/7 15:30）
   - ✅ 每個時間點的記憶體使用記錄
   - ✅ 連線數變化趨勢
   - ✅ 重啟事件的前後對比分析

2. **數據建模與驗證**
   - ✅ 建立線性回歸模型：`Memory = 1.1 × Connections + 295Mi`
   - ✅ R² 驗證達 ≈ 1.0（完美擬合）
   - ✅ 殘差分析：40Mi 差距拆解
     - GC overhead: ~15Mi
     - Go runtime: ~10Mi
     - Buffers/Caches: ~15Mi

3. **日誌深度挖掘**
   - ✅ 從壓縮日誌檔（tar.gz）提取歷史數據
   - ✅ 解析連線數 JSON：`"目前桌台連線人數: 186 / 35"`
   - ✅ 關聯 kubectl top 數據
   - ✅ 識別異常模式（記憶體增長 vs 連線下降）

4. **Memory Leak 風險評估**
   - ✅ 多假設分析（3種可能性）
   - ✅ 置信度量化（65-70%）
   - ✅ 證據強度標記（✅✅✅, ✅✅, ✅, ⚠️, ❌, ⭕）
   - ✅ 驗證方案提供

5. **配置演進追蹤**
   - ✅ Pod 重啟根因調查（非 OOM，配置更新）
   - ✅ 資源配置變更歷史
     - Before: Request 300Mi, Limit 600Mi
     - After: Request 700Mi, Limit 1Gi
   - ✅ 變更影響分析

6. **完整技術文檔**
   - ✅ 24 KB Markdown 文件
   - ✅ 包含時間線、數據表、圖表說明
   - ✅ 可執行的驗證指令
   - ✅ 風險矩陣

**總計**: 42 小時數據收集 + 深度分析 = **1 份完整的深度技術剖析報告**

---

## 🔴 當前分析深度差距

### P0 緊急問題（分析深度嚴重不足）

#### 1. luckydropcoc2-prd (Hash Game)

**當前分析**:
- ✅ 靜態數據: 327Mi / 200Mi Request (164%)
- ✅ HPA 狀態: 164%
- ⭕ 基本建議: 升級到 400Mi Request

**缺少的深度分析**:
- ❌ **為何超過 Request 64%？** 根本原因未知
- ❌ **時間序列數據**: 無歷史趨勢
- ❌ **連線數分析**: 未提取日誌數據
- ❌ **Memory Leak 評估**: 無風險評估
- ❌ **與其他 LuckyDrop 對比**:
  - luckydropcoc2: 327Mi (異常)
  - luckydropgx: 117Mi (正常)
  - luckydropcoc: 116Mi (正常)
  - luckydropoly: 107Mi (正常)
  - **為何差異 2.8 倍？** 未調查
- ❌ **配置歷史**: 是否曾經調整過？
- ❌ **流量模式**: 峰值 vs 平均

**影響**: 無法判斷是否為暫時性峰值或持續性問題，修復方案可能不準確

**優先級**: 🔴🔴🔴 **最高**

---

#### 2. lostruins-prd (Bingo Game)

**當前分析**:
- ✅ 靜態數據: 129Mi / 140Mi Request (92%)
- ✅ HPA 狀態: 92%
- ⭕ 基本建議: 升級到 200Mi Request

**缺少的深度分析**:
- ❌ **為何使用率 92%？** 根本原因未知
- ❌ **時間序列數據**: 無 4 天運行歷史
- ❌ **連線數分析**: 未提取 40 connections 的實際使用
- ❌ **與其他 Bingo 對比**:
  - lostruins: 129Mi / 140Mi (92% - 異常)
  - cavebingo: 122Mi / 140Mi (87% - 高)
  - caribbeanbingo: 128Mi / 150Mi (85% - 高)
  - steampunk: 131Mi / 200Mi (66% - 正常)
  - steampunk2: 131Mi / 180Mi (73% - 正常)
  - **為何 steampunk 系列用量相同但配置更高？** 未調查
- ❌ **GameType 特性**: LostRuins 遊戲機制是否特殊？
- ❌ **Memory Leak 風險**: 無評估

**影響**: 可能低估所需資源，修復後仍可能觸發 HPA

**優先級**: 🔴🔴 **極高**

---

### P1/P2 問題（基礎分析已完成）

#### 3-9. 其他 Hash Games (7 個新服務)

| 服務 | 用量 | 當前分析 | 缺少內容 |
|------|------|---------|---------|
| luckydropgx | 117Mi | 靜態數據 | 時間序列、連線數 |
| luckydropcoc | 116Mi | 靜態數據 | 時間序列、連線數 |
| luckydropoly | 107Mi | 靜態數據 | 時間序列、連線數 |
| dragontower | 80Mi | 靜態數據 | 時間序列、GameType 特性 |
| videopoker | 59Mi | 靜態數據 | 時間序列、GameType 特性 |
| diamonds | 45Mi | 靜態數據 | 時間序列、GameType 特性 |

**優先級**: ⚠️ **中**（僅在發現異常時深入）

---

#### 10-11. 其他 Bingo Games (2 個新服務)

| 服務 | 用量 | 當前分析 | 缺少內容 |
|------|------|---------|---------|
| steampunk | 131Mi | 靜態數據 | 與 steampunk2 完全相同用量的原因分析 |
| steampunk2 | 131Mi | 靜態數據 | 版本差異、配置差異原因 |

**特殊觀察**: 兩者記憶體使用**完全相同** (131Mi)，但 Request 不同 (200Mi vs 180Mi)
- 需要深入分析：是否為相同版本？姐妹服務？流量是否相同？

**優先級**: ⚠️ **中低**

---

#### 12-14. Arcade Games (3 個新服務)

| 服務 | 用量 | 當前分析 | 缺少內容 |
|------|------|---------|---------|
| goldenclover | 241Mi | 靜態數據 | 完整深度分析（比照 MultiBoomers 1,666 行標準）|
| wilddiggr | 231Mi | 靜態數據 | 完整深度分析 |
| chilifiesta | 0Mi | 未部署 | 部署狀態調查、歷史記錄 |

**特殊觀察**: goldenclover/wilddiggr 用量接近但比 ForestTeaParty 高 30-33%
- 需要深入分析：GameType 差異？連線數差異？配置策略？

**優先級**: ⚠️ **中低**（chilifiesta 需確認狀態）

---

## 📋 後續行動計劃

### Phase 1: P0 深度分析（24-48 小時內）

#### Task 1.1: luckydropcoc2 深度剖析 🔴🔴🔴

**目標**: 產出比照 ForestTeaParty 標準的完整分析報告

**執行步驟**:
```bash
# 1. 收集時間序列數據（過去 4-7 天）
kubectl top pods -n luckydropcoc2-prd --containers
# 設置定時監控（每 10 分鐘一次，持續 24 小時）

# 2. 提取日誌中的連線數數據
kubectl logs -n luckydropcoc2-prd luckydropcoc2-0 --tail=100000 | \
  grep "連線人數" > luckydropcoc2_connections.log

# 檢查壓縮日誌檔
kubectl exec -n luckydropcoc2-prd luckydropcoc2-0 -- \
  ls -lh /var/log/*.tar.gz

# 3. 檢查重啟歷史
kubectl get events -n luckydropcoc2-prd --sort-by='.lastTimestamp' | \
  grep luckydropcoc2

# 4. 對比同系列其他服務
kubectl top pods -n luckydropgx-prd
kubectl top pods -n luckydropcoc-prd
kubectl top pods -n luckydropoly-prd

# 5. 檢查配置歷史
kubectl get statefulset luckydropcoc2 -n luckydropcoc2-prd -o yaml | \
  grep -A 10 resources:
```

**產出**:
- `LUCKYDROPCOC2_DEEP_DIVE_ANALYSIS.md`（目標 20+ KB）
- 包含時間序列圖表、連線數模型、Memory Leak 評估
- 置信度評估：X% 可能性有 memory leak
- 驗證方案

**預估時間**: 6-8 小時

---

#### Task 1.2: lostruins 深度剖析 🔴🔴

**目標**: 理解為何 HPA 達 92%，與其他 Bingo 的差異

**執行步驟**:
```bash
# 1. 收集 lostruins 時間序列
kubectl top pods -n lostruins-prd --containers

# 2. 對比分析（相似配置的服務）
kubectl top pods -n cavebingo-prd      # 140Mi Request, 87% HPA
kubectl top pods -n caribbeanbingo-prd # 150Mi Request, 85% HPA
kubectl top pods -n steampunk-prd      # 200Mi Request, 66% HPA (相同用量!)
kubectl top pods -n steampunk2-prd     # 180Mi Request, 73% HPA (相同用量!)

# 3. 提取連線數
kubectl logs -n lostruins-prd lostruins-0 --tail=100000 | \
  grep "連線人數"

# 4. GameType 特性調查
kubectl describe statefulset lostruins -n lostruins-prd
kubectl get configmap -n lostruins-prd
```

**關鍵問題**:
- 為何 lostruins (129Mi/140Mi) 使用率比 steampunk (131Mi/200Mi) 高？
- steampunk 和 steampunk2 用量完全相同 (131Mi)，為何配置不同？
- LostRuins 遊戲機制是否需要更多記憶體？

**產出**:
- `LOSTRUINS_VS_BINGO_COMPARISON.md`（目標 15+ KB）
- Bingo Games 記憶體使用模式分析
- 配置建議更新

**預估時間**: 4-6 小時

---

### Phase 2: 補充分析（1-2 週內）

#### Task 2.1: LuckyDrop 系列完整分析

**4 個服務對比**:
- luckydropcoc2: 327Mi (異常)
- luckydropgx: 117Mi
- luckydropcoc: 116Mi
- luckydropoly: 107Mi

**產出**: `LUCKYDROP_SERIES_COMPLETE_ANALYSIS.md`

---

#### Task 2.2: Arcade Games 擴展分析

**對比分析**:
- ForestTeaParty: 181Mi
- MultiBoomers: 49Mi
- goldenclover: 241Mi
- wilddiggr: 231Mi

**產出**: `ARCADE_GAMES_MEMORY_PATTERNS.md`

---

#### Task 2.3: Steampunk 雙胞胎之謎

**調查**:
- 為何 steampunk 和 steampunk2 用量完全相同？
- 版本差異？配置差異？部署策略？

**產出**: 整合到 Bingo 分析報告

---

### Phase 3: 標準化與文檔（2-4 週內）

#### Task 3.1: 分析標準文檔化

**產出**: `ANALYSIS_DEPTH_STANDARDS.md`
- 定義 3 個層級：Basic, Standard, Deep
- 每個層級的檢查清單
- 工具腳本模板

---

#### Task 3.2: 自動化監控腳本

**產出**: `scripts/deep_dive_monitor.sh`
- 自動收集 42 小時時間序列
- 自動提取連線數
- 自動生成初步分析報告

---

## 🎯 成功標準

### 完成 Phase 1 後

- ✅ luckydropcoc2 有完整的 20+ KB 深度分析報告
- ✅ lostruins 有 15+ KB 對比分析報告
- ✅ 兩者都包含：
  - 時間序列數據（至少 24 小時）
  - 連線數關聯分析
  - Memory Leak 風險評估（量化置信度）
  - 多假設對比
  - 驗證方案
- ✅ 修復建議基於數據支撐，而非猜測

### 完成 Phase 2 後

- ✅ 所有 13 個新服務都有深度分析
- ✅ 系列對比分析完成（LuckyDrop, Arcade, Steampunk）
- ✅ 異常模式根因明確

### 完成 Phase 3 後

- ✅ 分析標準文檔化
- ✅ 自動化工具到位
- ✅ 未來新服務可自動達到 Deep 標準

---

## 📝 追蹤表

| Task | 優先級 | 狀態 | 預估時間 | 完成日期 | 負責人 |
|------|-------|------|---------|---------|-------|
| luckydropcoc2 深度剖析 | 🔴🔴🔴 | ⭕ 待開始 | 6-8h | - | Claude Code |
| lostruins 深度剖析 | 🔴🔴 | ⭕ 待開始 | 4-6h | - | Claude Code |
| LuckyDrop 系列分析 | ⚠️ | ⭕ 待開始 | 4-6h | - | - |
| Arcade Games 擴展 | ⚠️ | ⭕ 待開始 | 6-8h | - | - |
| Steampunk 調查 | ⚠️ | ⭕ 待開始 | 2-4h | - | - |
| 分析標準文檔 | 📘 | ⭕ 待開始 | 4h | - | - |
| 自動化腳本 | 📘 | ⭕ 待開始 | 6-8h | - | - |

---

## 💡 關鍵洞察

### 為何分析深度重要？

**案例: ForestTeaParty**

如果只做靜態分析：
- ❌ 可能誤判為 "配置過高"（181Mi / 700Mi = 26%）
- ❌ 可能建議降低 Request 到 300Mi
- ❌ 忽略 memory leak 風險（65-70% 置信度）
- ❌ 看不到記憶體增長與連線下降的矛盾

深度分析後發現：
- ✅ 歷史峰值達 553Mi（接近原 600Mi Limit）
- ✅ Pod 已重啟（因資源配置更新到 700Mi/1Gi）
- ✅ 存在潛在 memory leak（需持續監控）
- ✅ 建議保持 700Mi Request 是正確的

**差異**: 可能導致錯誤決策 vs 數據支撐的正確決策

---

**最後更新**: 2025-11-08 01:30 UTC+8
**下次檢查**: P0 深度分析開始前
