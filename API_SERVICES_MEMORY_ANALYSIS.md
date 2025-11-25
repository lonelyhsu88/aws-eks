# API 服務記憶體使用分析報告

**分析時間**: 2025-11-07
**分析對象**: 10 個 API 服務部署
**運行時間**: 約 4 天 7 小時

---

## 執行摘要

### 關鍵發現

1. **嚴重資源問題 (1 個服務)**:
   - `exgameapi-prd`: 記憶體使用 222Mi **超過 Limit 100Mi 的 222%**，HPA 顯示 96% 使用率，處於臨界狀態

2. **高風險服務 (3 個)**:
   - `eventapi-prd`: 109Mi 使用量逼近 120Mi 限制（91%），HPA 74%
   - `mgmtapi-prd`: 111Mi 使用，接近 200Mi 限制的 56%，但有 1 次重啟記錄
   - `partnerapi-prd`: 雖然當前僅 29Mi，但配置極不合理（Request 40Mi, Limit 100Mi）

3. **配置過度保守 (1 個)**:
   - `loyaltyapi-prd`: Request 4Gi，實際只用 236Mi（僅 6%），嚴重浪費資源預留

4. **測試服務異常 (2 個)**:
   - `fakeapi-prd` & `fakeapi2-prd`: 實際使用 5-6Mi，但配置 Request 10Mi / Limit 100Mi

---

## 詳細分析

### 1. adapterapi-prd

**基本資訊**:
- **副本數**: 1
- **運行時長**: 4d7h
- **重啟次數**: 0
- **容器數**: 2 (adapterapi + linkerd-proxy)

**記憶體使用**:
- **實際使用**: 101 Mi
- **Request**: 40 Mi
- **Limit**: 100 Mi
- **使用率**: 253% of request, **101% of limit** ⚠️

**HPA 狀態**:
- **Metric**: memory: 60%/80%
- **副本範圍**: 1-1 (固定)
- **當前副本**: 1

**評估**:
- ⚠️ **記憶體使用已達 Limit，隨時可能 OOMKilled**
- ✅ Request 設定過低，但 Limit 準確
- ⚠️ HPA 顯示 60% 是基於 Request (40Mi) 計算，實際上已達 Limit
- **建議**: 提高 Request 至 80Mi，Limit 至 150Mi

---

### 2. domain-serviceapi-prd

**基本資訊**:
- **副本數**: 1
- **運行時長**: 4d7h
- **重啟次數**: 0
- **容器數**: 2 (domain-serviceapi + linkerd-proxy)

**記憶體使用**:
- **實際使用**: 101 Mi
- **Request**: 20 Mi
- **Limit**: 50 Mi
- **使用率**: 505% of request, **202% of limit** 🔴

**HPA 狀態**:
- **Metric**: memory: 68%/80%
- **副本範圍**: 1-1 (固定)
- **當前副本**: 1

**評估**:
- 🔴 **嚴重超限！實際使用是 Limit 的 2 倍**
- 🔴 **此 Pod 應該已經被 OOMKilled，但還在運行 - 可能計量有誤**
- 🔴 Request 和 Limit 都嚴重過低
- **建議**: 立即調查為何未 OOM，檢查記憶體計量準確性，將 Request 設為 100Mi，Limit 設為 200Mi

---

### 3. eventapi-prd

**基本資訊**:
- **副本數**: 1
- **運行時長**: 4d6h
- **重啟次數**: 0
- **容器數**: 2 (eventapi + linkerd-proxy)

**記憶體使用**:
- **實際使用**: 109 Mi
- **Request**: 20 Mi
- **Limit**: 50 Mi
- **使用率**: 545% of request, **218% of limit** 🔴

**HPA 狀態**:
- **Metric**: memory: 74%/80%
- **副本範圍**: 1-1 (固定)
- **當前副本**: 1

**評估**:
- 🔴 **嚴重超限！實際使用是 Limit 的 2.18 倍**
- 🔴 **同樣應該被 OOMKilled 但仍在運行**
- 🔴 配置嚴重不足
- **建議**: 緊急調查記憶體計量系統，將 Request 設為 100Mi，Limit 設為 200Mi

