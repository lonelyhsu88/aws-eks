# EKS 資源配置分析與調整建議報告

**分析日期**: 2025-11-07  
**分析範圍**: 過去 7 天（自週一上線至今）  
**Cluster**: gemini-game-prd (ap-east-1)

---

## 📊 執行摘要

### 分析範圍
- **分析的 Pods**: 142 個
- **分析的 Containers**: 173 個
- **發現需要關注的容器**: 123 個 (71.1%)

### 問題嚴重度分布
| 優先級 | 數量 | 百分比 | 說明 |
|--------|------|--------|------|
| 🔴 **緊急** | **21** | **12.1%** | 資源使用率超過 90% 或超過 request，可能影響服務穩定性 |
| 🟡 **建議調整** | **37** | **21.4%** | 資源使用率 70-90% 或未設定 requests，建議調整以提高穩定性 |
| 🟢 **可優化** | **65** | **37.6%** | 資源使用率過低，可降低配置以提高資源利用率 |
| ✅ **正常** | **50** | **28.9%** | 配置合理，無需調整 |

---

## 🔴 關鍵發現與緊急問題

### 1. **Filebeat DaemonSet 嚴重資源不足**
**影響**: 6 個 filebeat pods（遍佈所有節點）

**問題**:
- CPU request 使用率最高達 **472%**（filebeat-mgf7w）
- CPU limit 使用率達 **94%**（接近限制，可能被 throttle）
- Memory request 使用率最高達 **97%**

**當前配置**:
```yaml
resources:
  requests:
    cpu: 100m
    memory: 200Mi
  limits:
    cpu: 500m
    memory: 500Mi
```

**建議配置**:
```yaml
resources:
  requests:
    cpu: 300m      # 增加 3 倍
    memory: 250Mi  # 增加 25%
  limits:
    cpu: 800m      # 增加 60%
    memory: 600Mi  # 增加 20%
```

**優先級**: 🔴🔴🔴 **最高優先級**  
**風險**: 
- CPU throttling 導致日誌收集延遲
- 可能遺漏關鍵日誌
- 影響可觀測性

---

### 2. **Schedule Service - 極高風險**
**影響**: schedule-prd namespace

**問題**:
- CPU request 使用率: **458%** ⚠️
- Memory request 使用率: **167%** ⚠️
- Memory limit 使用率: **99.9%** ⚠️⚠️⚠️ **即將 OOMKilled**

**當前配置**:
```yaml
resources:
  requests:
    cpu: 10m
    memory: 300Mi
  limits:
    memory: 500Mi
```

**建議配置**:
```yaml
resources:
  requests:
    cpu: 60m       # 增加 6 倍
    memory: 650Mi  # 增加 2.2 倍
  limits:
    cpu: 120m
    memory: 1Gi    # 增加 2 倍
```

**優先級**: 🔴🔴🔴 **緊急**  
**風險**: 
- **極高風險觸發 OOMKilled**
- 服務中斷
- 排程任務失敗

---

### 3. **ArgoCD Application Controller**
**影響**: CI/CD 流程

**問題**:
- CPU request 使用率: **277%**
- Memory request 使用率: **92%**

**當前配置**:
```yaml
resources:
  requests:
    cpu: 100m
    memory: 512Mi
  limits:
    cpu: 1000m
    memory: 1Gi
```

**建議配置**:
```yaml
resources:
  requests:
    cpu: 400m      # 增加 4 倍
    memory: 700Mi  # 增加 37%
  limits:
    cpu: 1000m     # 保持不變
    memory: 1Gi    # 保持不變
```

**優先級**: 🔴🔴 **高優先級**  
**風險**: 
- 部署延遲
- GitOps 同步失敗

---

### 4. **遊戲服務 Memory 配置不足**

以下遊戲服務 memory request 使用率超過 100%：

| Service | Memory 使用率 | 當前 Request | 建議 Request |
|---------|--------------|-------------|-------------|
| **luckydropcoc2** | **169%** | 200Mi | 440Mi |
| **forestteaparty** | **169%** | 380Mi | 660Mi |
| **cavebingo** | **131%** | 140Mi | 238Mi |
| **caribbeanbingo** | **123%** | 150Mi | 240Mi |
| **steampunk2** | **105%** | 190Mi | 246Mi |
| **limbone** | **102%** | 200Mi | 266Mi |

