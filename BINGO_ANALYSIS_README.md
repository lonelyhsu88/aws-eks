# Bingo Games 記憶體分析報告集合

**分析日期**: 2025-11-07
**分析師**: Claude Code
**目的**: 全面分析 10 個 Bingo 遊戲服務的記憶體使用情況，比照 ForestTeaParty 深度分析標準

---

## 報告文件列表

### 1. 主報告：詳細分析
**檔案**: [`BINGO_GAMES_MEMORY_ANALYSIS.md`](./BINGO_GAMES_MEMORY_ANALYSIS.md)

**內容**:
- 10 個 Bingo 服務的完整記憶體分析
- 每個服務的詳細評估和建議
- 資源配置不一致性分析
- 優化建議和實施計劃
- 風險評估

**適合對象**: DevOps 工程師、SRE、技術主管

**重點發現**:
- 🚨 2 個服務超過 HPA 閾值（cavebingo: 87%, caribbeanbingo: 85%）
- 🔥 1 個服務嚴重過度配置（bonusbingo: 使用率僅 25%，request 1536Mi）
- ⚠️ 配置範圍極大（140Mi - 1536Mi，相差 11 倍）
- ✅ 所有服務零重啟，運行穩定

---

### 2. 快速參考：總結表格
**檔案**: [`BINGO_GAMES_SUMMARY_TABLE.md`](./BINGO_GAMES_SUMMARY_TABLE.md)

**內容**:
- 快速參考表格
- 立即處理項目（P0）
- 資源優化建議
- kubectl 命令範例

**適合對象**: 需要快速了解狀況的團隊成員

**使用時機**:
- 快速健康檢查
- 向管理層報告
- 制定優先級

---

### 3. 對比分析：Bingo vs ForestTeaParty
**檔案**: [`BINGO_VS_FORESTTEAPARTY_COMPARISON.md`](./BINGO_VS_FORESTTEAPARTY_COMPARISON.md)

**內容**:
- 詳細對比 Bingo Games 與 ForestTeaParty 的配置策略
- 資源效率分析
- 配置一致性評估
- 三種標準化配置方案（保守/平衡/激進）
- 推薦方案和實施路線圖

**適合對象**: 架構師、技術決策者

**核心洞察**:
- ForestTeaParty: 保守配置（29.5% 使用率），統一標準
- Bingo Games: 配置混亂（25-87% 使用率），缺乏標準化
- 推薦採用「平衡策略」（目標使用率 50-70%）

---

### 4. 監控腳本：自動化健康檢查
**檔案**: [`scripts/check_bingo_memory.sh`](./scripts/check_bingo_memory.sh)

**功能**:
- 自動收集所有 Bingo 服務的記憶體使用數據
- 按使用率排序顯示
- 顏色標記（綠色/黃色/紅色）
- 自動建議優化方案
- 支援 alert-only 模式和 verbose 模式

**使用方法**:
```bash
# 基本使用
./scripts/check_bingo_memory.sh

# 只顯示警報（>= 75%）
./scripts/check_bingo_memory.sh --alert-only

# 詳細模式（包含 Pod/HPA/Events）
./scripts/check_bingo_memory.sh --verbose
```

**輸出範例**:
```
Service              |    Usage |  Request |    Limit | Usage% |        HPA |   RS | Status
--------------------------------------------------------------------------------
cavebingo            |    122 Mi |    140 Mi |    220 Mi |    87% |    87%/80% |    0 | 🚨
caribbeanbingo       |    127 Mi |    150 Mi |    250 Mi |    84% |    85%/80% |    0 | ⚠️
odinbingo            |    132 Mi |    200 Mi |    320 Mi |    66% |    66%/80% |    0 | ✅
...

Summary
========================================
Total Services:    10
Critical (>= 85%): 1
Warnings (>= 75%): 2
Healthy:           8

⚠️  CRITICAL: 1 service(s) need immediate attention!
```

**退出碼**:
- `0`: 所有服務健康
- `1`: 有警告（>= 75%）
- `2`: 有緊急狀況（>= 85%）

