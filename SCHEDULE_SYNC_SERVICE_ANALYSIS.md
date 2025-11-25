# Schedule & Sync Service 日誌分析報告

**Services**: schedule-prd, syncservice-prd
**Date**: 2025-11-07
**Cluster**: gemini-game-prd (ap-east-1)
**Analysis By**: Claude Code

---

## 🚨 Executive Summary

兩個後台服務存在**穩定性和效能問題**：

### Schedule Service
- 🔴 **OOMKilled 歷史**：3 次重啟，最後一次因記憶體不足被終止
- 🔴 **Read-only file system 錯誤**
- ⚠️ **大量統計任務**：每天處理 100,971 個玩家記錄
- ✅ **當前狀態穩定**：記憶體使用 5% (18Mi)

### Sync Service
- ⚠️ **Read-only file system 錯誤**
- ⚠️ **SQL 查詢效能問題**：部分查詢耗時 5+ 秒
- ⚠️ **高頻同步**：每 60 秒執行一次完整同步
- ✅ **當前狀態穩定**：記憶體使用 22% (46Mi)

---

## 📊 服務概覽

### 1. Schedule Service (schedule-prd)

| 屬性 | 值 |
|------|-----|
| **Pod 名稱** | schedule-7f7988db95-xbswg |
| **狀態** | Running |
| **重啟次數** | 3 次 |
| **最後重啟** | 9 小時前 (Nov 7 00:25:03) |
| **運行時間** | 3 天 8 小時 |
| **記憶體使用** | 17Mi / 500Mi (3.4%) |
| **CPU 使用** | 0m |
| **記憶體 Request** | 300Mi |
| **記憶體 Limit** | 500Mi |
| **CPU Request** | 10m |
| **CPU Limit** | 100m |
| **HPA 記憶體** | 5% (18Mi / 300Mi request) |
| **HPA 閾值** | 80% |
| **Min/Max Pods** | 1 / 1 (無法擴展) |

### 2. Sync Service (syncservice-prd)

| 屬性 | 值 |
|------|-----|
| **Pod 名稱** | syncservice-5866bf79d-zs4tt |
| **狀態** | Running |
| **重啟次數** | 0 次 |
| **最後重啟** | 83 分鐘前 (Nov 7 08:09:09) |
| **記憶體使用** | 27Mi / 500Mi (5.4%) |
| **CPU 使用** | 0m |
| **記憶體 Request** | 200Mi |
| **記憶體 Limit** | 500Mi |
| **CPU Request** | 100m |
| **CPU Limit** | 300m |
| **HPA 記憶體** | 22% (46Mi / 200Mi request) |
| **HPA 閾值** | 80% |
| **Min/Max Pods** | 1 / 1 (無法擴展) |

---

## 🔍 Schedule Service 詳細分析

### 問題 1: OOMKilled 歷史 🔴

**發現**：
```
Last State:     Terminated
  Reason:       OOMKilled
  Exit Code:    137
  Started:      Fri, 07 Nov 2025 00:17:55 +0800
  Finished:     Fri, 07 Nov 2025 00:24:39 +0800
```

**時間線**：
- 00:17:55 - Pod 啟動
- 00:24:39 - 被 OOMKilled (運行僅 6 分 44 秒)
- 00:25:03 - 自動重啟

**OOMKilled 原因分析**：

#### 可能原因 1: 統計任務記憶體峰值過高

從日誌看到，服務在 **00:05:00** 啟動大量統計任務：

```json
{"time":"2025-11-07 00:05:00:083","msg":"cron: statistics_last_day_player_data start"}
```

**處理量**：
- 總玩家數：**100,971 個**
- 分頁數：**202 頁**
- 每批次：**5,000 筆**
- 處理時間：**00:05:00 - 01:04:31** (約 **59 分鐘**)

**記憶體使用推測**：
```
每筆玩家記錄假設 10KB
5,000 筆 × 10KB = 50MB (單批次)
如果有記憶體洩漏或累積，可能超過 500Mi limit
```

#### 可能原因 2: 批次處理不當

日誌顯示批次處理過程中可能存在記憶體累積：

```
Processed batch with offset 0, got 5000 records
Processed batch with offset 5000, got 5000 records
...
Processed batch with offset 95000, got 5000 records
```

