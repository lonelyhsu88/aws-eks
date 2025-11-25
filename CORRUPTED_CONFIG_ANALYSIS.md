# 配置損壞服務詳細分析與修復指南

**發現時間**: 2025-11-07
**影響服務數**: 3 個
**嚴重度**: 🔴 **P0 - Critical**

---

## 📋 執行摘要

在 EKS 集群資源分析中，發現 **3 個服務使用了錯誤的 memory 單位**，導致配置難以閱讀、維護，並可能在未來的 Kubernetes 版本中產生不可預期的行為。

### 受影響的服務

| 服務 | 錯誤配置項 | 錯誤值 | Kubernetes 解析為 | 實際使用 | 過度配置 |
|------|-----------|--------|------------------|---------|---------|
| **luckyhilo-prd** | Memory Limit | 1288490188800m | 1.2 GiB | 187Mi | 6.57x |
| **plinkocl-prd** | Memory Request | 1932735283200m | 1.8 GiB | 164Mi | 11.24x |
| **plinkocl-prd** | Memory Limit | 3006477107200m | 2.8 GiB | 164Mi | 17.48x |
| **minesne-prd** | Memory Limit | 1395864371200m | 1.3 GiB | 111Mi | 11.99x |

---

## 🔍 問題詳細說明

### 1. luckyhilo-prd

#### 當前配置
```yaml
resources:
  requests:
    cpu: 150m
    memory: 800Mi          # ✅ 正確
  limits:
    cpu: 280m
    memory: 1288490188800m # ❌ 錯誤！使用了 'm' 單位
```

#### 問題分析
- **錯誤**: Memory limit 使用了 `1288490188800m`
- **'m' 是 CPU 單位**: millicores (千分之一核心)，不應用於 memory
- **Kubernetes 解析**: 將 'm' 解析為 'milli' (0.001)
  ```
  1288490188800m = 1,288,490,188,800 × 0.001
                 = 1,288,490,188.8 bytes
                 = 1,228.8 MiB
                 = 1.2 GiB
  ```
- **實際使用**: 187Mi
- **過度配置**: 1,228.8 MiB / 187 MiB = **6.57 倍**

#### 運行狀態
```
Pod: luckyhilo-0
Status: Running (4d7h)
Restarts: 0
IP: 172.31.55.219
Node: ip-172-31-54-200.ap-east-1.compute.internal
```
✅ 雖然配置錯誤，但 pod 仍然正常運行

#### 推測原因
可能有人想配置 `1.2Gi`，但錯誤地：
1. 計算出 bytes 數值: 1.2 × 1024³ = 1,288,490,188,800 bytes
2. 誤加了 'm' 單位: `1288490188800m`

---

### 2. plinkocl-prd ⚠️ **最嚴重**

#### 當前配置
```yaml
resources:
  requests:
    cpu: 120m
    memory: 1932735283200m # ❌ 錯誤！Request 就錯了
  limits:
    cpu: 200m
    memory: 3006477107200m # ❌ 錯誤！Limit 也錯了
```

#### 問題分析

**Memory Request**:
- 錯誤值: `1932735283200m`
- Kubernetes 解析為:
  ```
  1932735283200m = 1,932,735,283,200 × 0.001
                 = 1,932,735,283.2 bytes
                 = 1,843.2 MiB
                 = 1.8 GiB
  ```
- 實際使用: 164Mi
- 過度配置: 1,843.2 MiB / 164 MiB = **11.24 倍**

**Memory Limit**:
- 錯誤值: `3006477107200m`
- Kubernetes 解析為:
  ```
  3006477107200m = 3,006,477,107,200 × 0.001
                 = 3,006,477,107.2 bytes
                 = 2,867.2 MiB
                 = 2.8 GiB
  ```
- 實際使用: 164Mi
- 過度配置: 2,867.2 MiB / 164 MiB = **17.48 倍**

#### 運行狀態
```
Pod: plinkocl-0
Status: Running (4d7h)
Restarts: 0
IP: 172.31.51.113
Node: ip-172-31-51-140.ap-east-1.compute.internal
```
✅ 雖然配置錯誤，但 pod 仍然正常運行

