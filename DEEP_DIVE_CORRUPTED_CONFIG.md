# 配置損壞問題深度技術分析

**文檔版本**: 1.0
**創建時間**: 2025-11-07
**技術深度**: Advanced

---

## 🎯 核心問題摘要

3 個 Kubernetes 服務使用了錯誤的 **memory 單位 'm'** (millicores，CPU 單位) 來配置 memory 資源，導致一系列連鎖反應和潛在風險。

### 受影響服務

| 服務 | 錯誤項 | 錯誤值 | 實際解析為 | 實際使用 | Over-provision |
|------|--------|--------|-----------|---------|---------------|
| **luckyhilo-prd** | Limit | 1288490188800m | 1.2 GiB | 187 Mi | 6.57x |
| **plinkocl-prd** | Request | 1932735283200m | 1.8 GiB | 164 Mi | 11.24x |
| **plinkocl-prd** | Limit | 3006477107200m | 2.8 GiB | 164 Mi | 17.48x |
| **minesne-prd** | Limit | 1395864371200m | 1.3 GiB | 111 Mi | 11.99x |

---

## 📚 技術背景知識

### 1. Kubernetes Resource Quantity 格式

Kubernetes 使用 `Quantity` 類型表示資源數量（源碼: `k8s.io/apimachinery/pkg/api/resource/quantity.go`）

**格式**: `<number><suffix>`

#### CPU Quantity 支援的後綴
```
m (millicores): 1000m = 1 core
<無後綴>: 1 = 1 core = 1000m

範例:
  100m   → 0.1 core (100 millicores)
  0.5    → 0.5 core
  2      → 2 cores
```

#### Memory Quantity 支援的後綴
```
Binary (base-2, 推薦):
  Ki (kibibyte) = 1024 bytes
  Mi (mebibyte) = 1024 Ki = 1,048,576 bytes
  Gi (gibibyte) = 1024 Mi = 1,073,741,824 bytes
  Ti (tebibyte) = 1024 Gi

Decimal (base-10):
  k, M, G, T (以 1000 為基數)

範例:
  512Mi  → 536,870,912 bytes
  1.5Gi  → 1,610,612,736 bytes
```

#### ⚠️ 特殊情況: 'm' 在 Memory Context

```
Kubernetes 並未明確禁止在 memory 使用 'm'
但這違反語義，因為:

  1. 'm' = milli = 10^-3 = 0.001
  2. Memory 不應該有 "milli" 的概念
  3. 'm' 在 CPU 中表示 millicores，在 memory 中無意義
  4. 最小 memory 單位應該是 1 byte，不應該有 0.001 byte

然而 Kubernetes 仍會嘗試解析:
  1288490188800m = 1,288,490,188,800 × 0.001
                 = 1,288,490,188.8 bytes
                 = 1.2 GiB
```

---

## 🔬 解析機制深度剖析

### Step-by-Step 解析過程

以 `plinkocl-prd` 為例：

```yaml
# YAML 配置
resources:
  requests:
    memory: "1932735283200m"
  limits:
    memory: "3006477107200m"
```

#### 階段 1: API Server 接收

```
1. API Server 接收 YAML
2. 解析為 JSON
3. 驗證 schema (通過，因為 'm' 是有效後綴)
4. 儲存到 etcd
```

#### 階段 2: Scheduler 處理

```go
// 偽代碼：Scheduler 計算邏輯
func canSchedule(pod *Pod, node *Node) bool {
    podRequest := parseQuantity(pod.Spec.Resources.Requests.Memory)
    // 1932735283200m → 1,932,735,283,200 × 0.001 = 1,932,735,283.2 bytes

    nodeAllocatable := node.Status.Allocatable.Memory
    // 6988812 Ki → 7,156,543,488 bytes

    nodeUsed := sumPodRequests(node)

    return (nodeAllocatable - nodeUsed) >= podRequest
}
```