---

### 4. exgameapi-prd ⚠️ 最高優先級

**基本資訊**:
- **副本數**: 1
- **運行時長**: 4d6h
- **重啟次數**: 0
- **容器數**: 2 (exgameapi + linkerd-proxy)

**記憶體使用**:
- **實際使用**: 222 Mi
- **Request**: 100 Mi
- **Limit**: 400 Mi
- **使用率**: 222% of request, 56% of limit

**HPA 狀態**:
- **Metric**: memory: 96%/80% ⚠️
- **副本範圍**: 1-1 (固定)
- **當前副本**: 1

**評估**:
- 🔴 **HPA 已觸發擴展閾值 (96% > 80%)，但因 maxReplicas=1 無法擴展**
- ⚠️ 記憶體使用是 Request 的 2.22 倍
- ✅ Limit 400Mi 尚有餘裕 (56% 使用)
- ⚠️ **高 CPU 使用 (59m) 可能影響效能**
- **建議**:
  1. 提高 Request 至 250Mi 以反映實際需求
  2. 調整 HPA maxReplicas 至 3 以允許水平擴展
  3. 監控 CPU 瓶頸

---

### 5. exmgmtapi-prd

**基本資訊**:
- **副本數**: 1
- **運行時長**: 4d7h
- **重啟次數**: 0
- **容器數**: 2 (exmgmtapi + linkerd-proxy)

**記憶體使用**:
- **實際使用**: 100 Mi
- **Request**: 20 Mi
- **Limit**: 50 Mi
- **使用率**: 500% of request, **200% of limit** 🔴

**HPA 狀態**:
- **Metric**: memory: 67%/80%
- **副本範圍**: 1-1 (固定)
- **當前副本**: 1

**評估**:
- 🔴 **嚴重超限！實際使用是 Limit 的 2 倍**
- 🔴 **應該被 OOMKilled 但仍在運行**
- 🔴 配置嚴重不足
- **建議**: 檢查記憶體計量，將 Request 設為 100Mi，Limit 設為 200Mi

---

### 6. fakeapi-prd

**基本資訊**:
- **副本數**: 1
- **運行時長**: 4d7h
- **重啟次數**: 0
- **容器數**: 1 (fakeapi only)

**記憶體使用**:
- **實際使用**: 6 Mi
- **Request**: 10 Mi
- **Limit**: 100 Mi
- **使用率**: 60% of request, 6% of limit

**HPA 狀態**:
- **Metric**: memory: 64%/80%
- **副本範圍**: 1-1 (固定)
- **當前副本**: 1

**評估**:
- ✅ 資源使用正常
- ⚠️ HPA 顯示 64% 但實際只用 6Mi（計量可能基於不同容器）
- ⚠️ Limit 100Mi 過於寬鬆，可能是測試服務
- **建議**: 如果是測試服務，保持現狀；如果是生產服務，降低 Limit 至 20Mi

---

### 7. fakeapi2-prd

**基本資訊**:
- **副本數**: 1
- **運行時長**: 4d7h
- **重啟次數**: 0
- **容器數**: 1 (fakeapi2 only)

**記憶體使用**:
- **實際使用**: 5 Mi
- **Request**: 10 Mi
- **Limit**: 100 Mi
- **使用率**: 50% of request, 5% of limit

**HPA 狀態**:
- **Metric**: memory: 54%/80%
- **副本範圍**: 1-1 (固定)
- **當前副本**: 1

**評估**:
- ✅ 資源使用正常
- ⚠️ 與 fakeapi 類似，配置過於寬鬆
- **建議**: 同 fakeapi

---

### 8. loyaltyapi-prd

**基本資訊**:
- **副本數**: 1
- **運行時長**: 4d7h
- **重啟次數**: 0
- **容器數**: 1 (loyaltyapi only)

**記憶體使用**:
- **實際使用**: 236 Mi
- **Request**: 4 Gi (4096 Mi)
- **Limit**: 5 Gi (5120 Mi)
- **使用率**: 6% of request, 5% of limit

