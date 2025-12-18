# Jira OPS 工作記錄

**Summary**: RDS PostgreSQL WAL Cleanup - Remove Orphaned Debezium Replication Slot

**Issue Type**: Task

**Labels**: `rds`, `postgresql`, `wal`, `debezium`, `maintenance`

**Jira Issue**: [OPS-873](https://jira.ftgaming.cc/browse/OPS-873)

---

## 目的
清理 RDS PostgreSQL 上棄用的 Debezium replication slot，釋放 46 GB 的 WAL 堆積空間。

## 背景
- **RDS Instance**: bingo-prd-backstage.crrfmdeapguf.ap-east-1.rds.amazonaws.com
- **Database**: combineddb
- **問題**: WAL 檔案持續堆積，佔用大量磁碟空間
- **根本原因**: 棄用的 Debezium replication slot 未清理

## 問題診斷

### 1. Replication Slots 狀態查詢

```sql
SELECT slot_name, slot_type, active,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) as lag
FROM pg_replication_slots;
```

**結果**:
| Slot 名稱 | 類型 | 狀態 | WAL 堆積 |
|-----------|------|------|----------|
| rds_ap_east_1_db_... | physical | active | 0 bytes |
| **t_orders_v8** | logical | **inactive** | **46 GB** |
| t_orders_v9 | logical | active | 5.4 GB |

### 2. 詳細分析

```sql
SELECT
    slot_name,
    plugin,
    database,
    active,
    active_pid,
    confirmed_flush_lsn,
    restart_lsn,
    pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) as wal_lag
FROM pg_replication_slots
WHERE slot_name IN ('t_orders_v8', 't_orders_v9');
```

**結果**:
| 指標 | t_orders_v8 | t_orders_v9 |
|------|-------------|-------------|
| plugin | wal2json | wal2json |
| database | combineddb | combineddb |
| active | **f** | t |
| active_pid | **NULL** | 18014 |
| confirmed_flush_lsn | 10E7/C0054108 | 10F1/F27BDBB8 |
| wal_lag | **46 GB** | 5400 MB |

### 3. 分析結論

1. **`t_orders_v8` 已被棄用**:
   - `active = f` (不活躍)
   - `active_pid = NULL` (無進程連接)
   - WAL 堆積 46 GB 且持續增長

2. **`t_orders_v9` 為目前使用中的 slot**:
   - `active = t` (活躍)
   - `active_pid = 18014` (有 Debezium 連接)
   - LSN 位置 `10F1` > v8 的 `10E7`，已消費到更前面

3. **版本迭代關係確認**:
   - 兩者使用相同配置 (wal2json + combineddb)
   - 命名規則 v8 → v9 表示版本升級
   - v9 完全取代 v8 功能

## 建議操作

### Step 1: 確認 Kafka Connect 側（可選）
```bash
# 確認沒有 connector 使用 v8
curl -s http://<kafka-connect-host>:8083/connectors | jq -r '.[]' | while read c; do
  slot=$(curl -s "http://<kafka-connect-host>:8083/connectors/$c/config" | jq -r '.["slot.name"] // empty')
  echo "$c: $slot"
done
```

### Step 2: 刪除棄用的 Slot
```sql
-- 刪除 t_orders_v8，釋放 46 GB WAL
SELECT pg_drop_replication_slot('t_orders_v8');
```

### Step 3: 驗證空間釋放
```sql
-- 確認 slot 已刪除
SELECT slot_name, pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) as wal_lag
FROM pg_replication_slots;

-- 手動觸發 checkpoint 加速 WAL 清理
CHECKPOINT;

-- 檢查 WAL 目錄大小
SELECT pg_size_pretty(sum(size)) as wal_size FROM pg_ls_waldir();
```

## 預期結果

- ✅ 釋放約 46 GB 磁碟空間
- ✅ WAL 目錄大小顯著減少
- ✅ 防止未來磁碟空間不足問題

## 風險評估

| 風險 | 機率 | 影響 | 緩解措施 |
|------|------|------|----------|
| 誤刪活躍 slot | 低 | 高 | 已確認 v8 為 inactive |
| Debezium 仍需要 v8 | 低 | 中 | 檢查 Kafka Connect 配置 |
| WAL 未立即釋放 | 中 | 低 | 執行 CHECKPOINT |

## 注意事項

1. **WAL 不會立即釋放**
   - 需等待 checkpoint 發生
   - 可手動執行 `CHECKPOINT;`

2. **監控 t_orders_v9**
   - 目前有 5.4 GB lag
   - 需持續監控確保正常消費

3. **未來預防**
   - Debezium 版本升級後應及時清理舊 slot
   - 建議設定 WAL 監控告警

## 相關資源

- **RDS Instance**: bingo-prd-backstage
- **Region**: ap-east-1 (Hong Kong)
- **CDC Tool**: Debezium with wal2json
- **Database**: combineddb

---

**建立日期**: 2025-12-02
**執行人員**: DevOps Team
**狀態**: ⏳ 待執行