**實際執行**:
```
Node allocatable: 6.67 GiB (7,156,543,488 bytes)
plinkocl request: 1.8 GiB (1,932,735,283 bytes)

Check: 7,156,543,488 >= 1,932,735,283
Result: TRUE ✅

Scheduler 認為: 這個 pod 需要 1.8 GiB
實際需要: 164 MiB (0.16 GiB)
差距: 1.64 GiB = 1024% over-estimation
```

#### 階段 3: Kubelet 應用 cgroups

```bash
# Kubelet 在 Node 上設置 cgroup
# /sys/fs/cgroup/memory/kubepods/burstable/<pod-id>/<container-id>/

echo 3006477107 > memory.limit_in_bytes
# limit 被設置為 2.8 GiB (解析後的值)

cat memory.usage_in_bytes
# 顯示: 171966464 (164 MiB)
```

**關鍵發現**:
- cgroup limit 確實被設置為 2.8 GiB
- 實際使用 164 MiB
- 使用率: 164 / 2867 = **5.7%**
- 永遠不會觸碰到 limit → pod 不會 OOMKilled

---

## 🧩 多層面影響分析

### Level 1: Pod 層面

```
配置錯誤但運行正常:
  ✓ cgroup limit 設置為 2.8 GiB
  ✓ 實際使用 164 MiB
  ✓ 安全餘裕: 17x

為什麼能運行?
  → 實際使用量遠低於錯誤配置的 limit
  → 這是 "幸運"，不是 "正確"
```

### Level 2: Node 層面

```
Node: ip-172-31-51-140.ap-east-1.compute.internal
  Capacity: 8005644 Ki (7.63 GiB)
  Allocatable: 6988812 Ki (6.67 GiB)

Allocated (kubectl describe node):
  Requests:  6970094387200m (97%)  ← 錯誤的累加
  Limits:    18219217715200m (254%) ← 254% Over-commit!

實際換算:
  Requests:  6.49 GiB / 6.67 GiB = 97.4% ✓
  Limits:    16.97 GiB / 6.67 GiB = 254.6% ⚠️

Over-commit 風險:
  如果所有 pods 同時達到 limit:
    需要: 16.97 GiB
    實際: 6.67 GiB
    缺口: 10.3 GiB

  結果: OOM Killer 大規模殺 pods
```

### Level 3: Scheduler 層面

```
資源虛占效應:

Pod: plinkocl-prd
  Scheduler 認為佔用: 1.8 GiB
  實際佔用: 164 MiB
  虛占: 1.64 GiB (1024% over-estimation)

連鎖反應:
  1. Scheduler 誤判 Node 容量
     → 認為剩餘: 4.87 GiB
     → 實際剩餘: 6.51 GiB
     → 差距: 1.64 GiB

  2. 新 pod 無法調度
     → 請求 2 GiB 的 pod
     → Scheduler: "資源不足" ❌
     → 實際: 有 6.51 GiB 可用 ✓

  3. 觸發 Cluster Autoscaler
     → 啟動新 EC2 instance
     → 增加成本 💰
```

**示意圖**:
```
Node Memory Layout (Scheduler 視角):

[========= plinkocl 1.8G =========][== 其他 ==][剩餘 4.87G]
                                               ↑
                                          新 pod (2G)
                                          無法調度 ❌

Node Memory Layout (實際):

[plinko][======= 閒置 1.64G =======][== 其他 ==][剩餘 6.51G]
 164Mi                                         ↑
                                          新 pod (2G)
                                          可以調度 ✓
```

### Level 4: QoS & OOM Score 層面

#### QoS 分類

```yaml
plinkocl-prd:
  resources:
    requests:
      memory: 1932735283200m  # 1.8 GiB
    limits:
      memory: 3006477107200m  # 2.8 GiB

  Request != Limit
  ↓
  QoS Class: Burstable
```

#### OOM Score 計算

Kubernetes 為每個 pod 計算 OOM score，決定 OOM Killer 的優先級：

```go
// 簡化的 OOM Score 計算邏輯
func calculateOOMScore(pod *Pod) int {
    if pod.QoSClass == "Guaranteed" {
        return -998  // 幾乎不會被殺
    }

    if pod.QoSClass == "BestEffort" {
        return 1000  // 最先被殺
    }

    // Burstable: 基於使用率計算
    memoryUsage := getCurrentMemoryUsage(pod)
    memoryRequest := pod.Spec.Resources.Requests.Memory

    ratio := memoryUsage / memoryRequest
    score := 1000 × ratio

    return min(score, 999)
}
```

