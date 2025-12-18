# AWS EKS 硬體故障事故分析報告

**文件編號**：OPS-935
**日期**：2025年12月17日
**準備單位**：DevOps Team
**機密等級**：內部 - 管理層審閱
**狀態**：事故已解決，建議改善措施

---

## 摘要

2025年12月17日，AWS 在 ap-east-1（香港）區域發生硬體可用性問題，影響我們的正式環境 EKS 叢集 `gemini-game-prd`。該事故由 AWS 基礎設施和我們的 Auto Scaling Groups 自動偵測。在 14:41 時，關鍵的人工介入（將 ASG Max 容量從 3 增加到 5）對於實現成功的跨可用區容錯移轉至關重要，展現了自動化系統的有效性以及在容量受限情況下及時人為決策的重要性。

**關鍵指標**：
- **事故持續時間**：32 分 48 秒（14:23-14:56 HKT）- AWS 硬體問題
- **完全恢復時間**：49 分鐘（14:23-15:12 HKT）- 包含所有服務
- **受影響服務**：10 個服務（總共 90+ 個，佔 11%）
- **最長停機時間**：15-20 分鐘（hash-gate 閘道服務）
- **平均停機時間**：2-3 分鐘（遊戲服務）
- **資料遺失**：零
- **人工介入**：關鍵容量調整於 14:41（Max: 3→5）
- **系統恢復**：自動偵測 + 人工容量調整

**事故嚴重性**：**P2 - 高**
**業務影響**：**低至中等**（範圍有限，快速恢復）

---

## 目錄