#### 影響最嚴重的原因
這是唯一一個 **Request 和 Limit 都配置錯誤** 的服務：
- **Node Scheduler** 會基於錯誤的 Request (1.8 GiB) 進行調度
- 佔用了大量 node 資源配額，但實際只用 164Mi
- 導致其他 pods 無法調度到該 node（資源假性不足）

#### 推測原因
可能想配置 `1.8Gi` request 和 `2.8Gi` limit，但轉換錯誤

---

### 3. minesne-prd

#### 當前配置
```yaml
resources:
  requests:
    cpu: 100m
    memory: 900Mi          # ✅ 正確
  limits:
    cpu: 170m
    memory: 1395864371200m # ❌ 錯誤！使用了 'm' 單位
```

#### 問題分析
- **錯誤**: Memory limit 使用了 `1395864371200m`
- **Kubernetes 解析**:
  ```
  1395864371200m = 1,395,864,371,200 × 0.001
                 = 1,395,864,371.2 bytes
                 = 1,331.2 MiB
                 = 1.3 GiB
  ```
- **實際使用**: 111Mi
- **過度配置**: 1,331.2 MiB / 111 MiB = **11.99 倍**

#### 運行狀態
```
Pod: minesne-0
Status: Running (4d7h)
Restarts: 4 (4d7h ago)  # ⚠️ 注意有 4 次重啟
IP: 172.31.51.239
Node: ip-172-31-51-189.ap-east-1.compute.internal
```
⚠️ 有重啟記錄，需要進一步調查

#### Request 合理但過高
- Request: 900Mi
- 實際使用: 111Mi
- Request 使用率: 12.3% (嚴重過度配置)

#### 推測原因
可能想配置 `1.3Gi` limit，但轉換錯誤

---

## 🎯 Kubernetes 單位系統說明

### ✅ 正確的 Memory 單位

| 單位 | 名稱 | 換算 | 範例 |
|-----|------|------|------|
| Ki | kibibyte | 1024 bytes | 512Ki |
| Mi | mebibyte | 1024 Ki | 256Mi |
| Gi | gibibyte | 1024 Mi | 2Gi |
| Ti | tebibyte | 1024 Gi | 1Ti |
| k | kilobyte | 1000 bytes | 500k |
| M | megabyte | 1000 k | 100M |
| G | gigabyte | 1000 M | 5G |

### ❌ 錯誤的 Memory 單位

| 單位 | 名稱 | 正確用途 | 錯誤用途 |
|-----|------|---------|---------|
| m | millicores | ✅ CPU: `100m` = 0.1 core | ❌ Memory: `1288490188800m` |

### 🔧 Kubernetes 如何解析 'm' 在 Memory Context

根據 Kubernetes 源碼 (`k8s.io/apimachinery/pkg/api/resource`):

```go
// 解析邏輯 (簡化版)
if unit == "m" {
    // 'm' 被解析為 'milli' = 0.001
    value = number × 0.001
}
```

**範例**:
```yaml
memory: 1288490188800m
# ↓ Kubernetes 解析為
# 1288490188800 × 0.001 = 1,288,490,188.8 bytes = 1.2 GiB
```

雖然 Kubernetes **能夠解析**這些值，但這是：
- ❌ 非標準用法
- ❌ 違反 Kubernetes 最佳實踐
- ❌ 配置難以閱讀和理解
- ❌ 可能在未來版本中行為改變

---

## 💥 實際影響分析

### 1. Node 資源分配影響

這些錯誤配置會影響 Node 的資源分配計算：

```
plinkocl-prd 實際佔用 Node 資源:
  Request: 1.8 GiB (但實際只用 164Mi)
  Limit: 2.8 GiB (但實際只用 164Mi)

結果:
  ✓ Node 認為已分配 1.8 GiB request
  ✓ Node 認為可能使用 2.8 GiB limit
  ✗ 實際只用了 164Mi

影響:
  → Node 資源被虛占
  → 其他 pods 無法調度（資源假性不足）
  → 集群容量被浪費
```

### 2. 成本影響