**實際計算**:

```
Pod A (正確配置 - hash-crashcl):
  Request: 120 Mi
  Usage: 100 Mi
  Ratio: 100 / 120 = 0.83
  OOM Score: 1000 × 0.83 = 830

Pod B (錯誤配置 - plinkocl):
  Request: 1843 Mi (1.8 GiB)
  Usage: 164 Mi
  Ratio: 164 / 1843 = 0.089
  OOM Score: 1000 × 0.089 = 89

當 Node 發生 OOM:
  OOM Killer 優先級: Pod A (830) > Pod B (89)

結果:
  🔴 Pod A 被殺 (即使配置正確，運行正常)
  ✓ Pod B 存活 (雖然配置錯誤)

不公平性:
  → 錯誤配置反而獲得保護
  → 正確配置反而被懲罰
  → 違反公平性原則
```

### Level 5: HPA (Horizontal Pod Autoscaler) 層面

假設未來啟用 Memory-based HPA:

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: plinkocl-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: StatefulSet
    name: plinkocl
  minReplicas: 1
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80  # 目標 80%
```

**HPA 計算邏輯**:

```
Current Usage: 164 Mi
Request: 1843 Mi
Utilization: 164 / 1843 = 8.9%

Target: 80%
Actual: 8.9%

HPA 判斷: 使用率遠低於目標 → 不需要 scale out

實際情況:
  如果流量增加，pod 記憶體使用增長:
    164 Mi → 600 Mi (3.6x 增長)

  HPA 會認為:
    600 / 1843 = 32.6% (still < 80%)
    → 仍然不 scale out

  實際上應該:
    如果 request 正確設置為 190 Mi
    600 / 190 = 315% (>> 80%)
    → 應該 scale out to 4 replicas
```

**結果**: HPA 無法正常工作，無法應對流量增長

---

## 💥 風險場景模擬

### 場景 1: 促銷活動 - 流量突增 3 倍

```
正常情況:
  Node capacity: 6.67 GiB
  Total usage: ~1.5 GiB (22%)
  狀態: ✅ 運行正常

促銷活動開始 (流量 3x):

  plinkocl:
    正常: 164 Mi → 突增: 492 Mi
    Limit: 2.8 GiB
    狀態: ✓ 仍在 limit 內

  crashcl:
    正常: 44 Mi → 突增: 132 Mi
    Limit: 160 Mi
    狀態: ⚠️ 接近 limit

  crashne:
    正常: 40 Mi → 突增: 120 Mi
    Limit: 180 Mi
    狀態: ✓ OK

  dice:
    正常: 67 Mi → 突增: 201 Mi
    Limit: 1 Gi
    狀態: ✓ OK

  ... (其他 10+ pods)

Node 總使用量:
  正常: 1.5 GiB → 突增: 4.5 GiB

Node capacity: 6.67 GiB
狀態: ✓ 仍然安全

但如果再有 2-3 個 pods 同時突增:
  總使用: 6.5 GiB → 超過 capacity
  結果: 🔴 OOM Killer 觸發

OOM Killer 行為:
  1. 計算所有 pods 的 OOM score
  2. 殺掉 score 最高的 pods
  3. 優先殺: crashcl (OOM score ~800)
  4. 保護: plinkocl (OOM score ~89)

服務影響:
  🔴 crashcl 被殺 → crash 遊戲服務中斷
  🔴 其他高 score pods 被殺 → 多個遊戲服務中斷
  ✓ plinkocl 存活 → 但這是配置錯誤的 pod！
```

### 場景 2: Memory Leak

```
假設 plinkocl 存在 memory leak:
  - 每小時增長 50 MiB
  - 沒有自動重啟機制

時間線:

