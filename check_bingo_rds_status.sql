-- ============================================
-- Bingo RDS 狀況檢查腳本
-- ============================================
-- 資料庫：bingo-prd-replica
-- 日期：2025-11-10
-- 目的：全面檢查 RDS 當前狀態
-- ============================================

\echo '=========================================='
\echo '  Bingo RDS Status Check'
\echo '  Date: 2025-11-10'
\echo '=========================================='

-- ============================================
-- Part 1：連線狀態分析
-- ============================================

\echo ''
\echo '========== 1. 總連線數統計 =========='
SELECT
    count(*) as total_sessions,
    count(*) FILTER (WHERE state = 'active') as active_sessions,
    count(*) FILTER (WHERE state = 'idle') as idle_sessions,
    count(*) FILTER (WHERE state = 'idle in transaction') as idle_in_tx,
    count(*) FILTER (WHERE state = 'idle in transaction (aborted)') as idle_in_tx_aborted
FROM pg_stat_activity
WHERE pid != pg_backend_pid();

\echo ''
\echo '========== 2. 按資料庫分組的連線數 =========='
SELECT
    datname as database,
    state,
    count(*) as session_count,
    max(now() - state_change) as max_idle_time
FROM pg_stat_activity
WHERE pid != pg_backend_pid()
GROUP BY datname, state
ORDER BY session_count DESC;

\echo ''
\echo '========== 3. 長時間運行的查詢 (>30秒) =========='
SELECT
    pid,
    usename,
    datname,
    application_name,
    state,
    now() - query_start as duration,
    left(query, 100) as query_preview
FROM pg_stat_activity
WHERE state = 'active'
  AND now() - query_start > interval '30 seconds'
  AND pid != pg_backend_pid()
ORDER BY query_start
LIMIT 20;

\echo ''
\echo '========== 4. Idle In Transaction 連線詳情 =========='
SELECT
    pid,
    usename,
    datname,
    application_name,
    now() - state_change as idle_duration,
    now() - xact_start as tx_duration,
    left(query, 80) as last_query
FROM pg_stat_activity
WHERE state LIKE 'idle in transaction%'
  AND pid != pg_backend_pid()
ORDER BY state_change
LIMIT 20;

-- ============================================
-- Part 2：資料庫效能指標
-- ============================================

\echo ''
\echo '========== 5. 當前資料庫大小 =========='
SELECT
    datname,
    pg_size_pretty(pg_database_size(datname)) as database_size
FROM pg_database
WHERE datname NOT IN ('template0', 'template1', 'rdsadmin')
ORDER BY pg_database_size(datname) DESC;

\echo ''
\echo '========== 6. Top 10 最大的表 =========='
SELECT
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as total_size,
    pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) as table_size,
    pg_size_pretty(pg_indexes_size(schemaname||'.'||tablename)) as indexes_size
FROM pg_tables
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC
LIMIT 10;

\echo ''
\echo '========== 7. t_bingo_orders 表狀態 =========='
SELECT
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size('t_bingo_orders')) as total_size,
    (SELECT count(*) FROM t_bingo_orders) as total_rows,
    (SELECT count(*) FROM t_bingo_orders WHERE f_join_time >= current_date - interval '7 days') as recent_7d_rows,
    (SELECT count(*) FROM t_bingo_orders WHERE f_join_time >= current_date - interval '1 day') as recent_1d_rows
FROM pg_tables
WHERE tablename = 't_bingo_orders'
LIMIT 1;

-- ============================================
-- Part 3：索引狀態檢查
-- ============================================

\echo ''
\echo '========== 8. t_bingo_orders 現有索引 =========='
SELECT
    schemaname,
    tablename,
    indexname,
    pg_size_pretty(pg_relation_size(indexrelid)) as index_size,
    idx_scan as index_scans,
    idx_tup_read as tuples_read,
    idx_tup_fetch as tuples_fetched
FROM pg_stat_user_indexes
WHERE tablename = 't_bingo_orders'
ORDER BY indexname;

\echo ''
\echo '========== 9. t_bingo_orders 索引詳細定義 =========='
SELECT
    indexname,
    indexdef
FROM pg_indexes
WHERE tablename = 't_bingo_orders'
ORDER BY indexname;