**優先級**: 🔴 **高優先級**  
**風險**: 
- 玩家體驗下降
- 遊戲服務不穩定
- 可能觸發 OOM

---

### 5. **API 服務配置問題**

| Service | 問題 | 當前 Request | 建議 |
|---------|------|-------------|------|
| **partnerapi** | Memory 202% | 40Mi | 增加到 105Mi |
| **exgameapi** | Memory 149% | 100Mi | 增加到 194Mi |
| **syncservice** | CPU 216%, Memory 136% | CPU: 100m, Mem: 200Mi | CPU: 280m, Mem: 353Mi |

---

## 🟡 建議調整項目

### 資源未設定或設定不當（37 個容器）

**主要類別**:
1. **未設定 CPU/Memory requests**: 影響 Pod 調度和 QoS 等級
2. **使用率 70-90%**: 接近上限，建議預留更多緩衝空間

**重點 Namespace**:
- `kube-system`: 多個系統組件未設定 requests
- `monitoring`: Prometheus 相關組件配置偏緊
- 多個遊戲服務: 使用率在 70-80% 之間

**建議**: 
- 為所有生產服務設定 requests 和 limits
- 使用率 > 70% 的服務增加 20-30% 緩衝空間

---

## 🟢 資源優化建議

### 過度配置的服務（65 個容器）

**特徵**:
- CPU 平均使用率 < 20%
- Memory 平均使用率 < 30%
- Request 遠大於實際需求

**Top 優化機會**:

| Namespace | Container | CPU 使用率 | 可節省 |
|-----------|-----------|-----------|--------|
| exgameapi-prd | exgameapi | 12.4% | 可降低 150m |
| argocd | redis | 4.2% | 可降低 150m |
| argocd | dex-server | 3.8% | 可降低 90m |
| istio-system | 多個 proxy | 10-15% | 總計可降低 ~500m |

**預估節省**:
- **CPU**: 約 8-10 cores（相當於 1-2 個 t3.xlarge 節點）
- **Memory**: 約 15-20Gi

**建議**: 
- 分階段調整，先調整非關鍵服務
- 調整後持續監控 1-2 週

---

## 📋 實施建議

### 🔴 Phase 1: 緊急修復（建議 24 小時內完成）

**優先順序**:
1. **schedule-prd** - Memory limit 99.9%，極高 OOM 風險
2. **filebeat DaemonSet** - 影響所有節點的日誌收集
3. **syncservice-prd** - CPU/Memory 雙高使用率

**實施步驟**:
```bash
# 1. 更新 deployment/statefulset 的 resources
kubectl edit statefulset schedule -n schedule-prd
kubectl edit daemonset filebeat-filebeat -n filebeat
kubectl edit deployment syncservice -n syncservice-prd

# 2. 驗證 pod 重啟後的資源使用
kubectl top pods -n schedule-prd
kubectl top pods -n filebeat
kubectl top pods -n syncservice-prd

# 3. 監控 5-10 分鐘，確認無異常
```

---

### 🟡 Phase 2: 重要調整（建議 1 週內完成）

**優先順序**:
1. ArgoCD application-controller
2. 遊戲服務 Memory 調整（luckydropcoc2, forestteaparty, etc.）
3. API 服務調整（partnerapi, exgameapi）
4. Istio ingress gateway

**策略**:
- 逐一調整，避免同時大量重啟
- 業務低峰期執行（建議凌晨 2-4 點）
- 每次調整後監控 30 分鐘

---

### 🟢 Phase 3: 優化調整（建議 2-4 週內完成）

**目標**: 提高整體資源利用率，降低成本

**策略**:
1. **第 1-2 週**: 調整非關鍵服務（argocd-redis, dex-server 等）
2. **第 3-4 週**: 調整 istio-proxy sidecars
3. **持續監控**: 確保調整後使用率穩定在合理範圍