| 服務 | 錯誤配置 | 實際使用 | 浪費 | 月成本浪費估算 |
|------|---------|---------|------|--------------|
| luckyhilo-prd | 1.2 GiB limit | 187Mi | 1,041Mi | ~$8-10 |
| plinkocl-prd | 1.8 GiB request + 2.8 GiB limit | 164Mi | 4,546Mi | ~$35-40 |
| minesne-prd | 900Mi request + 1.3 GiB limit | 111Mi | 2,120Mi | ~$16-20 |
| **總計** | | | **7,707Mi** | **~$59-70/月** |

*估算基於 AWS EKS 價格，僅供參考*

### 3. HPA 影響

雖然這 3 個服務目前沒有啟用 CPU-based HPA，但如果未來啟用 Memory-based HPA：

```yaml
# 假設啟用 Memory HPA
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
spec:
  metrics:
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80  # 目標 80%
```

**plinkocl-prd 為例**:
- Request: 1.8 GiB
- 實際使用: 164Mi
- HPA 計算: 164Mi / 1843Mi = **8.9%** (遠低於 80% 目標)
- 結果: HPA **永遠不會 scale out**，即使實際需要更多 pods

### 4. 集群穩定性影響

**Node Over-Commit 風險**:
```
假設 Node 有 16 GiB memory:

正確配置下可以調度的 pods:
  16 GiB / 200Mi (實際使用) = 80 pods

錯誤配置下可以調度的 pods:
  16 GiB / 1.8 GiB (plinkocl request) = 8 pods

結果:
  → 集群容量利用率降低 90%
  → Node 資源虛占嚴重
  → 需要更多 nodes (增加成本)
```

---

## 🔧 修復方案

### 階段 1: 立即修復 (優先級 P0)

#### 方案 A: 使用 kubectl patch (推薦 - 快速)

```bash
# 1. 修復 luckyhilo-prd
kubectl patch statefulset luckyhilo -n luckyhilo-prd --type='json' -p='[
  {"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/memory", "value": "215Mi"},
  {"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/memory", "value": "640Mi"}
]'

# 2. 修復 plinkocl-prd (最嚴重)
kubectl patch statefulset plinkocl -n plinkocl-prd --type='json' -p='[
  {"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/memory", "value": "190Mi"},
  {"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/memory", "value": "640Mi"}
]'

# 3. 修復 minesne-prd
kubectl patch statefulset minesne -n minesne-prd --type='json' -p='[
  {"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/memory", "value": "130Mi"},
  {"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/memory", "value": "512Mi"}
]'
```

#### 方案 B: 編輯 YAML 檔案 (建議 - GitOps)

如果你的配置在 Git repository 中：

**luckyhilo-prd**:
```yaml
# Before
resources:
  limits:
    memory: 1288490188800m  # ❌
  requests:
    memory: 800Mi

# After
resources:
  limits:
    memory: 640Mi           # ✅ 修復
  requests:
    memory: 215Mi           # ✅ 調整為更合理的值
```

**plinkocl-prd**:
```yaml
# Before
resources:
  limits:
    memory: 3006477107200m  # ❌
  requests:
    memory: 1932735283200m  # ❌

# After
resources:
  limits:
    memory: 640Mi           # ✅ 修復
  requests:
    memory: 190Mi           # ✅ 修復
```

**minesne-prd**:
```yaml
# Before
resources:
  limits:
    memory: 1395864371200m  # ❌
  requests:
    memory: 900Mi

# After
resources:
  limits:
    memory: 512Mi           # ✅ 修復
  requests:
    memory: 130Mi           # ✅ 調整為更合理的值
```

### 修復後的配置理由

| 服務 | 實際使用 | 新 Request | 新 Limit | Request 理由 | Limit 理由 |
|------|---------|-----------|---------|------------|-----------|
| luckyhilo | 187Mi | 215Mi | 640Mi | 實際 × 1.15 | 實際 × 3.4 (充足 buffer) |
| plinkocl | 164Mi | 190Mi | 640Mi | 實際 × 1.16 | 實際 × 3.9 (充足 buffer) |
| minesne | 111Mi | 130Mi | 512Mi | 實際 × 1.17 | 實際 × 4.6 (充足 buffer) |