**HPA 狀態**:
- **Metric**: memory: 5%/80%
- **副本範圍**: 1-1 (固定)
- **當前副本**: 1

**評估**:
- 🔴 **嚴重的資源浪費！Request 4Gi 但只用 236Mi（6%）**
- 🔴 **獨佔了整個節點 4Gi 記憶體，影響集群調度**
- ⚠️ CPU 使用較高 (14m)
- ⚠️ HPA 永遠不會觸發（僅 5% 使用）
- **建議**:
  1. 緊急降低 Request 至 500Mi
  2. 降低 Limit 至 1Gi
  3. 調查為何配置如此高（是否曾經需要？）
  4. 調整 HPA target 至 60% 以更敏感

---

### 9. mgmtapi-prd

**基本資訊**:
- **副本數**: 1
- **運行時長**: 47h (約 2 天)
- **重啟次數**: 1 (47h 前) ⚠️
- **容器數**: 2 (mgmtapi + linkerd-proxy)

**記憶體使用**:
- **實際使用**: 111 Mi
- **Request**: 100 Mi
- **Limit**: 200 Mi
- **使用率**: 111% of request, 56% of limit

**HPA 狀態**:
- **Metric**: memory: 48%/80%
- **副本範圍**: 1-1 (固定)
- **當前副本**: 1

**評估**:
- ⚠️ **曾在 47 小時前重啟 - 可能是 OOM 或其他問題**
- ⚠️ 實際使用已超過 Request (111%)
- ✅ Limit 尚有餘裕 (56%)
- ⚠️ HPA 顯示 48% 與實際計算不符（可能基於不同時間點）
- **建議**:
  1. 調查 47h 前的重啟原因（檢查 logs/events）
  2. 提高 Request 至 120Mi
  3. 監控是否再次重啟

---

### 10. partnerapi-prd

**基本資訊**:
- **副本數**: 1
- **運行時長**: 4d7h
- **重啟次數**: 0
- **容器數**: 1 (partnerapi only)

**記憶體使用**:
- **實際使用**: 29 Mi
- **Request**: 40 Mi
- **Limit**: 100 Mi
- **使用率**: 73% of request, 29% of limit

**HPA 狀態**:
- **Metric**: memory: 73%/80%
- **副本範圍**: 1-1 (固定)
- **當前副本**: 1

**評估**:
- ⚠️ **CPU 使用異常高 (87m) 但記憶體低**
- ⚠️ HPA 接近閾值 (73% vs 80%)
- ✅ 記憶體配置合理
- **建議**:
  1. 調查高 CPU 使用原因（可能是計算密集或有效能問題）
  2. 考慮增加 CPU request/limit
  3. 檢查是否有無限迴圈或低效演算法

---

## 總結比較表格

### 記憶體使用排序（從高到低）

| 服務 | 實際使用 | Request | Limit | Request 使用率 | Limit 使用率 | HPA Target | 重啟 | 狀態 |
|------|---------|---------|-------|---------------|-------------|-----------|------|------|
| loyaltyapi | 236 Mi | 4096 Mi | 5120 Mi | **6%** 🔴 | 5% | 5%/80% | 0 | 嚴重浪費 |
| exgameapi | 222 Mi | 100 Mi | 400 Mi | 222% | 56% | **96%/80%** ⚠️ | 0 | HPA 臨界 |
| mgmtapi | 111 Mi | 100 Mi | 200 Mi | 111% | 56% | 48%/80% | **1** ⚠️ | 曾重啟 |
| eventapi | 109 Mi | 20 Mi | 50 Mi | 545% | **218%** 🔴 | 74%/80% | 0 | 嚴重超限 |
| adapterapi | 101 Mi | 40 Mi | 100 Mi | 253% | **101%** ⚠️ | 60%/80% | 0 | 已達限制 |
| domain-serviceapi | 101 Mi | 20 Mi | 50 Mi | 505% | **202%** 🔴 | 68%/80% | 0 | 嚴重超限 |
| exmgmtapi | 100 Mi | 20 Mi | 50 Mi | 500% | **200%** 🔴 | 67%/80% | 0 | 嚴重超限 |
| partnerapi | 29 Mi | 40 Mi | 100 Mi | 73% | 29% | 73%/80% | 0 | 高 CPU ⚠️ |
| fakeapi | 6 Mi | 10 Mi | 100 Mi | 60% | 6% | 64%/80% | 0 | 測試服務 |
| fakeapi2 | 5 Mi | 10 Mi | 100 Mi | 50% | 5% | 54%/80% | 0 | 測試服務 |