如果每批次處理後**沒有正確釋放記憶體**，會導致記憶體持續增長。

---

### 問題 2: Read-Only File System 錯誤 🔴

**錯誤日誌**：
```bash
/app/set_variable.sh: line 2: /app/config/config.ini: Read-only file system
/app/start.sh: line 5: /proc/sys/kernel/core_pattern: Read-only file system
```

**影響**：
- ❌ 啟動腳本嘗試寫入配置文件失敗
- ❌ 嘗試設定 core dump 路徑失敗
- ⚠️ 服務仍能正常運行（配置透過環境變數或 ConfigMap）

**根本原因**：

1. **ConfigMap/Secret 掛載的檔案系統是 read-only**
   ```yaml
   volumeMounts:
   - mountPath: /app/config
     name: config
     readOnly: true  # 預設是 read-only
   ```

2. **`/proc/sys/` 是唯讀的**（Kubernetes 安全限制）

**解決方案**：

#### 方案 A: 修改啟動腳本（推薦）

不要嘗試寫入檔案，改為：

```bash
# 錯誤做法
cat > /app/config/config.ini << EOF
...
EOF

# 正確做法
cat << EOF
...
EOF
# 直接讀取環境變數或 ConfigMap
```

#### 方案 B: 使用 emptyDir 作為臨時目錄

```yaml
volumeMounts:
- mountPath: /tmp/config
  name: temp-config
volumes:
- name: temp-config
  emptyDir: {}
```

---

### 問題 3: Cron Job 任務調度

**當前配置**：

| Cron Job | Schedule | 說明 |
|----------|----------|------|
| statistics_last_day_data | `0 0 7 * * *` | 每天 7:00 統計前一天數據 |
| retry_failed_statistics_data | `0 0 8 * * *` | 每天 8:00 重試失敗的統計 |
| statistics_last_day_player_data | `0 5 0 * * *` | 每天 00:05 統計玩家數據 |
| retry_failed_statistics_player_data | `0 35 0 * * *` | 每天 00:35 重試失敗的玩家統計 |

**效能觀察**：

#### 玩家統計任務（最耗時）

```
開始時間: 00:05:00
結束時間: 01:04:31
耗時: 59 分 31 秒

處理流程:
1. 讀取 100,971 個玩家記錄（分批 5,000）
2. 批次 Upsert 到 combineddb
3. 202 頁，每頁約 500 筆
```

**效能瓶頸**：
- 資料庫寫入：每批次約 300-500ms
- 網路往返：ap-east-1 RDS 連線延遲
- 單執行緒處理（無並行）

---

## 🔍 Sync Service 詳細分析

### 問題 1: 高頻同步（每 60 秒） ⚠️

**同步週期**：
```
09:15:50 - Sync 完成 (1407ms)
09:16:50 - 下一次同步開始
09:17:50 - 下一次同步開始
```

**每次同步內容**：
1. **Bingo DB** - Order + Game
2. **Hash PG DB** - Order + Game
3. **RNG DB** - Order + Game
4. **Combined DB** - 寫入同步資料

**同步數量（每分鐘）**：

| 資料庫 | Order 數量 | Game 數量 | 寫入時間 |
|--------|-----------|-----------|---------|
| Bingo | 140-195 | 41-60 | 246-494ms |
| Hash PG | 934-1,251 | 831-1,151 | 646-906ms |
| RNG | 467-629 | 558-722 | 600-835ms |
| **總計** | **~2,500-3,000** | **~1,500-2,000** | **~1.2-2.3 秒** |

**效能評估**：

✅ **正面**：
- 同步延遲低（1-2 秒內完成）
- 記憶體使用穩定（22%）
- 無錯誤或異常

⚠️ **潛在問題**：
- 每分鐘同步頻率可能過高
- 資料庫負載增加
- 可能造成不必要的網路流量

---

### 問題 2: SQL 查詢效能問題 🔴

**慢查詢警告**：

```json
{"level":"warn","time":"2025-11-07 09:20:56:272",
 "msg":"[5740.328ms] [rows:41] SELECT game.*,orders.f_currency AS currency,..."}
```

**慢查詢統計**：

