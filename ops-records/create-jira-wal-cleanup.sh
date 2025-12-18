#!/bin/bash
# Create Jira OPS issue for RDS WAL Cleanup
# Using Bearer Token Authentication

echo "Creating Issue: RDS PostgreSQL WAL Cleanup"
curl -X POST "https://jira.ftgaming.cc/rest/api/2/issue" \
  -H "Authorization: Bearer NjkzODA0MTA5MjU3OrqN9yqLDHE5UK2zqx5xgHVRKb9M" \
  -H "Content-Type: application/json" \
  -d '{
    "fields": {
      "project": {"key": "OPS"},
      "summary": "RDS PostgreSQL WAL Cleanup - Remove Orphaned Debezium Replication Slot",
      "description": "h2. 目的\n清理 RDS PostgreSQL 上棄用的 Debezium replication slot，釋放 46 GB 的 WAL 堆積空間。\n\nh2. 背景\n* *RDS Instance*: bingo-prd-backstage.crrfmdeapguf.ap-east-1.rds.amazonaws.com\n* *Database*: combineddb\n* *問題*: WAL 檔案持續堆積，佔用大量磁碟空間\n* *根本原因*: 棄用的 Debezium replication slot 未清理\n\nh2. 問題診斷\n\n|| Slot 名稱 || 類型 || 狀態 || WAL 堆積 ||\n| rds_ap_east_1_db_... | physical | active | 0 bytes |\n| *t_orders_v8* | logical | *inactive* | *46 GB* |\n| t_orders_v9 | logical | active | 5.4 GB |\n\nh3. 分析結論\n# *t_orders_v8 已被棄用*: active=f, active_pid=NULL, 46 GB WAL 堆積\n# *t_orders_v9 為目前使用中*: active=t, active_pid=18014, LSN 位置更前\n# *版本迭代關係確認*: 兩者使用相同配置 (wal2json + combineddb)\n\nh2. 建議操作\n\n{code:sql}\n-- Step 1: 刪除棄用的 Slot（釋放 46 GB）\nSELECT pg_drop_replication_slot('t_orders_v8');\n\n-- Step 2: 驗證\nSELECT slot_name, pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) as wal_lag\nFROM pg_replication_slots;\n\n-- Step 3: 手動觸發 checkpoint 加速清理\nCHECKPOINT;\n{code}\n\nh2. 預期結果\n* (/) 釋放約 46 GB 磁碟空間\n* (/) WAL 目錄大小顯著減少\n* (/) 防止未來磁碟空間不足問題\n\nh2. 注意事項\n# WAL 不會立即釋放，需等待 checkpoint\n# 持續監控 t_orders_v9 的 lag（目前 5.4 GB）\n# 未來 Debezium 版本升級後應及時清理舊 slot",
      "issuetype": {"name": "Task"},
      "assignee": {"name": "lonely.h"},
      "labels": ["rds", "postgresql", "wal", "debezium", "maintenance"]
    }
  }'

echo ""
echo "---"
echo "Issue created successfully!"
echo "Documentation: ops-records/JIRA_WAL_CLEANUP.md"