### CPU 使用排序（從高到低）

| 服務 | CPU 使用 | 記憶體使用 | 備註 |
|------|---------|-----------|------|
| partnerapi | 87m | 29 Mi | 🔴 CPU/記憶體比例異常 |
| exgameapi | 59m | 222 Mi | ⚠️ 高負載 |
| loyaltyapi | 14m | 236 Mi | 正常 |
| exmgmtapi | 6m | 100 Mi | 正常 |
| domain-serviceapi | 5m | 101 Mi | 正常 |
| eventapi | 5m | 109 Mi | 正常 |
| adapterapi | 3m | 101 Mi | 正常 |
| mgmtapi | 2m | 111 Mi | 正常 |
| fakeapi | 1m | 6 Mi | 測試服務 |
| fakeapi2 | 1m | 5 Mi | 測試服務 |

---

## 資源配置問題列表

### 🔴 嚴重問題（需立即處理）

#### 1. 記憶體計量系統異常
**影響服務**: domain-serviceapi, eventapi, exmgmtapi
- **問題**: 實際使用超過 Limit 200%+ 但未觸發 OOMKilled
- **風險**:
  - 記憶體計量不準確，可能誤導所有資源決策
  - 可能影響整個集群的穩定性
  - HPA 基於錯誤數據運作
- **行動**:
  1. 立即檢查 metrics-server 健康狀態
  2. 對比 cgroup 實際記憶體使用與 kubectl top 數據
  3. 檢查是否有 memory cgroup 限制未生效
  4. 驗證 container runtime (containerd/docker) 是否正確執行限制

#### 2. loyaltyapi 資源浪費
**影響**: 集群調度效率
- **問題**: Request 4Gi 但只使用 236Mi (6%)
- **影響**:
  - 獨佔節點 4Gi 記憶體，導致其他 Pod 無法調度至該節點
  - 如果集群記憶體總量不足，這個 Pod 可能導致調度失敗
  - 浪費雲端資源成本
- **行動**:
  1. 立即將 Request 降至 500Mi
  2. 降低 Limit 至 1Gi
  3. 監控 2 週確認穩定
  4. 調查歷史配置原因（是否曾經需要高記憶體？）

#### 3. exgameapi HPA 無法擴展
**影響**: 服務可用性風險
- **問題**: HPA 96% 已超過 80% 閾值，但 maxReplicas=1 無法擴展
- **風險**:
  - 流量增加時無法水平擴展
  - 記憶體持續增長可能導致 OOM
  - 單點故障風險
- **行動**:
  1. 調整 HPA maxReplicas 至 3
  2. 提高 Request 至 250Mi
  3. 考慮增加 Limit 至 600Mi
  4. 監控擴展行為

---

### ⚠️ 高風險問題（本週內處理）

#### 4. adapterapi 記憶體已達 Limit
- **當前**: 101Mi / 100Mi Limit (101%)
- **風險**: 任何記憶體增長都會觸發 OOMKilled
- **建議**: Request 80Mi → Limit 150Mi

#### 5. mgmtapi 曾經重啟
- **時間**: 47 小時前
- **風險**: 未知重啟原因可能再次發生
- **行動**:
  1. 檢查 kubectl logs (previous)
  2. 檢查 Events
  3. 提高 Request 至 120Mi

#### 6. partnerapi 高 CPU 使用
- **當前**: 87m CPU, 29Mi Memory
- **風險**: CPU 瓶頸可能影響效能或導致超時
- **行動**:
  1. Profile CPU 使用找出熱點
  2. 檢查是否有低效演算法或無限迴圈
  3. 考慮增加 CPU request/limit