**適合用於**:
- Cron job 定期監控
- CI/CD pipeline 健康檢查
- 手動快速診斷

---

## 關鍵數據快速查詢

### 資源使用總覽

| 指標 | 最小值 | 最大值 | 平均值 | 中位數 |
|------|-------|-------|-------|-------|
| **記憶體使用** | 108 Mi | 391 Mi | 156 Mi | 133 Mi |
| **Request** | 140 Mi | 1536 Mi | 512 Mi | 400 Mi |
| **Limit** | 220 Mi | 3072 Mi | 946 Mi | 700 Mi |
| **使用率** | 25% | 87% | 44% | 33% |

### 立即處理清單（優先級排序）

#### P0 - 緊急（24 小時內）

1. **cavebingo-prd** 🚨
   - 當前: 122 Mi / 140 Mi (87%)
   - 建議: 200 Mi request / 350 Mi limit
   - 風險: 最高，可能被驅逐

2. **caribbeanbingo-prd** 🚨
   - 當前: 128 Mi / 150 Mi (85%)
   - 建議: 220 Mi request / 400 Mi limit
   - 風險: 高，缺乏峰值緩衝

#### P1 - 高優先級（1 週內）

3. **bonusbingo-prd** 🔥
   - 當前: 391 Mi / 1536 Mi (25%)
   - 建議: 600 Mi request / 1 Gi limit
   - 原因: 可釋放 936 Mi request 資源

#### P2 - 中優先級（2-4 週內）

4-9. 其他 6 個服務的配置優化（詳見主報告）

### 預期資源節省

| 項目 | Request | Limit |
|-----|---------|-------|
| 總增加 | +130 Mi | +280 Mi |
| 總減少 | -1,796 Mi | ~-2,100 Mi |
| **淨節省** | **-1,666 Mi** (~1.63 Gi) | **~-1,820 Mi** (~1.78 Gi) |

---

## 推薦閱讀順序

### 對於 DevOps 工程師（需要立即執行）

1. ✅ 閱讀 [`BINGO_GAMES_SUMMARY_TABLE.md`](./BINGO_GAMES_SUMMARY_TABLE.md) - 5 分鐘
   - 快速了解哪些服務需要立即處理

2. ✅ 執行 [`scripts/check_bingo_memory.sh`](./scripts/check_bingo_memory.sh) - 1 分鐘
   - 確認當前狀態

3. ✅ 參考 [`BINGO_GAMES_MEMORY_ANALYSIS.md`](./BINGO_GAMES_MEMORY_ANALYSIS.md) 的「優化建議」章節 - 10 分鐘
   - 獲取具體的配置修改指令

4. ✅ 實施 P0 修復（cavebingo, caribbeanbingo）- 30 分鐘

### 對於架構師/技術主管（需要制定策略）

1. ✅ 閱讀 [`BINGO_VS_FORESTTEAPARTY_COMPARISON.md`](./BINGO_VS_FORESTTEAPARTY_COMPARISON.md) - 20 分鐘
   - 了解配置策略差異和最佳實踐

2. ✅ 閱讀 [`BINGO_GAMES_MEMORY_ANALYSIS.md`](./BINGO_GAMES_MEMORY_ANALYSIS.md) - 30 分鐘
   - 深入了解每個服務的詳細情況

3. ✅ 決策：選擇標準化配置方案
   - 方案 A（保守）vs 方案 B（平衡，推薦）vs 方案 C（激進）

4. ✅ 制定實施計劃（Phase 1-4）

### 對於管理層（需要了解影響）

1. ✅ 閱讀本檔案的「關鍵數據快速查詢」章節 - 5 分鐘

2. ✅ 閱讀 [`BINGO_GAMES_SUMMARY_TABLE.md`](./BINGO_GAMES_SUMMARY_TABLE.md) - 5 分鐘
   - 了解資源節省潛力

3. ✅ 關注「預期資源節省」：可節省 ~1.63 Gi request 資源

---

## 持續監控建議

### 1. 設置 Cron Job