**預期效果**:
- 節點 CPU 利用率提升 15-20%
- 可能減少 1-2 個節點（節省成本）
- 提高資源調度效率

---

## 🛡️ 風險評估與緩解措施

### 高風險服務

| 服務 | 當前風險 | 風險等級 | 緩解措施 |
|------|---------|---------|---------|
| schedule-prd | Memory limit 99.9%，隨時可能 OOM | 🔴🔴🔴 極高 | 立即增加 limits，設置 PDB |
| filebeat | CPU throttling 影響日誌收集 | 🔴🔴 高 | 增加 requests/limits，考慮改用 fluentd |
| 遊戲服務 | Memory 超過 request 影響調度 | 🔴 中-高 | 批次調整，設置 HPA |

---

## 📈 監控建議

### 調整後需要監控的指標

**短期監控（調整後 1-7 天）**:
```promql
# CPU throttling
rate(container_cpu_cfs_throttled_seconds_total[5m])

# Memory 接近 limit
container_memory_working_set_bytes / container_spec_memory_limit_bytes > 0.9

# OOMKill 事件
kube_pod_container_status_restarts_total

# Pod Eviction
kube_pod_status_reason{reason="Evicted"}
```

**長期監控（持續）**:
- P95 資源使用率
- 資源請求 vs 實際使用趨勢
- 節點資源碎片化程度

---

## 💡 最佳實踐建議

### 1. **資源配置原則**
- **Requests**: 基於 P95 使用量設定（確保 95% 時間內不會資源不足）
- **Limits**: 
  - CPU: 設為 requests 的 1.5-2 倍（允許 burst）
  - Memory: 設為 requests 的 1.3-1.5 倍（避免 OOM）

### 2. **Namespace 策略**
```yaml
# 為每個 namespace 設定 ResourceQuota 和 LimitRange
apiVersion: v1
kind: LimitRange
metadata:
  name: default-limits
spec:
  limits:
  - default:
      cpu: 500m
      memory: 512Mi
    defaultRequest:
      cpu: 100m
      memory: 128Mi
    type: Container
```

### 3. **HPA 配置**
對於流量波動大的服務（如遊戲服務），建議配置 HPA：
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: game-service-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: StatefulSet
    name: game-service
  minReplicas: 1
  maxReplicas: 5
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
```

### 4. **PodDisruptionBudget**
為關鍵服務設定 PDB，避免調整時服務中斷：
```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: critical-service-pdb
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: critical-service
```

---

## 📝 檢查清單

### 調整前檢查
- [ ] 確認業務低峰期時間
- [ ] 備份當前配置（使用 kubectl get ... -o yaml）
- [ ] 通知相關團隊
- [ ] 準備回滾計劃

### 調整中監控
- [ ] 監控 Pod 重啟狀態
- [ ] 檢查服務健康狀態
- [ ] 觀察資源使用變化
- [ ] 檢查應用日誌有無異常

### 調整後驗證
- [ ] 確認 Pod 穩定運行
- [ ] 驗證服務功能正常
- [ ] 觀察 1 小時資源使用
- [ ] 更新文檔

---

## 🎯 總結

### 關鍵數據
- **71%** 的容器需要資源配置調整
- **21** 個緊急問題需要立即處理
- **預估可節省** 8-10 CPU cores 和 15-20Gi Memory

### 主要問題
1. **Filebeat** 嚴重資源不足，影響日誌收集
2. **Schedule service** 即將 OOMKilled
3. 多個遊戲服務 Memory 配置不足
4. 大量服務過度配置，資源浪費

### 行動建議
1. **立即**（24 小時內）：修復 schedule 和 filebeat
2. **短期**（1 週內）：調整遊戲服務和關鍵 API
3. **中期**（1 個月內）：優化過度配置的服務
4. **長期**：建立資源配置審查機制

---

## 📎 附件

完整分析報告位於:
- 詳細報告: `/tmp/resource_analysis_report.txt`
- JSON 數據: `/tmp/resource_analysis_results.json`

**生成工具**: Claude Code + Prometheus Metrics
**分析方法**: 基於過去 7 天實際使用數據的統計分析