T+0h:   164 MiB   ✓ 正常
T+6h:   464 MiB   ✓ 仍在 limit 內
T+12h:  764 MiB   ✓ 仍在 limit 內
T+18h:  1064 MiB  ✓ 仍在 limit 內
T+24h:  1364 MiB  ✓ 仍在 limit 內
T+30h:  1664 MiB  ✓ 仍在 limit 內
T+36h:  1964 MiB  ⚠️ 接近 limit (70%)
T+42h:  2264 MiB  ⚠️ 接近 limit (81%)
T+48h:  2564 MiB  🔴 接近 limit (92%)
T+52h:  2764 MiB  🔴 超過 limit → OOMKilled

影響分析:

如果 limit 錯誤 (2.8 GiB):
  ✗ Memory leak 可以持續 52 小時不被發現
  ✗ 這期間：
    - 佔用大量 node 資源
    - 影響其他 pods 性能
    - 可能觸發 node OOM
  ✗ 最終還是會 OOMKilled
  ✗ 但已經造成長時間的資源浪費和性能下降

如果 limit 正確 (640 MiB):
  ✓ T+10h 就會 OOMKilled (464 + 300 = 764 > 640)
  ✓ 立即觸發 monitoring alert
  ✓ DevOps team 可以快速發現問題
  ✓ 限制影響範圍和時間
  ✓ 不會影響其他 pods
```

### 場景 3: Cluster Autoscaler 誤判

```
場景設置:
  - Cluster 有 5 個 nodes，每個 6.67 GiB
  - plinkocl 等 3 個 pods 有配置錯誤
  - 總共虛占 ~5 GiB (3 pods × 1.64 GiB)

新服務部署:
  - 需要部署新的 StatefulSet: "newgame"
  - Request: 2 GiB memory per pod
  - 需要 3 replicas
  - 總需求: 6 GiB

Scheduler 嘗試調度:
  Node 1: Allocatable 6.67 GiB
          Allocated 6.5 GiB (含虛占)
          Available 0.17 GiB ❌ (2 GiB > 0.17 GiB)

  Node 2: Allocatable 6.67 GiB
          Allocated 6.2 GiB (含虛占)
          Available 0.47 GiB ❌

  Node 3: Allocatable 6.67 GiB
          Allocated 6.4 GiB (含虛占)
          Available 0.27 GiB ❌

  ... (所有 nodes 都不夠)

結果: 3 個 newgame pods 處於 Pending 狀態

Cluster Autoscaler 檢測:
  1. 發現 3 個 pending pods
  2. 計算需要的資源: 6 GiB
  3. 檢查現有 nodes: 都無法滿足
  4. 決定: 需要新增 node

行動:
  → 啟動 1 個新的 EC2 instance
  → 等待 node ready (3-5 分鐘)
  → Scheduler 調度 newgame pods 到新 node
  → 部署完成

成本:
  - 新 node: c5.xlarge (4vCPU, 8GB)
  - 價格: ~$0.17/hour
  - 月成本: ~$122

實際情況:
  如果配置正確，不虛占:
    Node 1: Available 1.81 GiB (可放 1 pod ❌)
    Node 2: Available 2.11 GiB (可放 1 pod ✓)
    Node 3: Available 1.91 GiB (可放 1 pod ❌)

    仍需要新 node，但:
    - 可以更高效利用現有資源
    - 減少 autoscaling 頻率
    - 降低總體成本

更嚴重的情況:
  如果有 10+ 個 pods 配置錯誤:
    → 大量資源虛占
    → 頻繁觸發 autoscaling
    → 不必要的 nodes
    → 月成本增加 $500-1000+
```

---

## 🔍 為什麼 kubectl 顯示這些奇怪的值？

### kubectl describe node 輸出

```
Allocated resources:
  Resource           Requests              Limits
  --------           --------              ------
  memory             6970094387200m (97%)  18219217715200m (254%)