**設計原則**:
- **Request**: 略高於實際使用 (15-17%)，確保 pod 能獲得足夠資源
- **Limit**: 提供 3.4-4.6x buffer，應對流量突增、memory leak 等情況
- **統一標準**: 使用清晰的 Mi/Gi 單位

---

## 📋 實施計劃

### Pre-flight 檢查

```bash
# 1. 備份當前配置
kubectl get statefulset luckyhilo -n luckyhilo-prd -o yaml > luckyhilo-backup-$(date +%Y%m%d-%H%M%S).yaml
kubectl get statefulset plinkocl -n plinkocl-prd -o yaml > plinkocl-backup-$(date +%Y%m%d-%H%M%S).yaml
kubectl get statefulset minesne -n minesne-prd -o yaml > minesne-backup-$(date +%Y%m%d-%H%M%S).yaml

# 2. 檢查 pod 當前狀態
kubectl get pods -n luckyhilo-prd
kubectl get pods -n plinkocl-prd
kubectl get pods -n minesne-prd

# 3. 檢查是否有活躍的遊戲連接 (如適用)
# 建議在低峰時段進行修復
```

### 實施步驟 (建議在低峰時段)

```bash
# Step 1: 修復 plinkocl-prd (最嚴重，優先處理)
echo "=== 修復 plinkocl-prd ==="
kubectl patch statefulset plinkocl -n plinkocl-prd --type='json' -p='[
  {"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/memory", "value": "190Mi"},
  {"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/memory", "value": "640Mi"}
]'

# 等待 pod 重啟並 ready
kubectl rollout status statefulset/plinkocl -n plinkocl-prd --timeout=5m

# 驗證 pod 健康
kubectl get pods -n plinkocl-prd
kubectl top pod -n plinkocl-prd

# 檢查 logs 確認無錯誤
kubectl logs -n plinkocl-prd plinkocl-0 --tail=50

echo "等待 10 分鐘觀察穩定性..."
sleep 600

# Step 2: 修復 minesne-prd
echo "=== 修復 minesne-prd ==="
kubectl patch statefulset minesne -n minesne-prd --type='json' -p='[
  {"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/memory", "value": "130Mi"},
  {"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/memory", "value": "512Mi"}
]'

kubectl rollout status statefulset/minesne -n minesne-prd --timeout=5m
kubectl get pods -n minesne-prd
kubectl top pod -n minesne-prd

echo "等待 10 分鐘觀察穩定性..."
sleep 600

# Step 3: 修復 luckyhilo-prd
echo "=== 修復 luckyhilo-prd ==="
kubectl patch statefulset luckyhilo -n luckyhilo-prd --type='json' -p='[
  {"op": "replace", "path": "/spec/template/spec/containers/0/resources/requests/memory", "value": "215Mi"},
  {"op": "replace", "path": "/spec/template/spec/containers/0/resources/limits/memory", "value": "640Mi"}
]'

kubectl rollout status statefulset/luckyhilo -n luckyhilo-prd --timeout=5m
kubectl get pods -n luckyhilo-prd
kubectl top pod -n luckyhilo-prd

echo "修復完成！"
```

### Post-implementation 驗證

```bash
# 1. 驗證配置已更新
echo "=== 驗證配置 ==="
kubectl get statefulset luckyhilo -n luckyhilo-prd -o jsonpath='{.spec.template.spec.containers[0].resources}' | jq .
kubectl get statefulset plinkocl -n plinkocl-prd -o jsonpath='{.spec.template.spec.containers[0].resources}' | jq .
kubectl get statefulset minesne -n minesne-prd -o jsonpath='{.spec.template.spec.containers[0].resources}' | jq .

# 2. 檢查 pod 狀態
echo "=== Pod 狀態 ==="
kubectl get pods -n luckyhilo-prd -o wide
kubectl get pods -n plinkocl-prd -o wide
kubectl get pods -n minesne-prd -o wide

# 3. 監控資源使用
echo "=== 資源使用 ==="
kubectl top pod -n luckyhilo-prd
kubectl top pod -n plinkocl-prd
kubectl top pod -n minesne-prd

# 4. 檢查是否有 OOMKilled events
echo "=== 檢查 OOM Events ==="
kubectl get events -n luckyhilo-prd | grep OOM
kubectl get events -n plinkocl-prd | grep OOM
kubectl get events -n minesne-prd | grep OOM

# 5. 檢查應用 logs
echo "=== 應用 Logs ==="
kubectl logs -n luckyhilo-prd luckyhilo-0 --tail=100
kubectl logs -n plinkocl-prd plinkocl-0 --tail=100
kubectl logs -n minesne-prd minesne-0 --tail=100
```