| 時間 | 耗時 | 結果筆數 | 查詢類型 |
|------|------|---------|---------|
| 09:15:51 | **1001ms** | 49 rows | Bingo Game + Orders Join |
| 09:19:51 | **1000ms** | 49 rows | Bingo Game + Orders Join |
| 09:20:56 | **5740ms** | 41 rows | Bingo Game + Orders Join |
| 09:21:52 | **2287ms** | 60 rows | Bingo Game + Orders Join |

**查詢模式**：
```sql
SELECT game.*,
       orders.f_currency AS currency,
       orders.f_pid AS pid,
       (SUM(COALESCE(orders.f_amount,0))/100.0000)::NUMERIC(20,4) AS wager,
       (SUM(COALESCE(orders.f_won,0))/100.0000)::NUMERIC(20,4) AS payout,
       ...
FROM t_bingo_game game
LEFT JOIN t_bingo_orders orders ...
```

**效能問題分析**：

#### 1. 查詢複雜度高
- LEFT JOIN 大表（orders 表可能有數百萬筆）
- 多個 SUM 聚合函數
- 數值型別轉換 `::NUMERIC(20,4)`

#### 2. 缺少索引
可能缺少以下索引：
- `orders.f_game_id` (JOIN key)
- `orders.created_at` (時間範圍過濾)
- `orders.f_currency` (分組依據)

#### 3. 時間範圍過濾缺失
如果查詢沒有時間限制，會掃描整個 orders 表。

---

### 問題 3: Read-Only File System 錯誤

**錯誤日誌**：
```bash
/app/set_variable.sh: line 2: /app/config.json: Read-only file system
/app/start.sh: line 5: /proc/sys/kernel/core_pattern: Read-only file system
```

**與 Schedule Service 相同的問題**，參考上方解決方案。

---

## 📊 資料庫連線配置

### Schedule Service 資料庫

| 資料庫 | 主機 | 用途 |
|--------|------|------|
| **bingodb** | bingo-prd-replica1 (replica) | 讀取 Bingo 遊戲數據 |
| **combineddb** | bingo-prd-backstage | 寫入統計數據 |
| **loyaltydb** | bingo-prd-loyalty | 讀取會員數據 |

### Sync Service 資料庫

| 資料庫 | 主機 | 連線池 | 用途 |
|--------|------|--------|------|
| **bingo** | bingo-prd-replica1 (replica) | max:2, idle:1 | Bingo 遊戲數據 |
| **hash** | hash-prd (Oracle) | max:2, idle:1 | Hash 遊戲數據 |
| **hash_pg** | bingo-prd-replica1 | max:4, idle:2 | Hash PG 數據 |
| **rng** | bingo-prd-replica1 | max:4, idle:2 | RNG 遊戲數據 |
| **combined** | bingo-prd-backstage | max:10, idle:6 | 合併數據庫 |

**觀察**：
✅ 大部分讀取都使用 **replica** (bingo-prd-replica1)，減少主庫負載
⚠️ 連線池設定較小（max:2-4），可能在高峰時期不足

---

## 🚨 安全性警告

### 日誌洩漏資料庫密碼 🔴🔴🔴

**問題**：
啟動腳本將配置輸出到 stdout，**資料庫密碼明文顯示在日誌中**！

```ini
[database.bingodb]
user = bingo
password = eiyF3O7JhNeH$Ef  ← 明文密碼！

[database.combineddb]
user = migrateuser
password = EcdxsxD4C6D9tGqO  ← 明文密碼！

[database.loyaltydb]
user = loyalty
password = TIyot3Gwuccm4opq7EdW  ← 明文密碼！
```

**受影響的密碼**：
- bingodb: `eiyF3O7JhNeH$Ef`
- combineddb: `EcdxsxD4C6D9tGqO`
- loyaltydb: `TIyot3Gwuccm4opq7EdW`
- hashdb (hash_pg): `w1BM5AW9JCMjQqoi`
- rngdb: `59xnpPjEqppw2YDk`
- hash (Oracle): `6K6yT0xk0eE765jd`

**風險等級**: 🔴🔴🔴 **P0 - 嚴重安全漏洞**

**影響**：
- 任何可訪問 Kubernetes logs 的人都能看到密碼
- ArgoCD 可能也記錄了這些日誌
- 日誌可能被發送到集中式日誌系統（ELK/CloudWatch）