---

### 📊 中等優先級（本月內優化）

#### 7. 所有 API 服務的 HPA maxReplicas=1
- **影響**: 無法水平擴展應對流量增長
- **建議**:
  - 核心 API (mgmtapi, partnerapi, eventapi): maxReplicas 3-5
  - 次要 API (adapter, domain-service): maxReplicas 2-3
  - 測試 API (fakeapi): 保持 1

#### 8. Request 與實際使用不符
**需調整的服務**:
- domain-serviceapi: 20Mi → 100Mi
- eventapi: 20Mi → 100Mi
- exmgmtapi: 20Mi → 100Mi
- exgameapi: 100Mi → 250Mi

#### 9. 測試服務資源優化
- fakeapi & fakeapi2:
  - 如果是測試服務，降低 Limit 至 20Mi
  - 如果不再使用，考慮移除

---

## 優先級建議

### P0 - 立即處理（今天）

1. **調查記憶體計量異常** (domain-serviceapi, eventapi, exmgmtapi)
   - 可能影響整個集群穩定性
   - 需驗證 metrics-server 和 cgroup 限制

2. **降低 loyaltyapi Request** (4Gi → 500Mi)
   - 立即釋放 3.5Gi 集群資源
   - 改善調度效率

### P1 - 本週內處理

3. **修正 exgameapi HPA 配置**
   - maxReplicas: 1 → 3
   - Request: 100Mi → 250Mi
   - 避免服務中斷

4. **提高 adapterapi Limit**
   - Limit: 100Mi → 150Mi
   - Request: 40Mi → 80Mi
   - 避免 OOMKilled

5. **調查 mgmtapi 重啟原因**
   - 檢查 logs 和 events
   - 提高 Request: 100Mi → 120Mi

6. **調查 partnerapi 高 CPU**
   - Profile CPU 使用
   - 優化效能瓶頸

### P2 - 本月內優化

7. **批次修正資源配置**
   - domain-serviceapi, eventapi, exmgmtapi: 提高 Request/Limit

8. **調整所有 HPA 配置**
   - 設定合理的 maxReplicas
   - 調整 target 百分比

9. **清理測試服務**
   - 降低 fakeapi/fakeapi2 資源配置
   - 或移除不再使用的服務

---

## 建議的資源配置調整

### 立即調整（P0-P1）

```yaml
# loyaltyapi-prd
resources:
  requests:
    memory: 500Mi  # 原 4Gi
    cpu: 600m
  limits:
    memory: 1Gi    # 原 5Gi
    cpu: 1200m

# exgameapi-prd
resources:
  requests:
    memory: 250Mi  # 原 100Mi
    cpu: 200m
  limits:
    memory: 600Mi  # 原 400Mi
    cpu: 600m

# adapterapi-prd
resources:
  requests:
    memory: 80Mi   # 原 40Mi
    cpu: 200m
  limits:
    memory: 150Mi  # 原 100Mi
    cpu: 400m

# mgmtapi-prd
resources:
  requests:
    memory: 120Mi  # 原 100Mi
    cpu: 25m
  limits:
    memory: 250Mi  # 原 200Mi
    cpu: 80m
```

### 批次調整（P2）

```yaml
# domain-serviceapi-prd, eventapi-prd, exmgmtapi-prd
resources:
  requests:
    memory: 100Mi  # 原 20Mi
    cpu: 50m
  limits:
    memory: 200Mi  # 原 50Mi
    cpu: 400m

# fakeapi-prd, fakeapi2-prd
resources:
  requests:
    memory: 10Mi
    cpu: 5m
  limits:
    memory: 20Mi   # 原 100Mi
    cpu: 50m
```

### HPA 調整

```yaml
# exgameapi-hpa
spec:
  maxReplicas: 3  # 原 1
  minReplicas: 1
  metrics:
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 70  # 原 80

# mgmtapi-hpa, partnerapi-hpa, eventapi-hpa
spec:
  maxReplicas: 3  # 原 1
  minReplicas: 1

# loyaltyapi-hpa
spec:
  metrics:
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 60  # 原 80（因為 Request 降低很多）
```