\echo ''
\echo '========== 10. 缺失索引的表（Sequential Scans > 1000） =========='
SELECT
    schemaname,
    tablename,
    seq_scan as sequential_scans,
    seq_tup_read as rows_read_by_seq_scan,
    idx_scan as index_scans,
    pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) as table_size,
    CASE
        WHEN seq_scan = 0 THEN 0
        ELSE ROUND((100.0 * idx_scan / (seq_scan + idx_scan))::numeric, 2)
    END as index_usage_pct
FROM pg_stat_user_tables
WHERE seq_scan > 1000
  AND schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY seq_scan DESC
LIMIT 15;

-- ============================================
-- Part 4：查詢效能分析
-- ============================================

\echo ''
\echo '========== 11. 最慢的查詢（需要 pg_stat_statements）=========='
-- 注意：如果沒有啟用 pg_stat_statements 擴展，這個查詢會失敗
SELECT
    substring(query, 1, 80) as query_preview,
    calls,
    ROUND(mean_exec_time::numeric, 2) as avg_time_ms,
    ROUND(max_exec_time::numeric, 2) as max_time_ms,
    ROUND(total_exec_time::numeric, 2) as total_time_ms
FROM pg_stat_statements
WHERE query NOT LIKE '%pg_stat_statements%'
  AND query NOT LIKE '%pg_catalog%'
ORDER BY mean_exec_time DESC
LIMIT 15;

-- ============================================
-- Part 5：Lock 和 Blocking 分析
-- ============================================

\echo ''
\echo '========== 12. 當前 Locks =========='
SELECT
    locktype,
    database,
    relation::regclass,
    mode,
    count(*) as lock_count
FROM pg_locks
WHERE database IS NOT NULL
GROUP BY locktype, database, relation, mode
ORDER BY lock_count DESC
LIMIT 20;

\echo ''
\echo '========== 13. Blocking Queries =========='
SELECT
    blocked_locks.pid AS blocked_pid,
    blocked_activity.usename AS blocked_user,
    blocking_locks.pid AS blocking_pid,
    blocking_activity.usename AS blocking_user,
    blocked_activity.query AS blocked_statement,
    blocking_activity.query AS blocking_statement
FROM pg_catalog.pg_locks blocked_locks
JOIN pg_catalog.pg_stat_activity blocked_activity ON blocked_activity.pid = blocked_locks.pid
JOIN pg_catalog.pg_locks blocking_locks
    ON blocking_locks.locktype = blocked_locks.locktype
    AND blocking_locks.database IS NOT DISTINCT FROM blocked_locks.database
    AND blocking_locks.relation IS NOT DISTINCT FROM blocked_locks.relation
    AND blocking_locks.page IS NOT DISTINCT FROM blocked_locks.page
    AND blocking_locks.tuple IS NOT DISTINCT FROM blocked_locks.tuple
    AND blocking_locks.virtualxid IS NOT DISTINCT FROM blocked_locks.virtualxid
    AND blocking_locks.transactionid IS NOT DISTINCT FROM blocked_locks.transactionid
    AND blocking_locks.classid IS NOT DISTINCT FROM blocked_locks.classid
    AND blocking_locks.objid IS NOT DISTINCT FROM blocked_locks.objid
    AND blocking_locks.objsubid IS NOT DISTINCT FROM blocked_locks.objsubid
    AND blocking_locks.pid != blocked_locks.pid
JOIN pg_catalog.pg_stat_activity blocking_activity ON blocking_activity.pid = blocking_locks.pid
WHERE NOT blocked_locks.granted;

-- ============================================
-- Part 6：RDS 特定資訊
-- ============================================

\echo ''
\echo '========== 14. PostgreSQL 版本和配置 =========='
SHOW server_version;
SHOW max_connections;
SHOW shared_buffers;
SHOW effective_cache_size;
SHOW work_mem;
SHOW maintenance_work_mem;

\echo ''
\echo '========== 15. 複寫延遲（Replica Lag）=========='
-- 僅在 replica 上有效
SELECT
    CASE
        WHEN pg_is_in_recovery() THEN
            EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp()))::int
        ELSE
            0
    END as replication_lag_seconds;

\echo ''
\echo '========== 16. 資料庫統計資訊最後更新時間 =========='
SELECT
    schemaname,
    tablename,
    last_vacuum,
    last_autovacuum,
    last_analyze,
    last_autoanalyze,
    n_live_tup as live_rows,
    n_dead_tup as dead_rows
FROM pg_stat_user_tables
WHERE tablename IN ('t_bingo_orders', 't_cus_trans')
ORDER BY tablename;

\echo ''
\echo '=========================================='
\echo '  檢查完成'
\echo '=========================================='