---

## 🔄 Rollback 計劃

如果修復後出現問題，可以快速 rollback：

```bash
# 方法 1: 使用 kubectl rollout undo
kubectl rollout undo statefulset/plinkocl -n plinkocl-prd
kubectl rollout undo statefulset/minesne -n minesne-prd
kubectl rollout undo statefulset/luckyhilo -n luckyhilo-prd

# 方法 2: 使用備份的 YAML
kubectl apply -f luckyhilo-backup-20251107-*.yaml
kubectl apply -f plinkocl-backup-20251107-*.yaml
kubectl apply -f minesne-backup-20251107-*.yaml
```

---

## 📊 預期效果

### 修復前 vs 修復後

| 服務 | 指標 | 修復前 | 修復後 | 改善 |
|------|------|--------|--------|------|
| **luckyhilo-prd** | Request | 800Mi | 215Mi | -73% |
| | Limit | 1.2 GiB (1228Mi) | 640Mi | -48% |
| | 使用率 (vs Request) | 23% | 87% | +64% |
| **plinkocl-prd** | Request | 1.8 GiB (1843Mi) | 190Mi | -90% |
| | Limit | 2.8 GiB (2867Mi) | 640Mi | -78% |
| | 使用率 (vs Request) | 9% | 86% | +77% |
| **minesne-prd** | Request | 900Mi | 130Mi | -86% |
| | Limit | 1.3 GiB (1331Mi) | 512Mi | -62% |
| | 使用率 (vs Request) | 12% | 85% | +73% |

### 集群層面改善

**節省的 Request 資源**:
```
luckyhilo: 800Mi → 215Mi   (-585Mi)
plinkocl:  1843Mi → 190Mi  (-1653Mi)
minesne:   900Mi → 130Mi   (-770Mi)
────────────────────────────────
總計節省: 3,008Mi ≈ 2.94 GiB
```

**節省的 Limit 資源**:
```
luckyhilo: 1228Mi → 640Mi  (-588Mi)
plinkocl:  2867Mi → 640Mi  (-2227Mi)
minesne:   1331Mi → 512Mi  (-819Mi)
────────────────────────────────
總計節省: 3,634Mi ≈ 3.55 GiB
```

**效果**:
- ✅ 釋放 2.94 GiB request 資源，可供其他 pods 使用
- ✅ 降低 node over-commit 風險
- ✅ 提高集群資源利用率
- ✅ 減少月度成本約 $59-70
- ✅ 配置更清晰易讀，符合 Kubernetes 最佳實踐

---

## 🎓 經驗教訓與預防措施

### 根本原因分析

1. **缺乏配置驗證**: 沒有自動化檢查來防止錯誤的單位使用
2. **手動配置錯誤**: 可能是從 bytes 轉換時的人為錯誤
3. **缺乏 Review 流程**: 配置變更沒有經過 peer review
4. **文檔不足**: 缺少 Kubernetes 資源配置標準文檔

### 預防措施

#### 1. 建立配置驗證 CI/CD Pipeline

```yaml
# .github/workflows/validate-k8s-configs.yml
name: Validate Kubernetes Configs

on: [pull_request]

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2

      - name: Validate Resource Configs
        run: |
          # 檢查 memory 是否使用了錯誤的 'm' 單位
          if grep -r "memory:.*[0-9]m$" manifests/; then
            echo "❌ Error: Found memory config using 'm' unit!"
            grep -rn "memory:.*[0-9]m$" manifests/
            exit 1
          fi

          # 檢查是否使用正確的單位 (Ki, Mi, Gi)
          if ! grep -r "memory:.*[0-9]\+\(Ki\|Mi\|Gi\)" manifests/; then
            echo "⚠️  Warning: Memory configs should use Ki, Mi, or Gi"
          fi

          echo "✅ Resource configs validation passed!"
```

