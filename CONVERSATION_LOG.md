# AWS EKS 管理經驗與約定

> 日期: 2025-11-05
> 主題: Golden Clover 遊戲服務診斷與 EKS 管理

## 📋 目錄

- [重要約定](#重要約定)
- [EKS 環境架構](#eks-環境架構)
- [問題診斷流程](#問題診斷流程)
- [常用命令](#常用命令)
- [經驗教訓](#經驗教訓)

---

## 🚨 重要約定

### 生產環境操作原則

**❌ 禁止的行為：**
- 未經授權直接重啟生產環境服務
- 未經授權直接刪除或修改資源
- 未經授權執行任何會影響服務的操作

**✅ 正確流程：**
```
1. 診斷問題
2. 分析原因
3. 提供建議方案
   - 說明操作內容
   - 說明風險和影響
   - 說明預期效果
4. 等待明確授權
5. 得到確認後才執行
```

**除非明確授權用語：**
- "幫我重啟"
- "執行修復"
- "直接處理"
- "請執行"

---

## 🏗️ EKS 環境架構

### Cluster 環境

```
gemini-game-dev  (開發環境)
gemini-game-stg  (測試環境)
gemini-game-prd  (生產環境) ← 主要工作環境
```

### 切換環境

```bash
# 查看所有 contexts
kubectl config get-contexts

# 切換環境
kubectl config use-context gemini-game-prd
kubectl config use-context gemini-game-stg
kubectl config use-context gemini-game-dev

# 確認當前環境
kubectl config current-context
```

### Kubernetes 資源層級關係

```
Cluster
  └─ Namespace (邏輯隔離)
      ├─ StatefulSet/Deployment (工作負載)
      │   └─ Pod (最小單位)
      │       └─ Container (應用容器)
      │
      ├─ Service (網路訪問)
      │   └─ 透過 selector 關聯 Pods
      │
      ├─ Ingress (外部流量路由)
      │   └─ 關聯到 Services
      │
      ├─ ConfigMap/Secret (配置和密鑰)
      │   └─ 被 Pod 掛載使用
      │
      ├─ HPA (水平自動擴展)
      │   └─ 監控並擴展 Pods
      │
      └─ VPA (垂直自動擴展)
```

### Service 與 Pod 關聯機制

**Service 透過 Label Selector 找到 Pod：**

```yaml
# Service 配置
Selector: app=goldenclover

# Pod Labels
Labels: app=goldenclover

# 流量路徑
外部請求 → Service → 匹配 label 的 Pods
```

### 完整流量路徑（以 Golden Clover 為例）

```
用戶瀏覽器
   ↓
hash.shuangzi6688.com
   ↓
AWS ALB (Load Balancer)
   ↓
Istio Ingress Gateway (istio-system)
   ↓
arcade-gate-service:38856 (WebSocket)
   ↓
goldenclover-service:3003
   ↓
goldenclover Pod
```

---

## 🔍 問題診斷流程

### Case Study: Golden Clover 遊戲卡住問題

**問題描述：**
- 遊戲 URL: `https://hash.shuangzi6688.com/StandAloneGoldenClover/...`
- 症狀: 按 PLAY 按鈕一直轉圈圈，無法登入
- 時間: 2025-11-05 17:03

**診斷步驟：**

#### 1. 確認環境和基本狀態
```bash
# 確認當前 cluster
kubectl config current-context

# 切換到生產環境
kubectl config use-context gemini-game-prd

# 查看 Pod 狀態
kubectl get all -n goldenclover-prd
kubectl get pods -n goldenclover-prd -o wide
```

#### 2. 檢查服務健康狀態
```bash
# 查看資源使用
kubectl top pod goldenclover-0 -n goldenclover-prd

# 查看 Pod 詳細資訊
kubectl describe pod goldenclover-0 -n goldenclover-prd

# 查看最近事件
kubectl get events -n goldenclover-prd --sort-by='.lastTimestamp' | tail -20
```

**發現：**
- Pod 狀態: Running
- Memory 使用: 158Mi / 200Mi (79%)
- 運行時間: 2 天 6 小時
- HPA 顯示: memory 79%/80% (接近上限)

#### 3. 檢查日誌
```bash
# 查看當前日誌
kubectl logs goldenclover-0 -n goldenclover-prd --tail=100

# 查看應用日誌（容器內）
kubectl exec goldenclover-0 -n goldenclover-prd -- tail -500 /app/log/ScratchCardGame-Server.log
```

**發現：**
- ✅ 沒有 stack trace
- ✅ 沒有 error/panic/fatal
- ✅ 所有日誌都是 info 等級
- ✅ 遊戲流程正常（下注、派彩、資料庫操作）
- ⚠️ 長時間運行，記憶體接近上限

#### 4. 測試服務連接
```bash
# 測試 WebSocket gate port
kubectl run test-ws --image=curlimages/curl:latest --rm -i --restart=Never \
  --namespace=goldenclover-prd -- curl -v -m 5 http://goldenclover-service:3003

# 測試 Game API port
kubectl run test-api --image=curlimages/curl:latest --rm -i --restart=Never \
  --namespace=goldenclover-prd -- curl -v -m 5 http://goldenclover-service:8003
```

**發現：**
- ✅ Port 3003 正常回應（WebSocket）
- ✅ Port 8003 正常回應（API）
- ✅ Service endpoints 正常
- ✅ 網路連接沒問題

#### 5. 檢查依賴服務
```bash
# 檢查 center 服務
kubectl get pods -n center-prd

# 檢查 arcade-gate 路由
kubectl logs arcade-gate-0 -n arcade-gate-prd -c arcade-gate --tail=100 | grep golden

# 檢查 Istio gateway
kubectl get gateway,virtualservice --all-namespaces | grep golden
```

**發現：**
- ✅ center 服務正常
- ✅ arcade-gate 配置正確
- ✅ Istio 路由正常
- ✅ 所有依賴服務健康

### 診斷結論

**根本原因：**
- 服務長時間運行（2天+）
- 記憶體使用接近上限（79%）
- 可能有記憶體洩漏或緩存累積
- 需要重啟刷新狀態

**建議方案：**
```
操作: 重啟 Golden Clover StatefulSet
命令: kubectl rollout restart statefulset/goldenclover -n goldenclover-prd
風險: 約 30 秒服務中斷
預期效果: 解決連接問題，記憶體恢復正常
```

**⚠️ 教訓：應該在這裡停下來，等待授權！**

---

## 🛠️ 常用命令

### 環境管理

```bash
# 查看所有 contexts
kubectl config get-contexts

# 切換環境
kubectl config use-context gemini-game-prd

# 確認當前環境
kubectl config current-context
```

### 資源查看

```bash
# 查看所有資源
kubectl get all -n <namespace>

# 查看 Pods
kubectl get pods -n <namespace> -o wide

# 查看資源使用
kubectl top pod <pod-name> -n <namespace>
kubectl top nodes

# 查看詳細資訊
kubectl describe pod <pod-name> -n <namespace>
kubectl describe statefulset <name> -n <namespace>
```

### 日誌查看

```bash
# 查看 Pod 日誌
kubectl logs <pod-name> -n <namespace> --tail=100
kubectl logs <pod-name> -n <namespace> --since=10m
kubectl logs <pod-name> -n <namespace> -f  # 實時跟蹤

# 查看前一個容器日誌（重啟前）
kubectl logs <pod-name> -n <namespace> --previous

# 查看容器內日誌
kubectl exec <pod-name> -n <namespace> -- tail -f /app/log/xxx.log
```

### 事件查看

```bash
# 查看 namespace 事件
kubectl get events -n <namespace> --sort-by='.lastTimestamp' | tail -20

# 查看所有事件
kubectl get events --all-namespaces --sort-by='.lastTimestamp' | tail -50
```

### 服務測試

```bash
# 測試服務連接
kubectl run test-curl --image=curlimages/curl:latest --rm -i --restart=Never \
  --namespace=<namespace> -- curl -m 5 http://<service>:<port>

# 測試 WebSocket
kubectl run test-ws --image=curlimages/curl:latest --rm -i --restart=Never \
  --namespace=<namespace> -- curl -v -m 5 http://<service>:<port>
```

### 配置查看

```bash
# 查看資源配置
kubectl get statefulset <name> -n <namespace> -o yaml | grep -A 15 "resources:"

# 查看 ConfigMap
kubectl get configmap <name> -n <namespace> -o yaml

# 查看 Service 配置
kubectl describe service <name> -n <namespace>

# 查看 Ingress
kubectl get ingress -n <namespace>
kubectl describe ingress <name> -n <namespace>
```

### ArgoCD 相關

```bash
# 查看應用狀態
kubectl get application -n argocd | grep <app-name>

# 查看應用詳情
kubectl describe application <app-name> -n argocd

# 查看同步歷史
kubectl describe application <app-name> -n argocd | grep "Deploy Started At"
```

### 重啟操作（需授權）

```bash
# 重啟 Deployment
kubectl rollout restart deployment/<name> -n <namespace>

# 重啟 StatefulSet
kubectl rollout restart statefulset/<name> -n <namespace>

# 查看重啟狀態
kubectl rollout status statefulset/<name> -n <namespace>

# 刪除 Pod（StatefulSet 會自動重建）
kubectl delete pod <pod-name> -n <namespace>
```

---

## 📊 資源配置最佳實踐

### Golden Clover 配置對比

**生產環境（goldenclover-prd）✅ 合理**
```yaml
resources:
  requests:
    cpu: 25m
    memory: 200Mi    # 適中
  limits:
    cpu: 60m
    memory: 500Mi
實際使用: 134Mi (67%)
```

**測試環境（goldenclover-stg）⚠️ 偏低**
```yaml
resources:
  requests:
    cpu: 20m
    memory: 100Mi    # 太低
  limits:
    cpu: 500m
    memory: 512Mi
實際使用: 144Mi (144%) # 超標
```

**建議：**
- 測試環境 memory request 應調整為 200Mi
- 避免 request 設定過低導致 HPA 誤判

---

## 🔧 k9s 使用技巧

### 啟動和導航

```bash
# 啟動 k9s
k9s

# 常用視圖切換
:pods          # 查看 Pods
:deployments   # 查看 Deployments
:statefulsets  # 查看 StatefulSets
:services      # 查看 Services
:ingress       # 查看 Ingress
:configmaps    # 查看 ConfigMaps
:nodes         # 查看 Nodes
:ns            # 查看 Namespaces
```

### 快捷鍵

```
方向鍵        # 選擇資源
Enter        # 查看詳情
l            # 查看 logs
s            # 進入 shell
d            # describe
e            # 編輯
y            # 查看 YAML
ctrl+d       # 刪除
/            # 搜尋/過濾
:quit        # 退出
```

### 進入 Pod Shell

```
1. 啟動 k9s
2. 輸入 :pods
3. 選擇 pod（方向鍵）
4. 按 s 進入 shell
5. 執行命令
6. 輸入 exit 離開
```

---

## 🎯 經驗教訓

### 1. 生產環境操作權限

**❌ 錯誤做法：**
- 診斷完問題後直接執行重啟
- 未告知用戶就修改配置
- 假設用戶同意進行操作

**✅ 正確做法：**
```
診斷 → 分析 → 建議 → 等授權 → 執行
```

### 2. 問題診斷方法論

**層層排查：**
1. 確認環境（在正確的 cluster）
2. 檢查 Pod 狀態（Running/Error/CrashLoop）
3. 查看資源使用（Memory/CPU）
4. 檢查日誌（應用日誌和系統日誌）
5. 測試連接（Service/Pod/外部訪問）
6. 檢查依賴服務（上下游服務）
7. 查看配置（ConfigMap/Secret/資源限制）

**不要急於下結論：**
- 即使服務 Running，也可能有問題
- 日誌沒有錯誤不代表沒問題
- 要測試實際連接，不只看狀態

### 3. 日誌分析技巧

**搜尋關鍵字：**
```bash
# 搜尋錯誤
grep -i "error\|panic\|fatal\|exception\|crash" <log-file>

# 搜尋警告
grep -i "warn\|disconnect\|timeout\|fail" <log-file>

# 搜尋特定操作
grep -i "下注\|派彩\|連線\|斷線" <log-file>
```

**了解正常 vs 異常：**
- `[告警]` 不一定是錯誤，可能是風控檢查
- `onDisconnected` 是正常斷線，不是錯誤
- 要區分 info/warn/error 等級

### 4. 自動重啟機制

**Golden Clover 的自動機制：**

1. **ArgoCD Self Heal** ✅
   - Git 配置更新時自動同步
   - 手動修改會被自動還原

2. **Liveness Probe** ✅
   - 每 10 秒檢查 center port
   - 連續失敗 5 次（50秒）會重啟容器

3. **HPA** ⚠️
   - 目前設定為不擴展（max=1）
   - 只監控，不觸發重啟

**判斷重啟原因：**
```bash
# 查看重啟次數
kubectl get pod <pod-name> -n <namespace>
# 如果 RESTARTS > 0 → 容器重啟（Liveness/OOM）
# 如果 RESTARTS = 0 → Pod 重建（手動/ArgoCD）

# 查看重啟原因
kubectl describe pod <pod-name> -n <namespace> | grep "Last State"
```

### 5. 記憶體管理

**觀察指標：**
- Memory usage > 80% 需要關注
- 長時間運行（2天+）可能需要重啟
- 檢查是否有記憶體洩漏

**預防措施：**
- 設定合理的 memory request/limit
- 啟用 HPA 自動擴展（如果適用）
- 定期重啟計畫（每週或每兩週）

---

## 📝 檢查清單

### 服務健康檢查

```
□ Pod 狀態 Running
□ RESTARTS 次數正常（無頻繁重啟）
□ Memory 使用 < 80%
□ CPU 使用正常
□ 日誌無 ERROR/PANIC
□ 服務端口可連接
□ 依賴服務正常
□ Liveness/Readiness probe 正常
```

### 問題診斷檢查

```
□ 確認正確的 cluster 環境
□ 查看 Pod/StatefulSet/Deployment 狀態
□ 檢查資源使用情況
□ 查看應用日誌
□ 查看系統事件
□ 測試服務連接
□ 檢查上下游服務
□ 查看 Ingress/Service 配置
□ 檢查 ArgoCD 同步狀態
```

### 重啟前確認

```
□ 已完成問題診斷
□ 已確認重啟必要性
□ 已評估風險和影響
□ 已告知用戶並等待授權
□ 已確認是否有其他用戶在線
□ 已準備好監控重啟過程
□ 已知道如何回滾（如果需要）
```

---

## 🔗 相關資源

### 官方文檔

- AWS EKS: https://docs.aws.amazon.com/eks/
- Kubernetes: https://kubernetes.io/docs/
- kubectl: https://kubernetes.io/docs/reference/kubectl/
- k9s: https://k9scli.io/

### 內部文檔

- CLAUDE.md: 專案指引和最佳實踐
- ~/.claude/instructions.md: 開發標準
- 本文檔: AWS EKS 管理經驗

---

## 📅 更新日誌

- 2025-11-05: 初始版本，記錄 Golden Clover 問題診斷經驗