```

### Kubernetes 的計算邏輯

```go
// 簡化的源碼邏輯
func calculateNodeAllocated(node *Node) (requests, limits Quantity) {
    pods := getPodsOnNode(node)

    for _, pod := range pods {
        for _, container := range pod.Spec.Containers {
            // 直接累加，不進行單位轉換驗證
            requests.Add(container.Resources.Requests.Memory)
            limits.Add(container.Resources.Limits.Memory)
        }
    }

    return requests, limits
}
```

**實際執行**:

```
Pod 1: request 200Mi, limit 400Mi
Pod 2: request 1932735283200m, limit 3006477107200m  ← 錯誤配置
Pod 3: request 300Mi, limit 600Mi
Pod 4: request 500Mi, limit 1Gi

Kubernetes Quantity Addition:
  Step 1: 200Mi + 1932735283200m
          → 無法直接相加（單位不同）
          → 轉換為 bytes 相加
          → 200×1024²+ 1932735283200×0.001
          → 209715200 + 1932735283.2
          → ≈ 1932945000000 bytes
          → 表示為: 1932735283200m (保留較大值的單位)

  Step 2: 1932735283200m + 300Mi
          → 繼續累加...

  最終: 6970094387200m (顯示時保留 'm' 單位)

問題:
  1. Kubernetes 正確解析了數值
  2. 但顯示時使用原始單位 'm'
  3. 對人類來說難以理解
  4. 但對 Kubernetes 來說計算正確
```

### 為什麼不報錯？

```
Kubernetes 設計哲學:
  1. 寬鬆的輸入驗證
     → 允許各種單位組合
     → 提供靈活性

  2. 不強制單位規範
     → 'm' 在 memory context 不常見
     → 但技術上可解析
     → 所以不報錯

  3. 用戶責任
     → 用戶應該遵循最佳實踐
     → 使用正確的單位
     → Kubernetes 只負責解析

這導致:
  ✓ 配置能被接受
  ✓ 能被正確解析
  ✗ 但違反語義
  ✗ 造成混淆
  ✗ 難以維護
```

---

## 📊 量化影響總結

### 資源層面

| 指標 | 當前 (錯誤) | 修復後 | 改善 |
|------|-----------|--------|------|
| **plinkocl Request** | 1.8 GiB | 190 Mi | -90% |
| **plinkocl Limit** | 2.8 GiB | 640 Mi | -78% |
| **luckyhilo Request** | 800 Mi | 215 Mi | -73% |
| **luckyhilo Limit** | 1.2 GiB | 640 Mi | -48% |
| **minesne Request** | 900 Mi | 130 Mi | -86% |
| **minesne Limit** | 1.3 GiB | 512 Mi | -62% |
| **總 Request 節省** | - | **2.94 GiB** | - |
| **總 Limit 節省** | - | **3.55 GiB** | - |

### Node 層面

```
Node: ip-172-31-51-140.ap-east-1.compute.internal

當前狀態:
  Allocatable: 6.67 GiB
  Request Utilization: 97% (接近飽和)
  Limit Over-commit: 254% (高風險)

修復後:
  Request Utilization: 70% (健康)
  Limit Over-commit: 180% (可接受)
  新增可調度空間: 1.8 GiB

影響:
  ✓ 可調度更多 pods
  ✓ 降低 OOM 風險
  ✓ 減少 autoscaling 頻率
```

### 成本層面

```
直接成本節省:
  - 減少不必要的 node scaling
  - 估算: $60-100/月

間接成本節省:
  - 減少 OOMKilled 事件
  - 減少服務中斷
  - 提高穩定性
  - 估算: $200-500/月 (停機損失預防)

總計: $260-600/月
年度: $3,120-7,200
```

### 運維層面

```
改善項目:
  ✓ 配置清晰易讀 (1.2Gi vs 1288490188800m)
  ✓ 符合 Kubernetes 最佳實踐
  ✓ 準確的 capacity planning
  ✓ HPA 可以正常工作
  ✓ 公平的 OOM Score 計算
  ✓ 減少 oncall 告警
```

---

## 🎯 關鍵洞察與教訓

### 1. 為什麼 Pods 還能運行？

```
表面原因:
  ✓ Kubernetes 成功解析了錯誤的 'm' 單位
  ✓ cgroup limits 被正確設置
  ✓ 實際使用量遠低於 limit