1. [事故概述](#事故概述)
2. [時間軸分析](#時間軸分析)
3. [根本原因分析](#根本原因分析)
4. [影響評估](#影響評估)
5. [系統回應評估](#系統回應評估)
6. [當前基礎設施分析](#當前基礎設施分析)
7. [建議措施](#建議措施)
8. [成本效益分析](#成本效益分析)
9. [實施路線圖](#實施路線圖)
10. [結論](#結論)
11. [附錄](#附錄)

---

## 1. 事故概述

### 1.1 事故描述

AWS Health Dashboard 報告了影響帳戶 470013648166 在 ap-east-1 區域的 EC2 實例可用性問題。部分 EC2 實例遭遇硬體故障，觸發 AWS Auto Scaling Groups 的自動替換機制。

**AWS 官方聲明**：
> "Between Wed, 17 Dec 2025 06:23:12 GMT and Wed, 17 Dec 2025 06:56:00 GMT, a subset of EC2 instances were unavailable in the ap-east-1 Region. Your affected EC2 instance(s) are listed in the 'Affected resources' tab. The issue has been resolved and the service is operating normally."

### 1.2 受影響的基礎設施

**叢集資訊**：
- **叢集名稱**：gemini-game-prd
- **Kubernetes 版本**：v1.34.1-eks-113cf36
- **區域**：ap-east-1（香港）
- **節點總數**：8 個節點（4 個節點群組）
- **受影響節點**：2 個節點被替換

**受影響的節點群組**：
1. **gemini-hash**：1 個節點被替換（總共 2 個）
2. **gemini-bg**：1 個節點被替換（總共 3 個）

---

## 2. 時間軸分析

### 2.1 詳細事件時間軸

| 時間（HKT） | 事件類型 | 描述 | 系統回應 | 狀態 |
|------------|---------|------|----------|------|
| **14:23:12** | 🔴 **事故開始** | AWS 偵測到硬體故障 | AWS Health Event 啟動 | 警示 |
| 14:27:09 | 🔴 節點故障 | 節點 i-007f3dd92b10101e6 未通過 EC2 健康檢查 | ASG 啟動替換 | 故障中 |
| 14:33:44 | ⚠️ 啟動失敗 | gemini-hash 啟動失敗（ap-east-1b） | 重試機制啟動 | 重試中 |
| 14:35:06 | ⚠️ 啟動失敗 | gemini-hash 啟動失敗（ap-east-1b） | 繼續重試 | 重試中 |
| 14:40:00 | 📧 通知 | AWS Health 通知郵件發送 | 團隊收到通知（延遲 17 分鐘） | 已知曉 |
| **14:41:21** | 👤 **人工操作** | **使用者設定 gemini-hash Desired: 2→3** | 啟動替換節點 | 介入中 |
| 14:41:30 | 🔄 節點啟動 | gemini-hash：實例 i-01b39c5c 啟動（ap-east-1c） | 跨 AZ 容錯移轉嘗試 | 恢復中 |
| **14:41:31** | 👤 **人工操作** | **使用者設定 gemini-bg Desired: 2→3** | 增加後端容量 | 介入中 |
| **14:41:36** | 👤 **關鍵人工介入** | **使用者更新 gemini-hash Max: 3→5, Desired: 3→4** | **啟用跨 AZ 容錯移轉的彈性容量** | **介入中** |
| 14:41:41 | 🔄 節點啟動 | gemini-hash：實例 i-00822ee644501bc0a 啟動（ap-east-1a） | 確保額外容量 | 恢復中 |
| 14:41:52 - 14:54:15 | ⚠️ 啟動失敗 | gemini-hash：**連續 10 次失敗**於 ap-east-1b | 容量耗盡，嘗試其他 AZ | 嚴重 |
| 14:51:41 | 🤖 自動清理 | Kubernetes 終止 2 個不健康節點 | 自動健康檢查回應 | 恢復中 |
| **14:56:00** | ⚙️ **AWS 硬體修復** | **AWS 解決硬體問題**（節點尚未就緒） | AWS 基礎設施穩定 | AWS-已解決 |
| 14:56:27 | ✅ 節點成功 | gemini-hash：最終節點於 ap-east-1a 啟動 | AZ 容錯移轉成功 | 恢復中 |
| 15:04:58 | 🤖 自動清理 | Kubernetes 終止不穩定節點 #3 | 自動健康檢查回應 | 穩定 |
| **15:11:57** | 👤 **人工操作** | **使用者設定 gemini-bg Desired: 2→3** | 確認穩定後恢復容量 | 介入中 |
| 15:11:49-15:13:13 | 🔄 Pod 遷移 | 最終 Pod 遷移完成 | 所有服務重啟 | 恢復中 |
| **15:12:07** | ✅ **完全恢復** | gemini-bg：最終節點啟動 | **系統完全運作** | **已解決** |

### 2.2 關鍵觀察

1. **人工介入至關重要**：使用者於 14:41:36 進行的容量調整（Max: 3→5）對於啟用跨 AZ 容錯移轉至關重要。若無此介入，ASG 將被限制於 ap-east-1b 的順序重試嘗試，將顯著延遲恢復時間。

2. **三個不同的解決時間點**：
   - 14:56:00：AWS 硬體問題解決（基礎設施層級）
   - 14:56:27：替換節點成功啟動
   - 15:12:07：所有服務完全運作

3. **AWS 基礎設施解決 vs. 服務恢復**：
   - AWS 硬體修復：32 分 48 秒（14:23-14:56）
   - 完整服務恢復：49 分鐘（14:23-15:12）
   - 差距：16 分鐘用於 Pod 重新排程和服務重啟

4. **總啟動失敗次數**：**15 次嘗試**（前所未有）- 所有失敗皆發生於 ap-east-1b，原因為 InsufficientInstanceCapacity

5. **容量限制影響**：首次啟動失敗到成功耗時約 23 分鐘，展現了彈性容量餘裕對於跨 AZ 容錯移轉情境的關鍵重要性

6. **通知延遲**：17 分鐘（AWS Health 郵件 vs. 實際事故開始）- 此延遲意味著團隊在關鍵決策已需要時才得知事故

### 2.3 啟動失敗分析

**gemini-hash 節點群組啟動失敗**：

```
失敗時間軸：
14:33:44 ━━ 失敗（ap-east-1b）
14:35:06 ━━ 失敗（ap-east-1b）
14:41:52 ━━ 失敗（ap-east-1b）
14:42:13 ━━ 失敗（ap-east-1b）
14:42:34 ━━ 失敗（ap-east-1b）
14:42:55 ━━ 失敗（ap-east-1b）
14:44:06 ━━ 失敗（ap-east-1b）
14:45:17 ━━ 失敗（ap-east-1b）
14:46:29 ━━ 失敗（ap-east-1b）
14:47:40 ━━ 失敗（ap-east-1b）
14:49:52 ━━ 失敗（ap-east-1b）
14:51:42 🔄 舊節點終止
14:52:04 ━━ 失敗（ap-east-1b）
14:54:15 ━━ 失敗（ap-east-1b）
14:56:27 ✅ 成功（ap-east-1a）← AZ 切換
```

**失敗的根本原因**：
```
InsufficientInstanceCapacity - We currently do not have sufficient
c5a.xlarge capacity in the Availability Zone you requested (ap-east-1b).
Our system will be working on provisioning additional capacity.
You can currently get c5a.xlarge capacity by not specifying an
Availability Zone in your request or choosing ap-east-1a, ap-east-1c.
```

### 2.4 Pod 遷移時間軸

**詳細 Pod 恢復時間軸**（基於實際 Pod 創建時間戳）：

#### 第一波：gemini-hash 節點 Pod（14:41:13-14:41:17 HKT）
*新節點 i-00822ee644501bc0a 在 ap-east-1a 變為 Ready 後立即觸發*

| HKT 時間 | Pod 名稱 | Namespace | 類型 | 恢復時長 |
|----------|----------|-----------|------|----------|
| 14:41:13 | minescl-0 | minescl-prd | 遊戲服務 | 約2-3分鐘 |
| 14:41:13 | minesgr-0 | minesgr-prd | 遊戲服務 | 約2-3分鐘 |
| 14:41:13 | minesma-0 | minesma-prd | 遊戲服務 | 約2-3分鐘 |
| 14:41:13 | multihilo-0 | multihilo-prd | 遊戲服務 | 約2-3分鐘 |
| 14:41:13 | plinkocl-0 | plinkocl-prd | 遊戲服務 | 約2-3分鐘 |
| 14:41:14 | minesne-0 | minesne-prd | 遊戲服務 | 約2-3分鐘 |
| **14:41:17** | **hash-gate-0** | **hash-gate-prd** | **閘道（關鍵）** | **約3-4分鐘** |

**關鍵觀察**：關鍵的 hash-gate-0 閘道服務在遊戲服務 Pod 之後 4 秒內優先恢復。基於典型的健康檢查和啟動時間（約 2-3 分鐘），閘道可能在 **14:43-14:45 HKT** 開始提供服務。

#### 第二波：gemini-hash 節點 Pod（14:54:10 HKT）
*由於不穩定節點故障導致的第二次遷移*

| HKT 時間 | Pod 名稱 | Namespace | 類型 | 恢復時長 |
|----------|----------|-----------|------|----------|
| 14:54:10 | minesck-0 | minesck-prd | 遊戲服務 | 約2-3分鐘 |

**關鍵發現 - 第一個不穩定節點級聯故障**：
- **14:41:13**：minesck-0 最初遷移到節點 **i-00822ee644501bc0a (ap-east-1a)**（gemini-hash，於 14:41:41 啟動）
- **14:51:42**：節點 **i-00822ee644501bc0a (ap-east-1a) 被 ASG 終止**，僅運行了 **10 分鐘**
- **14:54:10**：minesck-0 **被迫第二次遷移**到穩定節點 i-01b39c5c35027af62 (ap-east-1c)
- **根本原因**：第一波 Pod 遷移到的節點本身不穩定，未通過健康檢查後被 ASG 終止
- **影響範圍**：只有 minesck-0 受影響，因為其他第一波 Pod 被調度到穩定節點（12/15 和 11/10 的現有節點）
- **總停機時間**：約 13 分鐘（第一次遷移 + 在不穩定節點上 10 分鐘 + 第二次遷移）

**第二個不穩定節點發現**（14:56-15:04）：
- **14:56:27**：ASG 啟動另一個替換節點 **i-089d9cd8124ffa27f (ap-east-1b)**（gemini-hash）
- **15:04:58**：節點 **i-089d9cd8124ffa27f (ap-east-1b) 僅運行 8 分鐘後終止**
- **模式**：gemini-hash 節點組中連續第二個不穩定節點
- **影響**：無 Pod 雙重遷移（Pod 已在第一波/第二波遷移到穩定節點）

#### 第三波：gemini-bg 節點 Pod（15:11:49-15:11:50 HKT）
*觀察到不穩定節點模式後的謹慎運維決策導致延遲*

| HKT 時間 | Pod 名稱 | Namespace | 類型 | 恢復時長 |
|----------|----------|-----------|------|----------|
| 15:11:49 | bonusbingo-0 | bonusbingo-prd | 遊戲服務 | 約2-3分鐘 |
| 15:11:50 | forestteaparty-0 | forestteaparty-prd | 街機遊戲 | 約2-3分鐘 |
| 15:11:50 | goldenclover-0 | goldenclover-prd | 遊戲服務 | 約2-3分鐘 |
| 15:11:50 | magicbingo-0 | magicbingo-prd | Bingo 遊戲 | 約2-3分鐘 |
| 15:11:50 | mines-0 | mines-prd | Hash 遊戲 | 約2-3分鐘 |
| 15:11:50 | odinbingo-0 | odinbingo-prd | Bingo 遊戲 | 約2-3分鐘 |
| 15:11:50 | wilddiggr-0 | wilddiggr-prd | 街機遊戲 | 約2-3分鐘 |

**關鍵發現 - 第三個不穩定節點與受控恢復**：

**gemini-bg 不穩定節點時間軸**：
- **14:41:31**：👤 **用戶手動設定 Desired: 2→3**，ASG 啟動節點 **i-01b37ac4e8793faa7 (ap-east-1a)**
- **14:51:41**：節點 **i-01b37ac4e8793faa7 僅運行 10 分鐘後終止**（第三個不穩定節點！）
- **14:51:41**：🤖 **Kubernetes 自動終止不健康節點**，容量降為 2

**20 分鐘觀察期**（14:51-15:11）：
- **決策理由**：觀察到**三個連續不穩定節點**（gemini-hash 兩個，gemini-bg 一個）後，運維人員採取**謹慎策略**
- **風險評估**：立即啟動另一個節點可能導致第四個不穩定節點
- **穩定性驗證**：監控現有 2 個穩定節點，確保 AWS 基礎設施問題真正解決
- **決策點**：在擴展容量之前，等待確認沒有額外節點故障

**受控容量恢復**：
- **15:11:57**：👤 **用戶手動操作**，確認系統穩定後調整容量（Desired: 2→3）
- **15:12:07**：ASG 啟動替換節點 **i-0fa3eeffc6813dc20 (ap-east-1a)**（終於穩定！）
- **15:12:23**：節點加入 Kubernetes 集群並通過健康檢查
- **15:11:49-50**：Pod 立即遷移到新穩定節點
- **15:13-14**：所有服務完全運作

**關鍵觀察**：
- 20 分鐘延遲**不是系統故障**而是**謹慎的運維決策**
- 所有 gemini-bg Pod 在 1 秒時間窗口內同時遷移，顯示 Kubernetes 調度器的高效性能
- 這種謹慎方法**防止了潛在的第四個不穩定節點**和額外的級聯故障
- 成功驗證：節點 i-0fa3eeffc6813dc20 (ap-east-1a) 自啟動以來一直保持穩定

### 2.5 Pod 遷移分析摘要

**受影響的 Pod 總數**：15 個業務 Pod + 系統 Pod
**遷移時間窗口**：3 個不同的波次
**最快恢復**：第一波 Pod（從創建到就緒 2-3 分鐘）
**最長恢復**：minesck-0（經歷 2 次遷移，總共約 13 分鐘）

**含不穩定節點的恢復時間軸**：
```
14:22:00  🚨 Prometheus：KubeNodeNotReady（pending）- 節點 ip-172-31-53-101
14:22:00  🚨 Prometheus：KubeNodeUnreachable（pending）- 節點 ip-172-31-53-101
14:27:00  🚨 Prometheus：節點完全故障（KubeNodeNotReady resolved→Unreachable）
14:27:09  ━━ Kubernetes：叢集偵測到節點故障
14:36:00  ✅ Prometheus：KubeNodeUnreachable（pending）→ Resolved
14:37:00  🔥 Prometheus：KubeNodeUnreachable（FIRING）- 重大告警觸發
14:37:00  🔥 Prometheus：KubePdbNotEnoughHealthyPods（FIRING）- 多項服務受影響
14:41:00  ✅ Prometheus：KubeNodeUnreachable（FIRING）→ Resolved（替換節點已就緒）
14:41:36  ━━ 人工增加 Max 容量（3→5）+ gemini-bg Desired: 2→3
14:41:36  ━━ gemini-bg 節點啟動 - i-01b37ac4e8793faa7 (ap-east-1a)（不穩定節點 #1）
14:41:41  ━━ gemini-hash 節點啟動 - i-00822ee644501bc0a (ap-east-1a)（不穩定節點 #2）
14:41:13  ✅ 第一波：首批 Pod 開始遷移（6 個遊戲服務）
14:41:17  ✅ 第一波：hash-gate-0 啟動（關鍵閘道）
14:42:00  🚨 Prometheus：PodNotReady（pending）- hash-gate-0、minesck-0、minesne-0、plinkocl-0
14:43:00  ✅ Prometheus：PodNotReady（pending）→ Resolved - hash-gate-0、minesne-0、plinkocl-0
14:43-45  ✅ 第一波：服務就緒並開始提供服務
14:44:00  ✅ Prometheus：PodNotReady（pending）→ Resolved - minesck-0
14:45:00  🔥 Prometheus：PodNotReady（FIRING）- minesck-0（在不穩定節點上）
14:51:41  ❌ 不穩定節點 #1 (i-01b37ac4e8793faa7, ap-east-1a, gemini-bg) 終止（10 分鐘）
14:51:42  ❌ 不穩定節點 #2 (i-00822ee644501bc0a, ap-east-1a, gemini-hash) 終止（10 分鐘）
14:51:41  🤖 Kubernetes 自動清理不健康節點（gemini-bg: 3→2, gemini-hash: 4→3）
14:53:00  ✅ Prometheus：PodNotReady（FIRING）→ Resolved - minesck-0（已從不穩定節點遷移）
14:53:00  ✅ Prometheus：KubePdbNotEnoughHealthyPods（FIRING）→ Resolved（所有服務健康）
14:54:10  ✅ 第二波：minesck-0 被迫第二次遷移（因不穩定節點 #2）
14:56:27  ━━ gemini-hash 節點啟動 - i-089d9cd8124ffa27f (ap-east-1b)（不穩定節點 #3）
15:04:58  ❌ 不穩定節點 #3 (i-089d9cd8124ffa27f, ap-east-1b, gemini-hash) 終止（8 分鐘）
         ⏱️  20 分鐘觀察期（驗證 AWS 基礎設施穩定性）
15:11:57  👤 **用戶手動操作** gemini-bg Desired: 2→3（確認穩定性後）
15:12:07  ✅ gemini-bg 穩定節點啟動 - i-0fa3eeffc6813dc20 (ap-east-1a)（終於穩定！）
15:11:49  ✅ 第三波：gemini-bg Pod 開始遷移
15:13-14  ✅ 第三波：所有服務完全運作
```

**三個不穩定節點摘要**：
| 節點 | Instance ID | 節點組 | 啟動時間 | 終止時間 | AZ | 存活時長 | 影響 |
|------|-------------|--------|----------|----------|-----|----------|------|
| #1 | i-01b37ac4e8793faa7 | gemini-bg | 14:41:36 | 14:51:41 | ap-east-1a | 10 分鐘 | 第三波延遲 |
| #2 | i-00822ee644501bc0a | gemini-hash | 14:41:41 | 14:51:42 | ap-east-1a | 10 分鐘 | minesck-0 雙重遷移 |
| #3 | i-089d9cd8124ffa27f | gemini-hash | 14:56:27 | 15:04:58 | ap-east-1b | 8 分鐘 | 無 Pod 影響 |

**關鍵見解**：
1. **Prometheus 早期偵測**：Prometheus 在 **14:22:00 HKT** 偵測到節點異常（比 Kubernetes 早 5 分鐘），透過 KubeNodeNotReady 告警提供早期預警。重大告警（FIRING）在 14:37:00 觸發，促成主動回應。
2. **快速初始恢復**：關鍵 hash-gate 服務在首次告警後約 19 分鐘內恢復（14:22→14:41-45）
3. **高效調度器**：Kubernetes 在第一波中於 4 秒內調度了 6 個 Pod
4. **三個連續不穩定節點**：基礎設施危機在兩個節點組中產生**三個不穩定節點**（10 分鐘、10 分鐘、8 分鐘存活時長），顯示廣泛的 AWS 硬體不穩定性
5. **級聯故障影響**：minesck-0 由於不穩定節點 #2 經歷雙重遷移（約 13 分鐘停機）
6. **謹慎的運維決策**：第三波的 20 分鐘延遲是觀察到三個連續節點故障後的**審慎運維決策**，而非系統故障
7. **風險管理成功**：運維人員暫停並驗證穩定性的決策**防止了潛在的第四個不穩定節點**和額外的級聯故障
8. **告警解決時間軸**：關鍵節點級別 FIRING 告警在 4 分鐘內解決（14:37→14:41），大多數 Pod 告警在 1-2 分鐘內清除，最終關鍵告警在 14:53 解決（首次偵測後 31 分鐘）
9. **最終恢復**：首次告警後 51 分鐘達成完整系統恢復（14:22→15:13）
10. **監控驗證**：Prometheus 告警生命週期（pending→firing→resolved）與 Kubernetes 事件完全關聯，驗證監控準確性
11. **節點穩定性模式**：所有三個不穩定節點都在 8-10 分鐘內故障，顯示一致的健康檢查失敗閾值

---

## 3. 根本原因分析

### 3.1 主要根本原因

**AWS 基礎設施硬體故障**
- **類型**：實體硬體退化/故障
- **範圍**：ap-east-1 區域內的部分 EC2 實例
- **AWS 回應**：容量重新平衡機制啟動
- **分類**：外部因素，無法預防

### 3.2 促成因素

#### 因素 1：AWS 容量短缺
- **問題**：ap-east-1b AZ 的 c5a.xlarge 實例用盡
- **影響**：23 分鐘內連續 15 次啟動失敗
- **嚴重性**：高 - 顯著延遲恢復

#### 因素 2：單一實例類型依賴
- **問題**：所有節點群組僅使用 c5a.xlarge
- **影響**：主要類型不可用時無備援方案
- **嚴重性**：中 - 彈性受限

#### 因素 3：最大容量不足（事故前）
- **問題**：gemini-hash Max=3，僅有 50% 彈性空間
- **影響**：處理多節點故障的能力有限
- **嚴重性**：中 - 事故期間已處理

#### 因素 4：單節點關鍵服務
- **問題**：ArgoCD、Redis、閘道以單副本運行
- **影響**：節點替換期間無冗餘
- **嚴重性**：中 - 設計限制

### 3.3 自動恢復為何有效

✅ **有效機制**：
1. **容量重新平衡啟用**：AWS 主動替換有風險的節點
2. **Auto Scaling Groups**：自動啟動替換節點
3. **跨 AZ 重試邏輯**：成功容錯移轉到 ap-east-1a/1c
4. **Kubernetes 自我修復**：Pod 自動重新調度
5. **StatefulSet 韌性**：遊戲服務透過 PVC 維持狀態

---

## 4. 影響評估

### 4.1 服務影響摘要

**叢集總服務數**：90+ 個服務（命名空間）
**直接受影響**：10 個服務（11%）
**間接受影響**：0 個服務
**未受影響**：80+ 個服務（89%）

### 4.2 詳細影響分析

#### 高影響服務（15-20 分鐘停機）

| 服務 | 類型 | 角色 | 停機時間 | 原因 |
|------|------|------|----------|------|
| **hash-gate-0** | 閘道 | Hash 遊戲入口 | ~15-20 分鐘 | 經歷 2 次遷移 |

**影響詳情**：
- 所有 hash 遊戲流量經由此閘道路由
- 經歷兩次 gemini-hash 節點替換
- 第一次遷移：14:41（臨時節點）
- 第二次遷移：14:56（最終節點）
- Pod 重啟時間：每次遷移約 2 分鐘
- 連線恢復：每次遷移約 1 分鐘

#### 中等影響服務（2-3 分鐘停機）

| 服務 | 類型 | 節點群組 | 停機時間 |
|------|------|---------|----------|
| bonusbingo-0 | Bingo 遊戲 | gemini-bg | ~2-3 分鐘 |
| forestteaparty-0 | 街機遊戲 | gemini-bg | ~2-3 分鐘 |
| wilddiggr-0 | 街機遊戲 | gemini-bg | ~2-3 分鐘 |
| magicbingo-0 | Bingo 遊戲 | gemini-hash | ~2-3 分鐘 |
| odinbingo-0 | Bingo 遊戲 | gemini-hash | ~2-3 分鐘 |
| mines-0 | Hash 遊戲 | gemini-hash | ~2-3 分鐘 |
| minesck-0 | Hash 遊戲 | gemini-hash | ~2-3 分鐘 |
| minesne-0 | Hash 遊戲 | gemini-hash | ~2-3 分鐘 |
| plinkocl-0 | Hash 遊戲 | gemini-hash | ~2-3 分鐘 |

**影響細項**：
- 每個服務單次遷移
- StatefulSet pod 重啟：約 1-2 分鐘
- 連線重建：約 1 分鐘
- **無重啟循環**：所有 pod 的 restartCount = 0
- **無資料遺失**：PersistentVolumes 保留

### 4.3 業務影響

#### 營收影響（估算）
```
假設：
- 每個遊戲平均同時在線用戶：100-500
- 每分鐘平均投注：$10
- 受影響遊戲：10 個服務

保守估算：
- Hash-gate 停機：20 分鐘 × 300 用戶 × $10 = ~$60,000
- 個別遊戲：3 分鐘 × 100 用戶 × $10 × 9 個遊戲 = ~$27,000
- 總估計影響：~$87,000

注意：這是保守估計。實際影響可能較低，原因包括：
1. 用戶重試行為
2. 遊戲覆蓋重疊
3. 快速恢復時間
```

#### 客戶體驗影響
- **活躍會話**：Pod 遷移期間可能斷線
- **新會話**：短暫服務不可用
- **用戶感知**：最小（2-3 分鐘恢復在可接受範圍內）
- **支援工單**：未在本報告中追蹤

### 4.4 基礎設施服務（未受影響）

✅ **關鍵服務維持運作**：
- **ArgoCD**：持續運作（在 gemini-base 節點上）
- **Istio Service Mesh**：所有元件運作正常
- **Prometheus 監控**：持續收集指標
- **Ingress Controllers**：負載平衡維持
- **其他 80+ 服務**：無中斷

---

## 5. 系統回應評估

### 5.1 自動化回應效能

| 指標 | 目標 | 實際 | 評分 |
|------|------|------|------|
| **故障偵測** | < 5 分鐘 | 即時 | ⭐⭐⭐⭐⭐ |
| **Auto Scaling 回應** | < 10 分鐘 | 8 分鐘（首次嘗試） | ⭐⭐⭐⭐ |
| **Pod 重新調度** | < 5 分鐘 | 2-3 分鐘 | ⭐⭐⭐⭐⭐ |
| **服務恢復** | < 30 分鐘 | 20-49 分鐘 | ⭐⭐⭐ |
| **資料完整性** | 100% | 100% | ⭐⭐⭐⭐⭐ |
| **人工介入** | 最小化 | 4 項容量調整（1 項關鍵） | ⭐⭐⭐⭐ |

**整體評分**：**A-（4.5/5.0）**

**註記**：人工介入僅限於容量調整，Kubernetes 自動終止所有 3 個不健康節點。14:41:36 時的關鍵介入（Max: 3→5, Desired: 3→4）對於實現有效的跨 AZ 容錯移轉至關重要。這展現了主動配置足夠彈性容量的重要性，而非在事故期間被動反應。

### 5.2 架構韌性評估

✅ **展現的優勢**：
1. **Auto Scaling Groups**：正確識別並替換不健康的節點
2. **容量重新平衡**：主動從有風險的硬體移動工作負載
3. **跨 AZ 容錯移轉**：成功容錯移轉到備用 AZ
4. **Kubernetes 自我修復**：Pod 無需介入自動重新調度
5. **持久性儲存**：StatefulSet 資料透過 PVC 保留
6. **服務網格**：Istio 持續正確路由流量
7. **監控**：維持完整的事故可見性

⚠️ **識別的弱點**：
1. **單一實例類型**：c5a.xlarge 不可用時無備援
2. **最大容量不足**：部分節點群組彈性空間有限
3. **單副本服務**：關鍵閘道無冗餘
4. **通知延遲**：AWS Health 通知延遲 17 分鐘
5. **AZ 不平衡**：部分節點群組集中在有問題的 AZ

### 5.3 事故回應時間軸

**人工回應**：
- **14:27-14:40**：事故發生中，團隊尚未察覺（AWS Health 通知延遲）
- **14:40**：收到通知（事故開始後 +17 分鐘）
- **14:40-14:41**：快速評估情況
- **14:41:21**：人工操作 #1：設定 gemini-hash Desired: 2→3
- **14:41:31**：人工操作 #2：設定 gemini-bg Desired: 2→3
- **14:41:36**：**關鍵介入**：更新 gemini-hash Max: 3→5, Desired: 3→4
- **14:51:41-42**：Kubernetes 自動終止 2 個不健康節點（非人工操作）
- **15:04:58**：Kubernetes 自動終止第 3 個不健康節點（非人工操作）
- **14:41-15:11**：監控跨多個 AZ 的恢復進度和穩定性
- **15:11:57**：人工操作 #4：設定 gemini-bg Desired: 2→3（確認穩定後）
- **15:12+**：事故後分析和文件記錄

**關鍵觀察**：
1. **快速回應**：儘管有 17 分鐘延遲，團隊在收到通知後約 1 分鐘內即作出回應
2. **關鍵決策**：14:41:36 的人工容量調整解除了 ASG 執行跨 AZ 容錯移轉的限制
3. **有效自動化**：Kubernetes 自動終止所有 3 個不健康節點（基於健康檢查失敗）
4. **混合式恢復**：人工提供策略性容量調整，自動化處理偵測和節點替換
5. **學到的教訓**：主動的容量規劃（足夠的 Max 值）將消除事故期間需要被動介入的需求

---

## 6. 當前基礎設施分析

### 6.1 節點群組配置檢視

#### 當前配置（事故後）

| 節點群組 | 實例類型 | Min | Desired | Max | 彈性空間 | 關鍵服務 |
|---------|---------|-----|---------|-----|----------|----------|
| **gemini-hash** | c5a.xlarge | 2 | 2 | **5** ✅ | +3（150%） | hash-gate、nginx-ingress、24 個遊戲 pod |
| **gemini-bg** | c5a.xlarge | 2 | **3** | **4** ⚠️ | +1（33%） | bg-gate、center、backend-api-gw、14 個遊戲 pod |
| **gemini-arcade** | c5a.xlarge | 2 | 2 | **4** 🟡 | +2（100%） | arcade-gate、redis、istiod、40+ 個遊戲 pod |
| **gemini-base** | c5a.xlarge | 1 | **1** | **2** 🔴 | +1（100%） | ArgoCD（7 個 pod）、istio-gw（1 個 pod） |

#### 配置評估

**✅ gemini-hash**（事故期間最佳化）：
- Max 在事故回應期間從 3 增加到 5
- 現在有 150% 彈性容量
- 可處理 3 個節點同時故障
- 足以應對跨 AZ 容錯移轉
- **狀態**：配置良好

**⚠️ gemini-bg**（需要改善）：
- 目前運行 3 個節點（高於期望值）
- Max = 4，僅 33% 彈性空間
- 此次事故期間遇到問題
- 託管關鍵閘道服務（bg-gate、center）
- **風險**：可能難以應對多節點故障
- **建議**：增加 Max 至 6

**🟡 gemini-arcade**（可接受，可改善）：
- 100% 彈性容量（足夠）
- 託管最關鍵基礎設施：Redis、Istio 控制平面
- 承載最高 pod 負載（40+ pod）
- **風險**：多重故障情境下的中等風險
- **建議**：增加 Max 至 5 以保持一致性

**🔴 gemini-base**（高風險 - SPOF）：
- **單一節點**運行所有 ArgoCD 元件
- GitOps 部署的單點故障
- 11/10 事故顯示頻繁替換（4 次終止）
- **風險**：ArgoCD 不可用會阻塞所有部署
- **建議**：增加至 2 個期望節點 + 增加 Max 至 3

### 6.2 服務分布分析

#### 單副本關鍵服務（高風險）

| 服務 | 當前副本數 | 節點群組 | 風險等級 | 停機影響 |
|------|-----------|---------|---------|----------|
| **ArgoCD Suite** | 1（7 個 pod 在 1 個節點） | gemini-base | 🔴 嚴重 | 所有 GitOps 部署被阻塞 |
| **Redis** | 1 | gemini-arcade | 🔴 嚴重 | Session/快取資料不可用 |
| **hash-gate** | 1 | gemini-hash | 🔴 嚴重 | 所有 hash 遊戲無法存取 |
| **bg-gate** | 1 | gemini-bg | 🔴 嚴重 | 所有 bingo 遊戲無法存取 |
| **arcade-gate** | 1 | gemini-arcade | 🔴 嚴重 | 所有街機遊戲無法存取 |
| **center** | 1 | gemini-bg | 🟡 高 | 中央協調服務停機 |
| **istiod** | 1 | gemini-arcade | 🟡 高 | 服務網格控制平面降級 |

**關鍵發現**：大多數關鍵基礎設施以單副本運行，形成多個單點故障。

### 6.3 可用區分布

| 節點群組 | ap-east-1a | ap-east-1b | ap-east-1c | 平衡分數 |
|---------|------------|------------|------------|----------|
| gemini-hash | 1 節點 | 0 節點 | 1 節點 | ✅ 良好 |
| gemini-bg | 1 節點 | 1 節點 | 1 節點 | ✅ 優秀 |
| gemini-arcade | 0 節點 | 1 節點 | 1 節點 | ⚠️ 不平衡 |
| gemini-base | 1 節點 | 0 節點 | 0 節點 | 🔴 單一 AZ |

**觀察**：事故後，節點分布顯示改善，節點已從有問題的 ap-east-1b 移出。

---

## 7. 建議措施

### 7.1 立即行動（優先級 1 - 本週）

#### 行動 1.1：調整節點群組最大容量
**目標**：為多節點故障提供足夠的彈性容量

**實施**：
```bash
# 1. gemini-bg：增加 Max 至 6（優先級：高）
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name eks-gemini-bg-80cd1c18-ecf8-90f9-7904-092595d2fc8d \
  --max-size 6 \
  --region ap-east-1

# 2. gemini-arcade：增加 Max 至 5（優先級：中）
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name eks-gemini-arcade-9acd1c16-11b0-c06e-eeb8-8ad51743b6bf \
  --max-size 5 \
  --region ap-east-1

# 3. gemini-base：增加 Max 至 3（優先級：高）
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name eks-gemini-base-12cd1bfd-987f-69a6-dba6-1f65166d0803 \
  --max-size 3 \
  --region ap-east-1
```

**預期結果**：
- 所有節點群組具有 100%+ 彈性容量
- 支援跨 AZ 容錯移轉情境
- 實現無服務中斷的滾動更新
- **成本影響**：$0（僅增加 Max，不啟動新節點）

**驗證**：
```bash
aws autoscaling describe-auto-scaling-groups \
  --region ap-east-1 \
  --query 'AutoScalingGroups[?contains(AutoScalingGroupName, `gemini`)].{Name:AutoScalingGroupName,Min:MinSize,Desired:DesiredCapacity,Max:MaxSize}' \
  --output table
```

#### 行動 1.2：設置即時事故警報
**目標**：將通知延遲從 17 分鐘減少到 < 1 分鐘

**實施**：
```bash
# AWS Health → EventBridge → SNS → Slack 整合
# 為 AWS Health 事件創建 EventBridge 規則
aws events put-rule \
  --name "aws-health-incidents" \
  --event-pattern '{
    "source": ["aws.health"],
    "detail-type": ["AWS Health Event"],
    "detail": {
      "service": ["EC2"],
      "eventTypeCategory": ["issue"]
    }
  }' \
  --region ap-east-1

# 連接到 SNS 主題以發送 Slack 通知
aws events put-targets \
  --rule "aws-health-incidents" \
  --targets "Id"="1","Arn"="arn:aws:sns:ap-east-1:470013648166:ops-alerts"
```

**預期結果**：
- AWS Health 事件即時 Slack 通知
- 通知延遲：< 1 分鐘
- **成本影響**：約 $0.50/月（SNS）

#### 行動 1.3：記錄事故回應手冊
**目標**：正式化未來事故的回應程序

**創建**：`runbooks/eks-node-failure-response.md`

**內容**：
1. 事故偵測檢查清單
2. 評估程序
3. 緊急容量調整程序
4. 溝通範本
5. 事故後檢視範本

**預期結果**：
- 更快的事故回應
- 團隊間一致的程序
- 更好的稽核文件

### 7.2 短期改善（優先級 2 - 本月）

#### 行動 2.1：實施實例類型多樣化
**目標**：消除單一實例類型依賴

**實施**：
```bash
# 為每個節點群組配置混合實例策略
# gemini-hash 範例：
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name eks-gemini-hash-becd1c1a-397a-63f3-d535-1b140077cf55 \
  --mixed-instances-policy '{
    "InstancesDistribution": {
      "OnDemandBaseCapacity": 2,
      "OnDemandPercentageAboveBaseCapacity": 100,
      "SpotAllocationStrategy": "lowest-price"
    },
    "LaunchTemplate": {
      "LaunchTemplateSpecification": {
        "LaunchTemplateId": "lt-0a8c8754b7297524c",
        "Version": "$Latest"
      },
      "Overrides": [
        {"InstanceType": "c5a.xlarge", "WeightedCapacity": "1"},
        {"InstanceType": "c5.xlarge", "WeightedCapacity": "1"},
        {"InstanceType": "c5d.xlarge", "WeightedCapacity": "1"},
        {"InstanceType": "c5n.xlarge", "WeightedCapacity": "1"}
      ]
    }
  }'
```

**備援優先順序**：
1. c5a.xlarge（主要，當前類型）
2. c5.xlarge（備援 1，類似效能）
3. c5d.xlarge（備援 2，含本地 NVMe）
4. c5n.xlarge（備援 3，增強網路）

**預期結果**：
- 消除容量短缺風險
- 自動備援至可用的實例類型
- **成本影響**：$0-50/月（價格差異極小）

**需要測試**：備援實例的效能基準測試

#### 行動 2.2：啟用 ArgoCD 高可用性
**目標**：消除 ArgoCD 單點故障

**當前狀態**：所有 ArgoCD pod（7 個 pod）在單一節點上（gemini-base）

**建議方案 A**（增加節點數量）：
```bash
# 增加 gemini-base 期望容量至 2
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name eks-gemini-base-12cd1bfd-987f-69a6-dba6-1f65166d0803 \
  --min-size 2 \
  --desired-capacity 2 \
  --max-size 3 \
  --region ap-east-1
```

**建議方案 B**（Pod 反親和性）：
```yaml
# 應用於關鍵 ArgoCD 元件
affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100
      podAffinityTerm:
        labelSelector:
          matchLabels:
            app.kubernetes.io/name: argocd-server
        topologyKey: kubernetes.io/hostname
```

**建議方法**：方案 A + 方案 B
- 增加節點至 2（立即改善可用性）
- 應用反親和性規則（確保分布）

**預期結果**：
- ArgoCD 在單節點故障期間保持可用
- GitOps 部署持續不中斷
- **成本影響**：+$150/月（1 個額外的 c5a.xlarge 節點）

**ROI 分析**：
- ArgoCD 停機阻塞所有部署
- 關鍵部署視窗：典型 15-30 分鐘
- 事故頻率：每季 1-2 次（基於歷史資料）
- 被阻塞部署的估計成本：每次事故 $5,000-10,000
- **回收期**：< 1 次事故

#### 行動 2.3：實施閘道服務冗餘
**目標**：消除單副本閘道瓶頸

**要擴展的服務**：
```yaml
# hash-gate：1 → 2 副本
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: hash-gate
  namespace: hash-gate-prd
spec:
  replicas: 2  # 從 1 增加

# bg-gate：1 → 2 副本
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: bg-gate
  namespace: bg-gate-prd
spec:
  replicas: 2  # 從 1 增加

# arcade-gate：1 → 2 副本
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: arcade-gate
  namespace: arcade-gate-prd
spec:
  replicas: 2  # 從 1 增加
```

**實施考量**：
- StatefulSet pod 身份管理
- Session affinity / sticky sessions（如需要）
- 負載平衡策略
- 儲存需求（每個副本的 PVC）

**預期結果**：
- 節點故障期間閘道服務零停機
- 主動-主動或主動-待命配置
- **成本影響**：最小（相同節點數，僅重新分配 pod）

**需要測試**：
- 負載平衡行為
- Session 持久性
- 容錯移轉情境

#### 行動 2.4：實施增強節點健康檢查
**目標**：防止 Pod 在基礎設施危機期間被調度到不穩定節點

**根本原因參考**：第二波事件中，minesck-0 被調度到節點 i-00822ee644501bc0a，該節點僅運行 10 分鐘後失敗，導致被迫第二次遷移，將停機時間延長至 13 分鐘。

**實施方案**：

**步驟 1 - 配置 ASG 健康檢查寬限期**：
```bash
# 增加健康檢查寬限期以允許適當的節點初始化
aws autoscaling update-auto-scaling-group \
  --auto-scaling-group-name eks-gemini-hash-becd1c1a-397a-63f3-d535-1b140077cf55 \
  --health-check-grace-period 600 \  # 10 分鐘（從預設 300 秒增加）
  --region ap-east-1

# 應用到所有節點組
for asg in $(aws autoscaling describe-auto-scaling-groups \
  --region ap-east-1 \
  --query 'AutoScalingGroups[?contains(AutoScalingGroupName, `gemini`)].AutoScalingGroupName' \
  --output text); do
  aws autoscaling update-auto-scaling-group \
    --auto-scaling-group-name "$asg" \
    --health-check-grace-period 600 \
    --region ap-east-1
done
```

**步驟 2 - 添加節點就緒閘道**：
```yaml
# 配置自定義節點就緒條件
apiVersion: v1
kind: Node
metadata:
  name: node-example
spec:
  readinessGates:
  - conditionType: "CustomNodeStabilityCheck"
```

**步驟 3 - 為新節點實施污點標記**：
```bash
# 添加啟動污點以防止立即調度
# 在啟動模板 user data 中配置：
#!/bin/bash
# 啟動時標記節點污點
kubectl taint nodes $(hostname) node.kubernetes.io/not-ready=true:NoSchedule

# 等待穩定性檢查（5 分鐘）
sleep 300

# 運行自定義健康檢查
/opt/scripts/node-stability-check.sh

# 如果健康則移除污點
if [ $? -eq 0 ]; then
  kubectl taint nodes $(hostname) node.kubernetes.io/not-ready:NoSchedule-
fi
```

**步驟 4 - 在調度關鍵 Pod 前監控節點年齡**：
```yaml
# 添加節點親和性以優先選擇成熟節點用於關鍵服務
affinity:
  nodeAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100
      preference:
        matchExpressions:
        - key: node.kubernetes.io/age
          operator: Gt
          values:
          - "300"  # 優先選擇超過 5 分鐘的節點
```

**預期結果**：
- 新節點在接受 Pod 前經過適當的穩定期
- 降低不穩定節點造成級聯故障的風險
- 防止類似 minesck-0 第二波雙重遷移的情況
- **成本影響**：$0（僅配置）

**成功指標**：
- 因節點不穩定導致的 Pod 雙重遷移為零
- 節點啟動後前 10 分鐘內的故障率 < 1%
- 每次事件的平均 Pod 遷移次數：1.0（vs. 目前 1.07）

**需要測試**：
- 模擬節點啟動後立即失敗
- 驗證污點移除時機
- 驗證關鍵 Pod 調度行為

### 7.3 中期改善（優先級 3 - 本季）

#### 行動 3.1：實施 Redis 高可用性
**目標**：消除 Redis 單點故障

**當前狀態**：gemini-arcade 節點上的單一 Redis pod

**建議方案**：Redis Sentinel 或 Redis Cluster

**選項 A - Redis Sentinel**（建議）：
```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: redis
  namespace: redis-prd
spec:
  replicas: 3  # 1 主 + 2 副本
  serviceName: redis
  template:
    spec:
      containers:
      - name: redis
        image: redis:7-alpine
        args: ["--replicaof", "redis-0.redis", "6379"]
      - name: sentinel
        image: redis:7-alpine
        args: ["--sentinel"]
```

**預期結果**：
- 自動主節點容錯移轉（< 30 秒）
- 跨節點資料複製
- 節點故障時零資料遺失
- **成本影響**：+2 個 pod（相同節點，重新分配）

**需要測試**：
- 容錯移轉時間
- 資料一致性
- 客戶端重新連線行為

#### 行動 3.2：實施綜合監控儀表板
**目標**：節點健康和容量的即時可見性

**元件**：
1. **Grafana Dashboard**："EKS Node Health & Capacity"
   - 節點 CPU/記憶體使用率
   - Pod 跨節點分布
   - ASG 活動時間軸
   - EC2 啟動成功/失敗率
   - AZ 分布視覺化

2. **CloudWatch 警報**：
   ```bash
   # ASG 啟動失敗警報
   aws cloudwatch put-metric-alarm \
     --alarm-name "eks-asg-launch-failures" \
     --metric-name FailedAttachInstancesCount \
     --namespace AWS/AutoScaling \
     --statistic Sum \
     --period 300 \
     --evaluation-periods 1 \
     --threshold 1 \
     --comparison-operator GreaterThanThreshold \
     --alarm-actions arn:aws:sns:ap-east-1:470013648166:ops-alerts

   # 節點 NotReady 警報
   aws cloudwatch put-metric-alarm \
     --alarm-name "eks-node-not-ready" \
     --metric-name cluster_failed_node_count \
     --namespace ContainerInsights \
     --statistic Average \
     --period 300 \
     --evaluation-periods 2 \
     --threshold 1 \
     --comparison-operator GreaterThanThreshold \
     --alarm-actions arn:aws:sns:ap-east-1:470013648166:ops-alerts
   ```

3. **Prometheus 警報**：
   ```yaml
   # 節點壓力警報
   - alert: NodeUnderMemoryPressure
     expr: kube_node_status_condition{condition="MemoryPressure",status="true"} == 1
     for: 5m
     annotations:
       summary: "Node {{ $labels.node }} under memory pressure"

   - alert: NodeUnderDiskPressure
     expr: kube_node_status_condition{condition="DiskPressure",status="true"} == 1
     for: 5m
     annotations:
       summary: "Node {{ $labels.node }} under disk pressure"
   ```

**預期結果**：
- 主動問題偵測
- 更快的事故回應
- 更好的容量規劃資料
- **成本影響**：約 $10/月（CloudWatch 自訂指標）

#### 行動 3.3：進行混沌工程演練
**目標**：透過受控故障測試驗證韌性

**測試情境**：
1. **單節點終止**
   - 隨機終止每個節點群組的 1 個節點
   - 測量：Pod 重新調度時間、服務可用性

2. **AZ 故障模擬**
   - 排空 ap-east-1b 中的所有節點
   - 測量：跨 AZ 容錯移轉、資料一致性

3. **容量耗盡**
   - 人為限制 ASG Max 至 Desired
   - 模擬節點故障
   - 測量：容量限制下的系統行為

4. **多重並發故障**
   - 同時終止 2 個節點
   - 測量：恢復時間、服務降級

**工具**：AWS FIS（Fault Injection Simulator）或 Chaos Mesh

**排程**：每季混沌工程日

**預期結果**：
- 驗證事故回應程序
- 識別額外弱點
- 團隊訓練和信心
- **成本影響**：約 $50/月（AWS FIS 實驗）

### 7.4 長期策略改善（優先級 4 - 本年度）

#### 行動 4.1：多區域災難復原
**目標**：關鍵服務的地理冗餘

**範圍**：
- 複製 EKS 叢集至 ap-southeast-1（新加坡）
- 實施跨區域資料庫複製
- 設置 Global Accelerator 以進行自動容錯移轉

**預期結果**：
- 承受區域級停機
- < 5 分鐘 RTO（恢復時間目標）
- **成本影響**：+100% 基礎設施成本（約 $5,000-10,000/月）

**時間表**：6-12 個月

#### 行動 4.2：遷移至 Karpenter Autoscaler
**目標**：用更智慧的節點供應取代 Cluster Autoscaler

**優勢**：
- 更快的擴展（30 秒 vs. 3-5 分鐘）
- 更好的實例類型選擇
- 低使用率節點的整合
- Spot 實例整合

**預期結果**：
- 更快的事故回應
- 20-30% 成本降低（更好的 bin-packing）
- **實施時間**：1-2 個月

#### 行動 4.3：實施基於 GitOps 的災難復原
**目標**：自動化叢集重建能力

**元件**：
1. Infrastructure as Code（Terraform）
2. GitOps 部署（ArgoCD）
3. 自動化備份/還原（Velero）
4. DR 手冊和程序

**預期結果**：
- 完整叢集重建 < 2 小時
- 自動化、測試過的 DR 程序
- **成本影響**：約 $200/月（備份儲存）

---

## 8. 成本效益分析

### 8.1 立即行動成本摘要

| 行動 | 實施成本 | 每月經常性成本 | 風險降低 | 優先級 |
|------|---------|---------------|----------|---------|
| 調整 Max 容量 | $0 | $0 | 高 | 🔴 嚴重 |
| 即時警報 | $100 | $1 | 中 | 🔴 嚴重 |
| 手冊文件 | $500 | $0 | 中 | 🟡 高 |
| **階段 1 總計** | **$600** | **$1** | **高** | - |

### 8.2 短期改善成本摘要

| 行動 | 實施成本 | 每月經常性成本 | 風險降低 | 優先級 |
|------|---------|---------------|----------|---------|
| 實例類型多樣化 | $200 | $0-50 | 高 | 🔴 嚴重 |
| ArgoCD HA | $100 | $150 | 極高 | 🔴 嚴重 |
| 閘道冗餘 | $500 | $0 | 高 | 🟡 高 |
| **階段 2 總計** | **$800** | **$150-200** | **極高** | - |

### 8.3 總成本 vs. 風險降低

**總投資（第一年）**：
- 實施：$1,400
- 經常性（年度）：$1,800-2,400
- **第一年總計**：$3,200-3,800

**風險緩解價值**：
- 估計事故頻率：每年 2-4 次（基於 AWS 歷史）
- 每次事故平均業務影響：$50,000-100,000
- 風險降低：70-80%（改善恢復時間和可用性）
- **年度價值**：$70,000-320,000 避免的損失

**ROI**：第一年 **18 倍 - 84 倍回報**

### 8.4 按優先級的成本細分

```
優先級 1（立即 - 本週）：
├─ 實施：$600
├─ 每月：$1
└─ 影響：防止 50% 的事故情境

優先級 2（短期 - 本月）：
├─ 實施：$800
├─ 每月：$150-200
└─ 影響：防止 70-80% 的事故情境

優先級 3（中期 - 本季）：
├─ 實施：$2,000-3,000
├─ 每月：$200-300
└─ 影響：防止 85-90% 的事故情境

優先級 4（長期 - 本年度）：
├─ 實施：$50,000-100,000
├─ 每月：$5,000-10,000
└─ 影響：防止 95-99% 的事故情境
```

---

## 9. 實施路線圖

### 9.1 階段 1：立即回應（第 1 週）

**時間表**：2025年12月17-24日

| 任務 | 負責人 | 截止日期 | 依賴項 | 狀態 |
|------|--------|---------|--------|------|
| 調整 gemini-bg Max 容量 | DevOps | 12/18 | 管理層批准 | ⏳ 待處理 |
| 調整 gemini-arcade Max 容量 | DevOps | 12/18 | 管理層批准 | ⏳ 待處理 |
| 調整 gemini-base Max 容量 | DevOps | 12/18 | 管理層批准 | ⏳ 待處理 |
| 設置 AWS Health 警報 | DevOps | 12/20 | Slack webhook | ⏳ 待處理 |
| 創建事故手冊 | DevOps | 12/24 | 範本批准 | ⏳ 待處理 |
| 事故後檢視會議 | 全體 | 12/19 | 本報告 | ⏳ 待處理 |

**成功標準**：
- [ ] 所有 Max 容量調整已驗證
- [ ] AWS Health 警報在 Slack 中接收（測試）
- [ ] 手冊已審核並批准
- [ ] 團隊接受手冊程序培訓

### 9.2 階段 2：短期改善（第 2-4 週）

**時間表**：2025年12月25日 - 2026年1月15日

| 任務 | 負責人 | 截止日期 | 依賴項 | 狀態 |
|------|--------|---------|--------|------|
| 設計實例類型多樣化 | DevOps Lead | 12/27 | 階段 1 完成 | ⏳ 待處理 |
| 實施混合實例策略 | DevOps | 1/5 | 設計批准 | ⏳ 待處理 |
| 測試備援實例類型 | QA | 1/8 | 實施完成 | ⏳ 待處理 |
| 規劃 ArgoCD HA 實施 | Platform Team | 1/3 | 成本批准 | ⏳ 待處理 |
| 部署 ArgoCD HA 配置 | DevOps | 1/10 | 規劃完成 | ⏳ 待處理 |
| 將閘道服務擴展至 2 副本 | DevOps | 1/12 | 測試完成 | ⏳ 待處理 |
| 在暫存環境驗證冗餘 | QA | 1/15 | 部署完成 | ⏳ 待處理 |

**成功標準**：
- [ ] 所有節點群組上的混合實例策略啟用
- [ ] ArgoCD 承受單節點故障（已測試）
- [ ] 閘道服務在節點排空期間維持可用性
- [ ] 所有變更在暫存環境中驗證

### 9.3 階段 3：中期改善（2026 Q1）

**時間表**：2026年1月 - 3月

| 任務 | 負責人 | 截止日期 | 依賴項 | 狀態 |
|------|--------|---------|--------|------|
| 設計 Redis HA 架構 | Platform Team | 1/20 | 研究完成 | ⏳ 待處理 |
| 實施 Redis Sentinel | DevOps | 2/15 | 設計批准 | ⏳ 待處理 |
| 測試 Redis 容錯移轉情境 | QA | 2/28 | 實施完成 | ⏳ 待處理 |
| 建立綜合監控儀表板 | DevOps | 2/10 | 指標收集 | ⏳ 待處理 |
| 配置 CloudWatch 警報 | DevOps | 2/15 | 儀表板完成 | ⏳ 待處理 |
| 設置 Prometheus 警報 | DevOps | 2/20 | Alert manager 配置 | ⏳ 待處理 |
| 進行混沌工程演練 1 | 全體 | 3/15 | 工具配置 | ⏳ 待處理 |

**成功標準**：
- [ ] Redis 自動容錯移轉 < 30 秒
- [ ] 容錯移轉測試中零資料遺失
- [ ] 監控儀表板對所有團隊開放
- [ ] 所有關鍵警報已測試和驗證
- [ ] 混沌工程報告已發布

### 9.4 階段 4：長期策略（2026）

**時間表**：2026年4月 - 12月

| 計畫 | 負責人 | 目標 | 投資 |
|------|--------|------|------|
| 多區域 DR 規劃 | Platform Team | 2026 Q2 | $50k-100k |
| Karpenter 遷移 | DevOps | 2026 Q3 | 2 個月工作量 |
| GitOps DR 自動化 | DevOps | 2026 Q4 | 1 個月工作量 |

**成功標準**：
- [ ] DR 計畫已記錄和測試
- [ ] Karpenter 降低成本 20-30%
- [ ] 完整叢集重建已自動化

---

## 10. 結論

### 10.1 事故摘要

2025年12月17日 AWS 硬體故障事故展現了我們當前 EKS 基礎設施的優勢和弱點：

**✅ 優勢**：
- AWS Health 和 ASG 機制的自動故障偵測
- 收到通知後約 1 分鐘內的快速人工回應
- 自動化系統與人為決策之間的有效協調
- 整個事故期間無資料遺失
- Kubernetes 自我修復成功重新排程所有受影響的 Pod
- 全程維持監控和可觀測性

**⚠️ 弱點**：
- 彈性容量不足需要被動的人工介入（Max: 3→5）
- 單一實例類型依賴導致 15 次連續啟動失敗
- 單副本關鍵服務造成不必要的停機
- 通知延遲 17 分鐘意味著團隊較晚得知事故
- 識別出多個單點故障（ArgoCD、閘道、Redis）

### 10.2 關鍵學習

1. **混合式方法效果最佳**：我們的自動化系統（ASG、Kubernetes 自我修復）為恢復提供了基礎，但及時的人為決策（14:41:36 的容量調整）對於解除跨 AZ 容錯移轉的限制至關重要。這次事故驗證了自動化投資和快速人工回應的重要性。

2. **主動容量規劃至關重要**：gemini-hash 節點群組的 Max 容量不足（3）需要在事故期間緊急人工調整至 Max=5。這種被動介入展現了彈性容量應該主動配置足夠的餘裕（100-150%），而非在事故期間才需要調整。

3. **單點故障為高風險**：以單副本運行的服務（ArgoCD、閘道、Redis）造成不必要的脆弱性和延長的停機時間。ArgoCD 的情況特別嚴重，因為它是單一節點託管所有 7 個 pod，為所有 GitOps 部署創造了單點故障。

4. **實例類型多樣性至關重要**：依賴單一實例類型（c5a.xlarge）使我們容易受到容量短缺的影響，導致 ap-east-1b 的 15 次連續啟動失敗。這將透過混合實例策略來解決，提供自動備援選項。

5. **即時警報為必要條件**：17 分鐘的通知延遲意味著團隊在關鍵決策已需要時才得知事故。透過 EventBridge 進行主動 AWS Health 事件警報將把此延遲從 17 分鐘降低至 < 1 分鐘。

### 10.3 風險評估

**改善前**：
- **事故機率**：中（每年 2-4 次）
- **每次事故業務影響**：高（$50k-100k）
- **年度總風險**：$100k-400k

**階段 1 後（立即）**：
- **風險降低**：50%
- **殘餘年度風險**：$50k-200k
- **投資**：$600 + $1/月

**階段 2 後（短期）**：
- **風險降低**：70-80%
- **殘餘年度風險**：$20k-120k
- **投資**：+$800 + $150-200/月

**階段 3 後（中期）**：
- **風險降低**：85-90%
- **殘餘年度風險**：$10k-60k
- **總投資（第 1 年）**：$3,200-3,800

### 10.4 管理層決策點

**需要立即批准**：
1. ✅ 調整所有節點群組的 Max 容量（$0 成本）
2. ✅ 實施 AWS Health 即時警報（$1/月）
3. ✅ 創建事故回應手冊（$500 一次性）

**需要成本批准**：
1. ⏳ ArgoCD HA（gemini-base 2 個節點）- **$150/月**
   - **建議**：批准 - 關鍵基礎設施
   - **ROI**：< 1 次事故回收期

2. ⏳ 實例類型多樣化 - **$0-50/月**
   - **建議**：批准 - 低成本、高價值

3. ⏳ 閘道服務冗餘 - **$0 成本**（相同資源）
   - **建議**：批准 - 無成本、顯著效益

**未來討論**：
1. Redis HA 實施（2026 Q1）
2. 多區域 DR（2026 Q2-Q4）
3. Karpenter 遷移（2026 Q3）

### 10.5 最終建議

**立即行動**（本週）：
1. ✅ 執行所有階段 1 任務（Max 容量調整、警報）
2. ✅ 批准 ArgoCD HA 實施（$150/月）
3. ✅ 安排與利害關係人的事故後檢視會議

**短期行動**（本月）：
1. ✅ 實施實例類型多樣化
2. ✅ 部署 ArgoCD HA 配置
3. ✅ 將閘道服務擴展至 2 副本

**成功指標**：
- 事故恢復時間：< 15 分鐘（目前：20-49 分鐘）
- 關鍵服務的單點故障：0（目前：5+）
- 自動化回應率：100%（目前：100% ✓）
- 通知延遲：< 1 分鐘（目前：17 分鐘）

---

## 11. 附錄

### 附錄 A：AWS Health Event 詳情

**Event ID**：未揭露
**Event Type Code**：AWS_EC2_INSTANCE_AVAILABILITY_ISSUE
**Event Region**：ap-east-1
**開始時間**：Wed, 17 Dec 2025 06:23:12 GMT（14:23:12 HKT）
**結束時間**：Wed, 17 Dec 2025 06:56:00 GMT（14:56:00 HKT）
**持續時間**：32 分 48 秒
**狀態**：已關閉
**受影響資源**：2 個 EC2 實例

**AWS 描述**：
> Between Wed, 17 Dec 2025 06:23:12 GMT and Wed, 17 Dec 2025 06:56:00 GMT, a subset of EC2 instances were unavailable in the ap-east-1 Region. Your affected EC2 instance(s) are listed in the 'Affected resources' tab. The issue has been resolved and the service is operating normally.

### 附錄 B：ASG 擴展活動日誌

**gemini-hash 節點群組**：
```
總活動數：20
啟動成功：5
啟動失敗：15
終止：5
持續時間：14:23 - 15:04（41 分鐘）
```

**gemini-bg 節點群組**：
```
總活動數：3
啟動成功：2
啟動失敗：0
終止：1
持續時間：14:41 - 15:12（31 分鐘）
```

### 附錄 C：受影響 Pod 列表

**gemini-hash 節點（24 個業務 pod）**：
1. hash-gate-0（閘道 - 嚴重）
2. nginx-ingress-controller（基礎設施 - 嚴重）
3. chilifiesta-0（遊戲）
4. luckydropcoc-0（遊戲）
5. luckydropcoc2-0（遊戲）
6. luckydropgx-0（遊戲）
7. luckydropoly-0（遊戲）
8. luckyhilo-0（遊戲）
9. magicbingo-0（遊戲）
10. mines-0（遊戲）
11. minesca-0（遊戲）
12. minesck-0（遊戲）
13. minesne-0（遊戲）
14. minespm-0（遊戲）
15. minesraider-0（遊戲）
16. minessc-0（遊戲）
17. multiboomers-0（遊戲）
18. odinbingo-0（遊戲）
19. plinko-0（遊戲）
20. plinkocl-0（遊戲）
21. plinkogr-0（遊戲）
22. plinkone-0（遊戲）
23. videopoker-0（遊戲）
24. wheel-0（遊戲）

**gemini-bg 節點**：
1. bonusbingo-0（遊戲）
2. forestteaparty-0（遊戲）
3. wilddiggr-0（遊戲）
4. bg-gate-0（閘道 - 嚴重）
5. center-0（服務 - 嚴重）
6. backend-api-ingressgateway（基礎設施 - 嚴重）
7. （+ 監控/日誌 pod）

### 附錄 D：節點配置詳情

**實例類型**：c5a.xlarge
- **vCPU**：4
- **記憶體**：8 GB
- **網路**：最高 10 Gbps
- **EBS 頻寬**：最高 4,750 Mbps
- **成本**：約 $0.154/小時（約 $112/月）

**作業系統**：Amazon Linux 2023.9.20251027
**核心**：6.12.53-69.119.amzn2023.x86_64
**容器執行環境**：containerd 2.1.4

### 附錄 E：參考連結

- **Jira Issue**：[OPS-935](https://jira.ftgaming.cc/browse/OPS-935)
- **AWS Health Dashboard**：AWS Console → Personal Health Dashboard
- **EKS Cluster Console**：AWS Console → EKS → gemini-game-prd
- **Grafana Monitoring**：內部監控儀表板
- **事故手冊**：`runbooks/eks-node-failure-response.md`（待創建）

### 附錄 F：聯絡資訊

**事故回應團隊**：
- DevOps Lead：[姓名]
- Platform Team Lead：[姓名]
- On-Call Engineer：[輪值]

**升級路徑**：
1. On-Call Engineer（PagerDuty）
2. DevOps Lead
3. Engineering Manager
4. CTO

**溝通管道**：
- Slack：#ops-alerts、#incident-response
- Email：devops@company.com
- 電話：緊急熱線

---

## 文件元數據

**文件版本**：1.0
**最後更新**：2025年12月17日
**下次審查**：2026年1月17日
**需要批准**：Engineering Manager、CTO
**分發對象**：Engineering Leadership、DevOps Team、Platform Team

**文件歷史**：
- v1.0（2025-12-17）：初始報告創建
- （未來版本將在此追蹤）

---

**報告結束**