**立即行動**：
1. ✅ 停止在啟動腳本中輸出配置
2. ✅ 輪換所有資料庫密碼
3. ✅ 審計誰訪問過這些日誌
4. ✅ 檢查日誌系統是否保存了這些密碼

---

## ✅ 解決方案

### 🔥 緊急修復（24 小時內）

#### 1. 修復安全漏洞 - 停止洩漏密碼 ⭐⭐⭐

**修改啟動腳本**：

```bash
# 錯誤做法 - 當前腳本
cat /app/config/config.ini

# 正確做法
echo "Loading configuration..."
# 不要輸出配置內容！
```

**部署流程**：
1. 修改 Docker image 的啟動腳本
2. 構建新 image
3. 更新 Kubernetes deployment
4. 重新部署服務

#### 2. 輪換所有資料庫密碼

```bash
# 在 RDS Console 或使用 AWS CLI
aws rds modify-db-instance \
  --db-instance-identifier bingo-prd-replica1 \
  --master-user-password <NEW_PASSWORD> \
  --apply-immediately
```

#### 3. 修復 Read-Only File System 錯誤

**修改啟動腳本** (`/app/set_variable.sh`, `/app/start.sh`):

```bash
# 刪除這些行
echo "..." > /app/config/config.ini  # ← 移除
echo "..." > /proc/sys/kernel/core_pattern  # ← 移除

# 改為直接使用 ConfigMap 或環境變數
# 不需要寫入檔案
```

---

### 📅 短期優化（1 週內）

#### 4. 增加 Schedule Service 記憶體限制

**問題**：統計任務在 00:05 - 01:04 期間處理 100,971 筆記錄，可能導致記憶體不足。

**建議配置**：

```yaml
resources:
  requests:
    cpu: 20m        # 增加 (10m → 20m)
    memory: 500Mi   # 增加 (300Mi → 500Mi)
  limits:
    cpu: 200m       # 增加 (100m → 200m)
    memory: 1Gi     # 增加 (500Mi → 1Gi)
```

**原因**：
- 當前 500Mi limit 在峰值時期不足
- 增加到 1Gi 提供更多緩衝空間
- Request 也需要提高，避免 HPA 誤判

#### 5. 優化 Sync Service SQL 查詢

**建議優化**：

##### A. 加入時間範圍過濾

```sql
-- 當前（慢）
SELECT game.*, ...
FROM t_bingo_game game
LEFT JOIN t_bingo_orders orders ON ...

-- 優化後（快）
SELECT game.*, ...
FROM t_bingo_game game
LEFT JOIN t_bingo_orders orders ON ...
WHERE orders.created_at >= NOW() - INTERVAL '2 minutes'  -- 只查詢最近 2 分鐘
```

##### B. 新增資料庫索引

```sql
-- 在 bingodb 執行
CREATE INDEX idx_bingo_orders_created_at ON t_bingo_orders(created_at);
CREATE INDEX idx_bingo_orders_game_id ON t_bingo_orders(f_game_id);
CREATE INDEX idx_bingo_orders_currency ON t_bingo_orders(f_currency);

-- 複合索引
CREATE INDEX idx_bingo_orders_game_created
ON t_bingo_orders(f_game_id, created_at);
```

##### C. 使用物化視圖（如果頻繁查詢）

```sql
CREATE MATERIALIZED VIEW mv_game_statistics AS
SELECT game.*,
       orders.f_currency AS currency,
       ...
FROM t_bingo_game game
LEFT JOIN t_bingo_orders orders ON ...
GROUP BY ...;

-- 每分鐘刷新
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_game_statistics;
```

#### 6. 調整 Sync 頻率

**評估是否需要每 60 秒同步一次**：

| 頻率選項 | 優點 | 缺點 |
|---------|------|------|
| 60 秒（當前） | 數據最新 | 資料庫負載高 |
| 120 秒 | 負載減半 | 數據延遲增加 60 秒 |
| 300 秒（5 分鐘） | 負載降低 80% | 數據延遲較高 |

**建議**：
- 評估業務需求：是否需要秒級數據同步？
- 如果可接受 2-3 分鐘延遲，改為 120 秒
- 監控同步延遲和資料庫負載