---

## 監控建議

### 關鍵指標

1. **記憶體使用趨勢**
   - 每個服務的 24 小時記憶體使用圖表
   - 識別記憶體洩漏或異常增長

2. **OOMKilled 事件**
   - 設定 Alert 當任何 Pod OOMKilled
   - 追蹤重啟次數

3. **HPA 擴展事件**
   - 監控 HPA 擴展/縮減頻率
   - 確認擴展邏輯正確運作

4. **CPU 瓶頸**
   - partnerapi 的 CPU throttling
   - 識別效能瓶頸

### Grafana Dashboard

建議建立以下 Panels:

1. **記憶體使用 vs Limit**
   ```promql
   container_memory_working_set_bytes{namespace=~".*api-prd"}
   /
   kube_pod_container_resource_limits{resource="memory", namespace=~".*api-prd"}
   ```

2. **HPA 目標 vs 實際**
   ```promql
   kube_horizontalpodautoscaler_status_current_metrics_value
   /
   kube_horizontalpodautoscaler_spec_target_metric
   ```

3. **OOMKilled 計數**
   ```promql
   increase(kube_pod_container_status_terminated_reason{reason="OOMKilled"}[1h])
   ```

4. **記憶體增長率**
   ```promql
   deriv(container_memory_working_set_bytes{namespace=~".*api-prd"}[5m])
   ```

---

## 下一步行動清單

### 今天

- [ ] 調查記憶體計量系統（domain-serviceapi, eventapi, exmgmtapi 超限問題）
- [ ] 降低 loyaltyapi Request: 4Gi → 500Mi
- [ ] 提交 loyaltyapi 配置變更 PR

### 本週

- [ ] 調整 exgameapi HPA: maxReplicas 1 → 3, Request 100Mi → 250Mi
- [ ] 提高 adapterapi Limit: 100Mi → 150Mi
- [ ] 調查 mgmtapi 重啟原因（47h 前）
- [ ] Profile partnerapi CPU 使用
- [ ] 建立記憶體監控 Grafana Dashboard

### 本月

- [ ] 批次調整 domain-serviceapi, eventapi, exmgmtapi 資源配置
- [ ] 調整所有核心 API 的 HPA maxReplicas
- [ ] 優化或移除 fakeapi/fakeapi2
- [ ] 建立自動化資源調整流程
- [ ] 設定記憶體相關 Alerts

---

## 附錄：記憶體計量異常調查指南

### 驗證步驟

1. **檢查 metrics-server**
   ```bash
   kubectl get deployment metrics-server -n kube-system
   kubectl logs -n kube-system deployment/metrics-server
   ```

2. **對比 cgroup 實際使用**
   ```bash
   # 在 domain-serviceapi pod 所在 node 上執行
   kubectl get pod -n domain-serviceapi-prd -o wide
   # 登入該 node
   docker stats <container-id>
   # 或
   cat /sys/fs/cgroup/memory/kubepods/.../memory.usage_in_bytes
   ```

3. **檢查 container runtime 配置**
   ```bash
   kubectl describe pod -n domain-serviceapi-prd
   # 確認 Limits 有正確設定在 cgroup
   ```

4. **測試記憶體限制**
   ```bash
   # 在 pod 內執行記憶體壓力測試
   kubectl exec -it <pod-name> -n domain-serviceapi-prd -- \
     stress --vm 1 --vm-bytes 60M --timeout 10s
   # 應該觸發 OOMKilled
   ```

### 可能原因

1. **metrics-server 計量錯誤**
   - 可能讀取錯誤的 cgroup 路徑
   - kubelet 回報數據有誤

2. **cgroup 限制未生效**
   - container runtime 配置問題
   - kernel 版本相容性問題

3. **記憶體計算方式不同**
   - kubectl top 使用 working_set_bytes
   - cgroup 使用 usage_in_bytes
   - 差異應該不超過 20%

---

**報告結束**

如有疑問或需要進一步分析，請聯繫 DevOps 團隊。