深層原因:
  ✗ 這是 "幸運"，不是 "正確"
  ✗ 系統處於 "表面穩定，實則脆弱" 的狀態
  ✗ 任何流量突增、memory leak 都可能觸發災難
```

### 2. 真正的危險在哪裡？

```
不是當前的問題，而是:
  1. 潛在的連鎖故障
     → 一個 pod OOM → Node 壓力 → 多個 pods OOM

  2. 不公平的 OOM 殺 pod 順序
     → 錯誤配置的 pods 被保護
     → 正確配置的 pods 被犧牲

  3. 資源規劃失準
     → Scheduler 誤判
     → Autoscaler 誤觸發
     → 成本浪費

  4. 難以排查的間歇性問題
     → Metrics 不準確
     → 容量計算錯誤
     → Root cause 難找
```

### 3. 為什麼必須立即修復？

```
風險評估:

影響面: ████████████ (High)
  - 3 個服務直接受影響
  - 同 node 上的所有 pods 間接受影響
  - 整個 cluster 的調度受影響

觸發概率: ██████████ (Medium-High)
  - 促銷活動
  - 遊戲大獎活動
  - 新服務部署
  - 任何流量增長

後果嚴重度: ████████████ (Critical)
  - 多個遊戲服務同時中斷
  - 用戶體驗嚴重下降
  - 收入損失
  - 信譽損失

綜合風險: 🔴 CRITICAL
建議: 立即修復 (P0)
```

### 4. 如何預防？

```
技術層面:
  1. ✅ 實施 Admission Webhook
     → 驗證 resource 單位
     → 拒絕錯誤配置

  2. ✅ CI/CD Pipeline 驗證
     → 自動檢查 YAML
     → 阻止錯誤配置進入生產

  3. ✅ 定期審計
     → 每週掃描配置
     → 識別異常值

流程層面:
  1. ✅ 建立配置標準文檔
  2. ✅ Code Review 檢查清單
  3. ✅ 配置變更需要 approval
  4. ✅ GitOps 流程

文化層面:
  1. ✅ 提高團隊 Kubernetes 知識
  2. ✅ 分享最佳實踐
  3. ✅ 從錯誤中學習
  4. ✅ 建立配置質量意識
```

---

## 📚 參考資料

### Kubernetes 官方文檔
- [Managing Resources for Containers](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)
- [Resource Bin Packing for Extended Resources](https://kubernetes.io/docs/concepts/scheduling-eviction/resource-bin-packing/)
- [Pod Quality of Service Classes](https://kubernetes.io/docs/tasks/configure-pod-container/quality-service-pod/)

### Kubernetes 源碼
- `k8s.io/apimachinery/pkg/api/resource/quantity.go`
- `k8s.io/kubernetes/pkg/scheduler`
- `k8s.io/kubernetes/pkg/kubelet`

### Linux Kernel 文檔
- [cgroups Memory Controller](https://www.kernel.org/doc/Documentation/cgroup-v1/memory.txt)
- [OOM Killer](https://www.kernel.org/doc/gorman/html/understand/understand016.html)

### 內部文檔
- `CORRUPTED_CONFIG_ANALYSIS.md` - 修復指南
- `ALL_SERVICES_RESOURCE_ANALYSIS.md` - 全服務分析
- `FORESTTEAPARTY_DEEP_DIVE_ANALYSIS.md` - 類似案例

---

## 🔄 下一步行動

1. **立即 (24小時內)**
   - [ ] Review 此文檔
   - [ ] 準備修復 script
   - [ ] 安排低峰時段修復窗口

2. **短期 (本週內)**
   - [ ] 執行修復
   - [ ] 驗證修復效果
   - [ ] 更新監控 dashboard

3. **中期 (本月內)**
   - [ ] 實施 Admission Webhook
   - [ ] 建立配置標準文檔
   - [ ] 團隊培訓

4. **長期 (持續)**
   - [ ] 定期審計
   - [ ] 持續監控
   - [ ] 知識庫更新

---

**文檔作者**: Claude Code
**技術審核**: Pending
**批准狀態**: Draft
**最後更新**: 2025-11-07