```bash
# 每小時檢查一次，只在有警報時發送通知
0 * * * * /path/to/check_bingo_memory.sh --alert-only || echo "Bingo services need attention!" | mail -s "Bingo Memory Alert" devops@example.com
```

### 2. Prometheus Alerts

```yaml
# 記憶體使用率超過 80%
- alert: BingoServiceMemoryHigh
  expr: |
    container_memory_working_set_bytes{namespace=~".*bingo-prd"} /
    on(pod) kube_pod_container_resource_requests{resource="memory",namespace=~".*bingo-prd"} > 0.80
  for: 15m
  annotations:
    summary: "Bingo service {{ $labels.namespace }} memory usage > 80%"
    description: "Memory usage is {{ $value | humanizePercentage }}"
```

### 3. 定期複查

- **每日**: 執行 `check_bingo_memory.sh --alert-only`
- **每週**: 檢查記憶體使用趨勢
- **每月**: 複查配置是否需要調整
- **每季**: 更新標準化配置策略

---

## 相關文件

### 本專案其他分析

- [`FORESTTEAPARTY_DEEP_DIVE_ANALYSIS.md`](./FORESTTEAPARTY_DEEP_DIVE_ANALYSIS.md) - ForestTeaParty 原始深度分析
- [`FORESTTEAPARTY_RESOURCE_ANALYSIS.md`](./FORESTTEAPARTY_RESOURCE_ANALYSIS.md) - ForestTeaParty 資源分析
- [`SCHEDULE_SYNC_SERVICE_ANALYSIS.md`](./SCHEDULE_SYNC_SERVICE_ANALYSIS.md) - Schedule Sync 服務分析

### 專案文件

- [`CLAUDE.md`](./CLAUDE.md) - EKS 專案指南
- [`README.md`](../README.md) - 主專案 README

---

## 技術細節

### 數據收集方法

```bash
# 記憶體使用
kubectl top pod -n <namespace>

# 資源配置
kubectl get pod -n <namespace> -o jsonpath='{.spec.containers[0].resources}'

# HPA 狀態
kubectl get hpa -n <namespace>

# Pod 狀態
kubectl get pods -n <namespace> -o wide

# 日誌分析
kubectl logs -n <namespace> <pod-name> --tail=1000
```

### 分析標準

1. **記憶體使用率 = (實際使用 / Request) × 100%**
2. **理想使用率範圍**: 50-70%
3. **HPA 閾值**: 80%
4. **警報閾值**: 75%
5. **緊急閾值**: 85%

### 配置建議公式

```
建議 Request = 實際使用 × 1.5 ~ 2.0
建議 Limit = 建議 Request × 1.5 ~ 2.0
```

---

## 問題與支援

### 常見問題

**Q: 為什麼 bonusbingo 配置這麼高？**
A: 可能是初始配置時預期高負載，但實際未發生。建議降至 600Mi request。

**Q: cavebingo 和 caribbeanbingo 為什麼這麼低？**
A: 可能是配置時低估了實際需求。需要立即調整以避免驅逐風險。

**Q: 應該選擇哪種標準化方案？**
A: 推薦「方案 B - 平衡策略」（目標使用率 50-70%），在資源效率和穩定性之間取得平衡。

**Q: 調整配置會導致服務中斷嗎？**
A: StatefulSet 的配置調整會觸發 rolling update，建議在低峰時段進行。

### 聯絡方式

- **技術問題**: DevOps 團隊
- **配置變更審批**: SRE 主管
- **緊急事件**: On-call SRE

---

## 變更歷史

| 日期 | 版本 | 變更內容 | 作者 |
|------|------|---------|------|
| 2025-11-07 | 1.0 | 初始分析報告 | Claude Code |

---

## 授權與使用

本分析報告僅供內部使用，包含敏感的基礎設施資訊。

**請勿**:
- 分享到公司外部
- 提交到公開 repository
- 包含在對外文件中

**可以**:
- 內部團隊分享
- 用於配置決策
- 納入內部知識庫

---

**報告生成**: 2025-11-07
**資料來源**: EKS Cluster ap-east-1
**分析工具**: kubectl, Claude Code
**下次更新**: 實施優化後 7 天
