# 遊戲服務完整清單

**建立日期**: 2025-11-08
**來源**: kustomize-prd/gemini-game/base/prd/
**用途**: 記錄所有遊戲及後端服務的完整清單

---

## 📊 服務分類統計

| 類別 | 服務數 | Kustomize 目錄 |
|------|--------|---------------|
| **Hash Games** | 41 | `hash-svc/` |
| **Bingo Games** | 13 | `bingo-svc/` |
| **Arcade Games** | 5 | `arcade-svc/` |
| **Backend/API** | 16 | `backend-svc/` |
| **總計** | **75** | - |

---

## 🎮 Hash Games（41 個）

**目錄**: `/Users/lonelyhsu/gemini/kustomize-prd/gemini-game/base/prd/hash-svc/`

### Aviator 系列（3 個）
1. hash-aviator-game
2. hash-aviator2-game
3. hash-aviator2xin-game

### Crash 系列（4 個）
4. hash-crash-game
5. hash-crashcl-game
6. hash-crashgr-game
7. hash-crashne-game

### Hilo 系列（7 個）
8. hash-egypthilo-game
9. hash-hilo-game
10. hash-hilocl-game
11. hash-hilogr-game
12. hash-hilone-game
13. hash-luckyhilo-game
14. hash-multihilo-game

### Limbo 系列（4 個）
15. hash-limbo-game
16. hash-limbocl-game
17. hash-limbogr-game
18. hash-limbone-game

### Mines 系列（9 個）
19. hash-mines-game
20. hash-minesca-game
21. hash-minescl-game
22. hash-minesgr-game
23. hash-minesma-game
24. hash-minesne-game
25. hash-minespm-game
26. hash-minesraider-game
27. hash-minessc-game

### Plinko 系列（4 個）
28. hash-plinko-game
29. hash-plinkocl-game
30. hash-plinkogr-game
31. hash-plinkone-game

### LuckyDrop 系列（4 個）
32. hash-luckydropcoc-game
33. hash-luckydropcoc2-game
34. hash-luckydropgx-game
35. hash-luckydropoly-game

### Other 系列（6 個）
36. hash-diamonds-game
37. hash-dice-game
38. hash-dragontower-game
39. hash-keno-game
40. hash-videopoker-game
41. hash-wheel-game

---

## 🎰 Bingo Games（13 個）

**目錄**: `/Users/lonelyhsu/gemini/kustomize-prd/gemini-game/base/prd/bingo-svc/`

1. bg-arcadebingo-game
2. bg-bingbingbingo-game
3. bg-bingobells-game
4. bg-bonusbingo-game
5. bg-caribbeanbingo-game
6. bg-cavebingo-game
7. bg-egghuntbingo-game
8. bg-lostruins-game
9. bg-magicbingo-game
10. bg-maplebingo-game
11. bg-odinbingo-game
12. bg-steampunk-game
13. bg-steampunk2-game

---

## 🎪 Arcade Games（5 個）

**目錄**: `/Users/lonelyhsu/gemini/kustomize-prd/gemini-game/base/prd/arcade-svc/`

1. arcade-chilifiesta-game
2. arcade-forestteaparty-game
3. arcade-goldenclover-game
4. arcade-multiboomers-game
5. arcade-wilddiggr-game

---

## 🔧 Backend/API Services（16 個）

**目錄**: `/Users/lonelyhsu/gemini/kustomize-prd/gemini-game/base/prd/backend-svc/`

### Gate 服務（2 個）
1. arcade-gate-svc
2. hash-gate-svc

### API 服務（10 個）
3. bg-adapterapi-svc
4. bg-exgameapi-svc
5. bg-fakeapi-svc
6. bg-fakeapi2-svc
7. bg-mgmtapi-svc
8. bg-partnerapi-svc
9. domain-serviceapi
10. els-loyaltyapi-svc
11. event-api
12. ex-mgmt-api

### 後端服務（4 個）
13. bg-center-svc
14. bg-gate-svc (可能是 Bingo Gate?)
15. els-schedule-svc
16. els-syncservice-svc

---

## 📝 命名對應關係

### Kustomize 目錄名稱 → Kubernetes Namespace

| Kustomize 名稱 | K8s Namespace | 說明 |
|---------------|---------------|------|
| hash-aviator-game | aviator-prd | 移除 hash- 前綴，加 -prd 後綴 |
| bg-arcadebingo-game | arcadebingo-prd | 移除 bg- 前綴和 -game 後綴 |
| arcade-forestteaparty-game | forestteaparty-prd | 移除 arcade- 前綴和 -game 後綴 |
| els-loyaltyapi-svc | loyaltyapi-prd | 移除 els- 前綴和 -svc 後綴 |

---

## ⚠️ 我之前分析中的遺漏

### Hash Games（遺漏 7 個）
- ❌ hash-diamonds-game
- ❌ hash-dragontower-game
- ❌ hash-luckydropcoc-game
- ❌ hash-luckydropcoc2-game
- ❌ hash-luckydropgx-game
- ❌ hash-luckydropoly-game
- ❌ hash-videopoker-game

### Bingo Games（遺漏 3 個）
- ❌ bg-lostruins-game
- ❌ bg-steampunk-game
- ❌ bg-steampunk2-game

### Arcade Games（遺漏 3 個）
- ❌ arcade-chilifiesta-game
- ❌ arcade-goldenclover-game
- ❌ arcade-wilddiggr-game

### Backend Services（可能遺漏）
- ❓ bg-center-svc
- ❓ bg-gate-svc (需確認是否為 Bingo Gate)
- ❓ els-schedule-svc
- ❓ els-syncservice-svc

**總遺漏**: 至少 13 個遊戲服務 + 可能 4 個後端服務

---

## 🎯 下一步行動

1. ✅ 分析遺漏的 7 個 Hash games
2. ✅ 分析遺漏的 3 個 Bingo games
3. ✅ 分析遺漏的 3 個 Arcade games
4. ⭕ 確認 4 個後端服務是否需要分析
5. ⭕ 更新 HASH_GAMES_RESOURCE_ANALYSIS.md
6. ⭕ 更新 ALL_SERVICES_MEMORY_ANALYSIS_OVERVIEW.md
7. ⭕ 重新生成完整的資源優化建議

---

**最後更新**: 2025-11-08 00:30 UTC+8