#### 2. 建立 Admission Webhook

```yaml
# validating-webhook.yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingWebhookConfiguration
metadata:
  name: validate-resource-configs
webhooks:
- name: validate.resources.config
  rules:
  - operations: ["CREATE", "UPDATE"]
    apiGroups: ["apps", ""]
    apiVersions: ["v1"]
    resources: ["deployments", "statefulsets", "pods"]
  clientConfig:
    service:
      name: resource-validator
      namespace: kube-system
      path: "/validate"
  admissionReviewVersions: ["v1"]
  sideEffects: None
```

驗證邏輯 (Python 範例):
```python
def validate_memory_unit(value: str) -> bool:
    """驗證 memory 單位是否正確"""
    valid_units = ['Ki', 'Mi', 'Gi', 'Ti', 'k', 'M', 'G', 'T']

    # 不允許 'm' 結尾 (millicores 是 CPU 單位)
    if value.endswith('m'):
        return False

    # 檢查是否使用正確的單位
    return any(value.endswith(unit) for unit in valid_units)
```

#### 3. 建立資源配置標準文檔

創建 `RESOURCE_STANDARDS.md`:
```markdown
# Kubernetes 資源配置標準

## Memory 單位
✅ 使用: Ki, Mi, Gi, Ti
❌ 禁止: m (這是 CPU 單位)

## Request vs Limit 比例
- API 服務: Limit = Request × 2-3
- Game 服務: Limit = Request × 1.5-2

## 配置範例
\`\`\`yaml
resources:
  requests:
    cpu: 100m          # ✅ CPU 使用 m
    memory: 256Mi      # ✅ Memory 使用 Mi
  limits:
    cpu: 500m
    memory: 512Mi
\`\`\`
```

#### 4. 定期審計

```bash
#!/bin/bash
# audit-resource-configs.sh

echo "=== Kubernetes 資源配置審計 ==="

# 檢查所有使用 'm' 單位的 memory 配置
echo "檢查錯誤的 memory 單位..."
kubectl get statefulsets,deployments --all-namespaces -o json | \
  jq -r '.items[] | select(
    .spec.template.spec.containers[].resources.limits.memory // "" | test("m$")
    or
    .spec.template.spec.containers[].resources.requests.memory // "" | test("m$")
  ) | "\(.metadata.namespace)/\(.kind)/\(.metadata.name)"'

# 檢查過度配置的服務 (使用率 < 30%)
echo "檢查過度配置的服務..."
# ... (實現邏輯)
```

設置 cron job 每週執行一次。

---

## 📚 參考資料

### Kubernetes 官方文檔
- [Resource Management for Pods and Containers](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)
- [Meaning of Memory](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/#meaning-of-memory)

### Kubernetes API 文檔
- [Quantity API](https://kubernetes.io/docs/reference/kubernetes-api/common-definitions/quantity/)
- Go pkg: `k8s.io/apimachinery/pkg/api/resource`

### 內部文檔
- `ALL_SERVICES_RESOURCE_ANALYSIS.md` - 完整資源分析報告
- `FORESTTEAPARTY_RESOURCE_ANALYSIS.md` - forestteaparty 詳細分析
- `EKS_RESOURCE_ANALYSIS_REPORT.md` - 集群級資源分析

---

## 📞 支援與回報

如果修復過程中遇到問題：
1. 檢查 pod events: `kubectl describe pod <pod-name> -n <namespace>`
2. 檢查 logs: `kubectl logs <pod-name> -n <namespace>`
3. 執行 rollback（見上方 Rollback 計劃）
4. 聯繫 DevOps team

---

**文檔建立**: 2025-11-07
**最後更新**: 2025-11-07
**狀態**: ✅ Ready for Implementation
**優先級**: 🔴 P0 - Critical

