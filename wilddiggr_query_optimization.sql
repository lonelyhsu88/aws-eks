-- ============================================
-- WildDigGR Query Optimization Script
-- ============================================
-- 目標: 優化玩家最近投注金額查詢
-- 執行時間目標: 2900ms → 10-50ms (98% improvement)
-- ============================================

-- 查詢問題:
-- SELECT f_amount FROM t_orders
-- WHERE f_game_type = 'StandAloneWildDigGR'
--   AND f_loginname = 'GMM37420ws235866475'
--   AND f_table_id = 'WDGR1'
--   AND f_amount != 0
--   AND f_status IN (4, 10)
--   AND f_join_time >= now() - interval '1 week'
-- ORDER BY f_join_time DESC
-- LIMIT 1;

-- ============================================
-- Step 1: 檢查當前索引狀態
-- ============================================

-- 查看 t_orders 表的所有索引
SELECT
    indexname,
    indexdef
FROM pg_indexes
WHERE tablename = 't_orders'
  AND indexname LIKE '%wilddiggr%' OR indexname LIKE '%game_type%' OR indexname LIKE '%loginname%';

-- 查看表大小
SELECT
    pg_size_pretty(pg_total_relation_size('t_orders')) as total_size,
    (SELECT count(*) FROM t_orders WHERE f_game_type = 'StandAloneWildDigGR') as wilddiggr_rows;

-- ============================================
-- Step 2: 分析當前查詢執行計劃
-- ============================================

EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT f_amount
FROM t_orders
WHERE f_game_type = 'StandAloneWildDigGR'
  AND f_loginname = 'GMM37420ws235866475'
  AND f_table_id = 'WDGR1'
  AND f_amount != 0
  AND f_status IN (4, 10)
  AND f_join_time >= now() - interval '1 week'
ORDER BY f_join_time DESC
LIMIT 1;

-- ============================================
-- Step 3: 建立優化索引
-- ============================================

-- 索引策略說明:
-- 1. 使用複合索引覆蓋所有過濾條件
-- 2. 索引列順序: 選擇性高 → 選擇性低
-- 3. 包含 ORDER BY 列以避免排序
-- 4. 使用 WHERE 子句過濾減少索引大小

-- 主要索引: 玩家最近投注查詢
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_orders_wilddiggr_player_recent_bet
ON t_orders (
    f_game_type,       -- 第一層過濾: 遊戲類型
    f_loginname,       -- 第二層過濾: 玩家 (高選擇性)
    f_table_id,        -- 第三層過濾: 桌台
    f_join_time DESC   -- 排序列
)
INCLUDE (
    f_amount,          -- SELECT 需要的列
    f_status           -- WHERE 條件檢查用
)
WHERE
    f_game_type = 'StandAloneWildDigGR'  -- 部分索引: 只索引 WildDigGR
    AND f_amount != 0                     -- 過濾掉 0 金額
    AND f_status IN (4, 10);              -- 只索引完成/派彩狀態

-- 索引說明:
-- - CONCURRENTLY: 不鎖表，線上建立
-- - INCLUDE: 覆蓋索引，避免回表查詢
-- - WHERE: 部分索引，減少索引大小 50-70%

-- ============================================
-- Step 4: 驗證索引效果
-- ============================================

-- 等待索引建立完成 (可能需要 5-30 分鐘，取決於數據量)
-- 檢查索引建立進度:
SELECT
    phase,
    blocks_total,
    blocks_done,
    tuples_total,
    tuples_done
FROM pg_stat_progress_create_index
WHERE relid = 't_orders'::regclass;

-- 索引建立完成後，再次執行 EXPLAIN
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT f_amount
FROM t_orders
WHERE f_game_type = 'StandAloneWildDigGR'
  AND f_loginname = 'GMM37420ws235866475'
  AND f_table_id = 'WDGR1'
  AND f_amount != 0
  AND f_status IN (4, 10)
  AND f_join_time >= now() - interval '1 week'
ORDER BY f_join_time DESC
LIMIT 1;

-- 預期結果:
-- Before: Seq Scan on t_orders (cost=0..XXX rows=XXX) (actual time=2900ms)
-- After:  Index Scan using idx_orders_wilddiggr_player_recent_bet (actual time=10-50ms)

-- ============================================
-- Step 5: 測試多個玩家的查詢性能
-- ============================================

-- 測試 5 個不同玩家
EXPLAIN ANALYZE
SELECT f_amount
FROM t_orders
WHERE f_game_type = 'StandAloneWildDigGR'
  AND f_loginname = 'GMM45590hs295024406'
  AND f_table_id = 'WDGR1'
  AND f_amount != 0
  AND f_status IN (4, 10)
  AND f_join_time >= now() - interval '1 week'
ORDER BY f_join_time DESC
LIMIT 1;

-- ============================================
-- Step 6: 監控索引使用情況
-- ============================================

-- 檢查索引是否被使用
SELECT
    schemaname,
    tablename,
    indexname,
    idx_scan as index_scans,
    idx_tup_read as tuples_read,
    idx_tup_fetch as tuples_fetched
FROM pg_stat_user_indexes
WHERE indexname = 'idx_orders_wilddiggr_player_recent_bet';

-- 查看索引大小
SELECT
    pg_size_pretty(pg_relation_size('idx_orders_wilddiggr_player_recent_bet')) as index_size;

-- ============================================
-- Alternative: 如果表非常大，考慮分區
-- ============================================

-- 如果 t_orders 表有數千萬行，考慮按遊戲類型分區:
/*
CREATE TABLE t_orders_wilddiggr PARTITION OF t_orders
FOR VALUES IN ('StandAloneWildDigGR');

-- 在分區表上建立更簡單的索引
CREATE INDEX idx_orders_wilddiggr_partition_player
ON t_orders_wilddiggr (f_loginname, f_table_id, f_join_time DESC)
WHERE f_amount != 0 AND f_status IN (4, 10);
*/

-- ============================================
-- 維護計劃
-- ============================================

-- 定期更新統計資訊 (每週)
ANALYZE t_orders;

-- 定期重建索引 (每月，如果寫入頻繁)
-- REINDEX INDEX CONCURRENTLY idx_orders_wilddiggr_player_recent_bet;

-- ============================================
-- 回滾方案 (如果需要)
-- ============================================

-- DROP INDEX CONCURRENTLY IF EXISTS idx_orders_wilddiggr_player_recent_bet;