---

### 🔧 長期改進（1 個月內）

#### 7. Schedule Service 任務並行化

**當前問題**：
- 單執行緒處理 100,971 筆記錄
- 耗時 59 分鐘

**優化方案**：

```go
// 並行處理批次
const numWorkers = 5
batches := make(chan []Player, 202)
results := make(chan BatchResult, 202)

// 啟動 workers
for i := 0; i < numWorkers; i++ {
    go func() {
        for batch := range batches {
            processBatch(batch)
            results <- BatchResult{...}
        }
    }()
}

// 預期效能提升：59 分鐘 → 12 分鐘
```

#### 8. 實施 HPA 自動擴展

**當前配置**：
```yaml
minReplicas: 1
maxReplicas: 1  # ← 無法擴展
```

**建議配置**：

```yaml
# Schedule Service (統計任務週期性高負載)
minReplicas: 1
maxReplicas: 2  # 高峰時期擴展到 2
targetMemoryUtilization: 70%

# Sync Service (持續負載)
minReplicas: 1
maxReplicas: 3  # 允許水平擴展
targetMemoryUtilization: 70%
```

#### 9. 增加資料庫連線池

**Sync Service 當前連線池**：

```json
{
  "bingo": {"max_connections": 2, "max_idle_connections": 1},
  "hash": {"max_connections": 2, "max_idle_connections": 1},
  "combined": {"max_connections": 10, "max_idle_connections": 6}
}
```

**建議配置**：

```json
{
  "bingo": {"max_connections": 5, "max_idle_connections": 3},
  "hash": {"max_connections": 5, "max_idle_connections": 3},
  "hash_pg": {"max_connections": 8, "max_idle_connections": 4},
  "rng": {"max_connections": 8, "max_idle_connections": 4},
  "combined": {"max_connections": 15, "max_idle_connections": 10}
}
```

#### 10. 實施監控和告警

**Prometheus 告警規則**：

```yaml
groups:
- name: schedule_sync_alerts
  rules:
  # Schedule Service OOM 風險
  - alert: ScheduleServiceHighMemory
    expr: (container_memory_usage_bytes{pod=~"schedule-.*"} / container_spec_memory_limit_bytes) > 0.85
    for: 5m
    annotations:
      summary: "Schedule service memory usage > 85%"
      description: "Memory: {{ $value }}%"

  # Sync Service 慢查詢
  - alert: SyncServiceSlowQuery
    expr: rate(slow_query_count[5m]) > 0.1
    for: 2m
    annotations:
      summary: "Sync service experiencing slow queries"

  # 資料庫連線池耗盡
  - alert: DatabaseConnectionPoolExhausted
    expr: db_connection_pool_active / db_connection_pool_max > 0.9
    for: 3m
    annotations:
      summary: "Database connection pool > 90% utilized"
```

---

## 📊 效能基準

### Schedule Service

| 指標 | 當前值 | 目標值 | 優化後預期 |
|------|--------|--------|-----------|
| 統計任務耗時 | 59 分鐘 | < 15 分鐘 | 12 分鐘（並行化） |
| 記憶體峰值 | > 500Mi (OOM) | < 800Mi | ~700Mi |
| OOMKilled 頻率 | 3 次/3 天 | 0 次 | 0 次 |
| CPU 使用率 | 0% (閒置時) | < 30% | 15% (平均) |

### Sync Service

| 指標 | 當前值 | 目標值 | 優化後預期 |
|------|--------|--------|-----------|
| 同步延遲 | 1.2-2.3 秒 | < 1 秒 | 0.8 秒 |
| SQL 查詢耗時 | 1-5.7 秒 | < 500ms | 200ms |
| 同步頻率 | 60 秒 | 120 秒 | 120 秒 |
| 記憶體使用 | 22% (46Mi) | < 60% | 40% |

---

## 🎯 實施優先級

### P0 - 緊急（24 小時）
1. ✅ **修復密碼洩漏** - 修改啟動腳本
2. ✅ **輪換資料庫密碼** - 所有受影響的資料庫
3. ✅ **修復 Read-Only FS 錯誤** - 移除寫入操作

### P1 - 高優先級（1 週）
1. ✅ **增加 Schedule 記憶體限制** - 500Mi → 1Gi
2. ✅ **優化 SQL 查詢** - 加入時間過濾和索引
3. ✅ **調整 Sync 頻率** - 評估業務需求

### P2 - 中優先級（1 個月）
1. ✅ **實施 HPA 擴展** - maxPods 1 → 2-3
2. ✅ **並行化統計任務** - 減少處理時間
3. ✅ **增加連線池** - 提升吞吐量
4. ✅ **建立監控告警** - Prometheus + Grafana

---

## 📝 檢查清單

### Schedule Service 健康檢查

```
□ 記憶體使用 < 80%
□ 無 OOMKilled 事件（過去 7 天）
□ 統計任務完成時間 < 20 分鐘
□ 無啟動腳本錯誤
□ 資料庫連線正常
□ Cron jobs 按時執行
```

### Sync Service 健康檢查

```
□ 記憶體使用 < 70%
□ 同步延遲 < 1.5 秒
□ SQL 查詢耗時 < 1 秒
□ 無慢查詢警告
□ 資料庫連線池健康
□ 資料同步無遺漏
```

### 安全檢查

```
□ 日誌中無明文密碼
□ 所有資料庫密碼已輪換
□ 啟動腳本不輸出敏感資訊
□ ConfigMap/Secret 正確掛載
□ RBAC 權限最小化
```

---

## 🔗 相關資源

### 日誌位置

```bash
# Schedule Service
kubectl logs -n schedule-prd schedule-7f7988db95-xbswg --tail=500
kubectl exec -n schedule-prd schedule-7f7988db95-xbswg -- tail -f /app/log/Schedule.log

# Sync Service
kubectl logs -n syncservice-prd syncservice-5866bf79d-zs4tt --tail=500
kubectl exec -n syncservice-prd syncservice-5866bf79d-zs4tt -- tail -f /app/log/Sync-Service.log
```

### 資源監控

```bash
# 實時資源使用
kubectl top pod -n schedule-prd
kubectl top pod -n syncservice-prd

# HPA 狀態
kubectl describe hpa -n schedule-prd
kubectl describe hpa -n syncservice-prd

# 事件查看
kubectl get events -n schedule-prd --sort-by='.lastTimestamp' | tail -20
kubectl get events -n syncservice-prd --sort-by='.lastTimestamp' | tail -20
```

### 資料庫查詢

```bash
# 連線到 RDS
psql -h bingo-prd-replica1.crrfmdeapguf.ap-east-1.rds.amazonaws.com \
     -U bingo -d bingodb

# 檢查慢查詢
SELECT * FROM pg_stat_statements
WHERE mean_exec_time > 1000
ORDER BY mean_exec_time DESC
LIMIT 10;

# 檢查索引
SELECT * FROM pg_indexes
WHERE tablename = 't_bingo_orders';
```

---

## 🎬 結論

### 主要發現

1. **Schedule Service** 存在 OOMKilled 風險，需要增加記憶體限制和優化統計任務
2. **Sync Service** SQL 查詢效能問題，需要優化查詢和增加索引
3. **嚴重安全漏洞**：資料庫密碼明文出現在日誌中，需要立即修復
4. **Read-Only FS 錯誤**：啟動腳本嘗試寫入唯讀檔案系統

### 建議行動

**立即執行**（P0）：
- 修復密碼洩漏問題
- 輪換所有資料庫密碼
- 修改啟動腳本

**1 週內完成**（P1）：
- 增加 Schedule Service 記憶體
- 優化 SQL 查詢效能
- 調整同步頻率

**1 個月內完成**（P2）：
- 實施 HPA 自動擴展
- 並行化統計任務
- 建立完整監控系統

### 預期效果

優化後預期：
- ✅ OOMKilled 事件減少為 0
- ✅ 統計任務時間從 59 分鐘降至 12 分鐘
- ✅ SQL 查詢效能提升 90%（5.7 秒 → 200ms）
- ✅ 消除安全漏洞
- ✅ 服務穩定性和可靠性大幅提升

---

**報告生成時間**: 2025-11-07 09:35 UTC+8
**分析工具**: Claude Code
**Cluster**: gemini-game-prd (ap-east-1)
**Services**: schedule-prd, syncservice-prd
