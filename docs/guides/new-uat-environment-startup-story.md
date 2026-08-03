# 新 UAT 環境啟動完整故事

## 前言：為什麼要這個故事？

當組織新增一個 UAT 環境時，不同角色需要**循序漸進地入場**。如果這個過程不清楚，會造成：
- ❌ 多個人做同一件事（資源浪費）
- ❌ 依賴不清楚（有人卡住等待）
- ❌ 事後才發現漏掉某個設定

**這個故事展示：** 在 **新 UAT 環境上線** 的完整過程中，誰做什麼、順序是什麼、何時需要 infra admin 幫忙、何時可以自己處理。

---

## 時間軸：Week 0 → Week 4

### 🔴 **Week 0.0：Infra Admin 只做一次**

**角色：AWS Architect + DevOps Engineer**

```
Timeline: Monday 09:00 - Monday 14:00 (Single Pass - 只做一次)
```

**做什麼：**
```bash
# 1. AWS 層面（不重複）
✅ 建立 EKS Cluster (uat-cluster-001)
✅ 建立 KMS 金鑰 (uat-kms-key)
✅ 建立 S3 Bucket (uat-backups-bucket)
✅ 建立 IRSA Roles (mongodb-uat-role, postgresql-uat-role)
✅ 建立 CloudNativePG Operator IAM 權限

# 2. Kubernetes 層面（不重複）
✅ 部署 Flux GitOps Controller
✅ 建立 storage class (gp3-mongodb)
✅ 建立 namespace (mongodb, postgresql, signoz)
✅ 配置 RBAC (誰可以看什麼)
```

**Why Single Pass？**
- AWS 資源是 **共用的**（不會因為 Boomi 新增流程就要重新建 KMS）
- Kubernetes cluster 是 **共用的**（不會重建）
- IaC 驅動（Terraform 確保 idempotent）

**驗證：**
```bash
bash scripts/verify-platform-health.sh --preflight
# Expected: ✅ EKS cluster exists
# Expected: ✅ KMS key accessible
# Expected: ✅ S3 bucket accessible
# Expected: ✅ Flux installed
```

**然後……Infra Admin 通知：「基礎設施 ready」**

---

### 🟡 **Week 0.1：Infra Admin + DevOps 一起 provision platform**

**角色：DevOps Engineer + Infra Admin**

```
Timeline: Monday 15:00 - Monday 18:00
```

**做什麼：**
```bash
# Single pass provisioning - 一個人跑，不會重複
bash scripts/provision.sh all --auto-approve
# 這會 apply 所有 Terraform（AWS 層 + Kubernetes 層）
# 包括：MongoDB PSMDB、PostgreSQL CNPG 的 operators

bash scripts/provision.sh signoz --auto-approve
# 部署 SigNoz 觀測平台

bash scripts/provision.sh signoz-observability --auto-approve
# 部署 SigNoz dashboards + alert rules（預配置的標準 dashboard）
# 📍 This includes importing standard dashboards from:
#    dashboards/signoz-import-pack/mongodb-overview.json
#    dashboards/signoz-import-pack/postgresql-overview.json
#    dashboards/signoz-import-pack/kubernetes-pod-metrics-overall.json
```

**驗證：**
```bash
bash scripts/verify-platform-health.sh --smoke-test
# Expected: MongoDB replica set is healthy (3/3)
# Expected: PostgreSQL cluster is ready
# Expected: SigNoz is accepting telemetry
# Expected: Standard dashboards are imported and visible
```

**結果：**
```
✅ 三個平台 ready
✅ 基礎 dashboard 已可用（不用等到 Week 1）
✅ 可以開始看實時 metrics
```

**然後……DevOps 通知：「三個平台 + 標準 dashboard ready」**

---

### 🟢 **Week 0.2：Boomi Admin 入場**

**角色：Boomi Administrator**

```
Timeline: Tuesday 09:00
Dependency: ← 等待 DevOps smoke test PASS
```

**任務：配置 Boomi Audit 機制**

```bash
# 1. 檢查 MongoDB audit collection 存在
bash scripts/run-audit-telemetry-test.sh --check-collection

# 2. 配置 Boomi 連接字符串
#    （DevOps 應該已經通過 Slack/email 提供）
Boomi Connection: mongodb+srv://oms-mongodb-workload:****@uat-mongodb:27017/audit
Auth Mechanism: MONGODB-X509 (IRSA已自動設置)

# 3. 測試連接
bash scripts/run-audit-telemetry-test.sh --test-write-read
# Expected: ✅ Can write audit records
# Expected: ✅ Can read audit records
```

**Boomi Admin 的權限：**
```
✅ CAN: 配置 Boomi process 連接字符串
✅ CAN: 測試 audit write/read
✅ CAN: 調整 audit log 的 retention 時間（如果配置為 MongoDB TTL index）
✅ CAN: 在 SigNoz 建立 custom queries（查詢 audit 日誌）
✅ CAN: 配置 Boomi alert rules（基於 audit 事件觸發）

❌ CANNOT: 修改 MongoDB IRSA role
❌ CANNOT: 刪除 audit collection
❌ CANNOT: 修改 KMS 加密金鑰
❌ CANNOT: 停止/重啟 MongoDB operator
```

**何時需要 Infra Admin？**
```
情況 1: Boomi 連接 failed
        → Infra Admin 檢查 IRSA role 的 IAM 權限

情況 2: Audit query 很慢
        → Boomi Admin 可以先自己在 SigNoz 調查
        → 如果需要建立索引，通知 Infra Admin（需要 mongodb admin 權限）

情況 3: 要新增 audit 收集器（Groovy library）
        → Boomi Admin 可以自己修改 Boomi process
        → 不需要 Infra Admin 介入
```

---

### 🟢 **Week 0.3：Boomi Developer 入場**

**角色：Boomi Process Developer**

```
Timeline: Tuesday 11:00
Dependency: ← 等待 Boomi Admin 驗證連接成功
```

**任務：開發業務流程**

```bash
# 0. 讀文檔（5 分鐘）
cat docs/guides/boomi-audit-log-owner-guide.md

# 1. 開發 Boomi process
#    - 呼叫業務服務
#    - 在關鍵點寫入 audit 日誌
#    範例 Groovy：
      def auditLogger = new AuditLogger(mongoConnection)
      auditLogger.log(
        action: "ORDER_CREATED",
        orderId: orderId,
        timestamp: System.currentTimeMillis(),
        details: [amount: orderAmount, customer: customerId]
      )

# 2. 在 SigNoz 看 audit 日誌
#    ✅ 查詢: SELECT * FROM audit_logs WHERE action='ORDER_CREATED'
#    ✅ 建立 dashboard: Order Creation Rate
#    ✅ 建立 alert: If order creation rate < 10/hour, send Slack

# 3. 測試端對端流程
#    - 在 UAT 執行 process
#    - 驗證 audit 日誌出現在 MongoDB + SigNoz
#    - 驗證 alert 有觸發（如果配置）
```

**Boomi Developer 的自主性：**
```
✅ CAN: 修改 Boomi process（audit logging 邏輯）
✅ CAN: 在 SigNoz 查詢 audit 日誌
✅ CAN: 在 SigNoz 建立 dashboard（基於 audit 資料）
✅ CAN: 測試 process（在 UAT 環境跑，實際寫入 MongoDB）
✅ CAN: 調試日誌（用 SigNoz 的 trace view）

❌ CANNOT: 修改 Boomi connector 的連接字符串（由 Boomi Admin 控制）
❌ CANNOT: 停止/重啟 MongoDB（由 Infra Admin 控制）
❌ CANNOT: 在 SigNoz 修改 alert 規則（由 Ops team 控制）
```

**何時需要 Infra Admin？**
```
情況 1: 「MongoDB 連接超時」
        → Boomi Admin 檢查連接字符串
        → Infra Admin 檢查 IRSA pod identity、network policy

情況 2: 「SigNoz 查詢太慢」
        → Boomi Developer 寫入更多詳細資料
        → Infra Admin 可能調整 ClickHouse 查詢優化

情況 3: 「我想在 audit 日誌寫入 large binary data」
        → 可以先試試（需要改 Groovy code）
        → 如果效能問題，通知 Infra Admin 調整 MongoDB document size limit
```

---

### 🟣 **Week 1：SRE/Platform Ops 入場**

**角色：Platform Reliability Engineer + Boomi Admin**

```
Timeline: Wednesday 09:00
Dependency: ← 等待 DevOps smoke test PASS
```

**任務：優化 + 定制觀測**

```bash
# 1. 檢查已預配置的標準 dashboard（已由 Infra Admin 在 Week 0.1 導入）
#    ✅ MongoDB overview（replica set、operation latency、backup status）
#    ✅ PostgreSQL overview（cluster status、connections、backup status）
#    ✅ Kubernetes pod metrics（CPU、memory、network）
#    ✅ SigNoz health（ClickHouse、Kafka、UI 狀態）
#    💡 這些都在 dashboards/signoz-import-pack/ 中定義，已自動導入

# 2. 定制 dashboard（可選）
#    ✅ 複製標準 dashboard，加上 custom panels
#    ✅ 添加業務相關指標（e.g., "Order Processing Time"）
#    ✅ 建立角色特定 dashboard（SRE view、Boomi Admin view、Developer view）
#    💡 標準 dashboard 在代碼中維護，永遠可以 reimport（不影響 custom 版本）

# 3. 配置告警規則
#    - MongoDB replica out of sync → PagerDuty
#    - PostgreSQL backup failed → Email
#    - Audit log write latency > 500ms → Slack

# 4. 設定日誌收集
#    - MongoDB audit log rotation policy
#    - PostgreSQL WAL 備份驗證
#    - SigNoz ClickHouse 存儲策略

# 5. 測試故障轉移
bash scripts/verify-platform-health.sh --test-failover
# Expected: MongoDB replica failover works
# Expected: Backups resume automatically
```

**SRE 的權限：**
```
✅ CAN: 在 SigNoz 定制 dashboard（add/remove panels）
✅ CAN: 創建 custom dashboard（新增業務指標）
✅ CAN: Reimport 標準 dashboard（如果改乱了）
✅ CAN: 配置告警、on-call rotation
✅ CAN: 調整 metrics retention policy
✅ CAN: 執行 disaster recovery drills
✅ CAN: 標記 false positive alerts

❌ CANNOT: 修改代碼中的標準 dashboard（由 Infra Admin 維護）
❌ CANNOT: 修改 MongoDB cluster configuration（需要 cluster admin）
❌ CANNOT: 修改 IRSA roles（需要 AWS 權限）
```

**何時需要 Infra Admin？**
```
情況 1: 「我要改標準 dashboard 的配置」
        → 創建新 issue/PR，Infra Admin 審查並更新代碼
        → 下次 provision 時自動同步

情況 2: 「我想收集更多 MongoDB metrics」
        → 檢查 mongodb-metrics-collector.yaml 的現有 scrape config
        → 如果需要修改，Infra Admin 更新配置，重新 apply

情況 3: 「Backup 失敗，我懷疑是 S3 權限」
        → 檢查 SigNoz 日誌（SRE 自己看）
        → 如果確實是 IRSA 權限，通知 Infra Admin
```

**Dashboard 的版本控制模式：**
```
📂 dashboards/signoz-import-pack/
   ├─ mongodb-overview.json     ← Infra Admin 維護（代碼中）
   ├─ postgresql-overview.json  ← Infra Admin 維護（代碼中）
   └─ kubernetes-pod-metrics-overall.json ← Infra Admin 維護（代碼中）

SigNoz UI 中：
   ├─ [Imported] MongoDB Overview  (1:1 from code, can be re-imported)
   ├─ [Custom] Order Processing Dashboard  (SRE 創建，自主性強)
   ├─ [Custom] PostgreSQL Backups Deep Dive  (SRE 創建)
   └─ [Customized] MongoDB Overview - UAT Specific  (SRE 改過的版本)

如果 SRE 不小心改壞了標準 dashboard：
   bash scripts/prepare-signoz-dashboard-import.sh
   # Re-import 標準版本（custom dashboard 不受影響）

這個設計的好處：
   ✅ 基礎 dashboard 立即可用（Week 0.1 就有）
   ✅ SRE 可以定制而不怕破壞（隨時可以 reimport）
   ✅ 標準 dashboard 版本控制在 git（審核 + 追蹤變更）
   ✅ 多環境共享（PROD/UAT dashboard 用同一份代碼，適當修改）
```

---

### 🔵 **Week 2-4：持續運作**

**角色：Mixed（取決於情況）**

```
Timeline: Ongoing
```

**典型流程：**

| 事件 | Owner | 需要 Infra Admin? |
|------|-------|-----------------|
| Boomi developer 新增 process | Boomi Developer | ❌ No |
| Audit query 很慢 | SRE + Boomi Dev | ⚠️ Maybe (索引) |
| MongoDB pod OOMKilled | Infra Admin | ✅ YES (增加記憶) |
| 新增 Boomi connector 連接 | Boomi Admin | ❌ No |
| 需要更多 EBS 存儲 | Infra Admin | ✅ YES (擴展 PVC) |
| 配置自定義 SigNoz panel | SRE | ❌ No |
| 需要新的 KMS 金鑰 | Infra Admin | ✅ YES (AWS 層) |
| 修改審計日誌保留期限 | Boomi Admin | ⚠️ Maybe (TTL index) |
| PostgreSQL 備份驗證失敗 | Infra Admin + SRE | ✅ YES (檢查 IAM) |

---

## 完整用戶旅程圖

```
┌─────────────────────────────────────────────────────────────────┐
│                         Week 0.0                                 │
│  🔴 Infra Admin (AWS + K8s infrastructure setup - ONCE)         │
│  ✅ EKS + KMS + S3 + IRSA roles + Flux                           │
│  ✅ scripts/verify-platform-health.sh --preflight               │
└──────────────────────┬──────────────────────────────────────────┘
                       │
                       ↓
┌─────────────────────────────────────────────────────────────────┐
│                         Week 0.1                                 │
│  🟡 DevOps Engineer (Platform provisioning - ONCE)              │
│  ✅ bash scripts/provision.sh all --auto-approve                │
│  ✅ bash scripts/provision.sh signoz --auto-approve             │
│  ✅ bash scripts/provision.sh signoz-observability --auto-approve
│     (Includes: import standard dashboards from JSON code)       │
│  ✅ scripts/verify-platform-health.sh --smoke-test              │
│  ✅ Standard dashboards already visible in SigNoz               │
└──────────────────────┬──────────────────────────────────────────┘
                       │
                       ↓
┌─────────────────────────────────────────────────────────────────┐
│                         Week 0.2                                 │
│  🟢 Boomi Admin (Audit mechanism setup)                         │
│  ✅ Verify MongoDB connection string                             │
│  ✅ bash scripts/run-audit-telemetry-test.sh --test-write-read  │
│  ✅ Configure audit log TTL retention                            │
└──────────────────────┬──────────────────────────────────────────┘
                       │
                       ↓
┌─────────────────────────────────────────────────────────────────┐
│                         Week 0.3                                 │
│  🟢 Boomi Developer (Process development)                       │
│  ✅ Read audit log guide                                         │
│  ✅ Develop Boomi processes with audit logging                   │
│  ✅ Query audit logs in SigNoz                                   │
│  ✅ End-to-end test in UAT                                       │
└──────────────────────┬──────────────────────────────────────────┘
                       │
                       ↓
┌─────────────────────────────────────────────────────────────────┐
│                         Week 1                                   │
│  🟣 SRE/Platform Ops (Observability customization)              │
│  ✅ Review pre-imported standard dashboards                      │
│  ✅ Customize dashboards (add/remove panels)                     │
│  ✅ Create custom dashboards for business metrics                │
│  ✅ Set up alerts & on-call rotation                             │
│  ✅ Test failover scenarios                                      │
│  ✅ Verify backup integrity                                      │
│  💡 Standard dashboards can be reimported anytime                │
└──────────────────────┬──────────────────────────────────────────┘
                       │
                       ↓
┌─────────────────────────────────────────────────────────────────┐
│                    Week 2-4 (Ongoing)                            │
│  🔵 All Roles (Normal operations)                               │
│  ✅ Boomi Devs: Add processes (completely independent)          │
│  ✅ Boomi Admin: Configure connectors (independent)              │
│  ✅ SRE: Monitor & tune (independent, can update dashboards)     │
│  ✅ Infra Admin: On-call for outages (intervention only)         │
└─────────────────────────────────────────────────────────────────┘
```

---

## 關鍵設計原則

### ✅ **單線程 Provisioning**

```
為什麼？避免競爭條件、資源衝突、重複工作

❌ Bad: Infra Admin A 跑 provision.sh all，同時 Infra Admin B 也跑
✅ Good: 只有一個人跑，output 有清晰的「DONE」標誌

實現方法：
- 使用 Terraform state lock（S3 backend 已配置）
- 使用 Flux GitOps（只有 main branch 的 commit 會觸發 apply）
- 每個階段的 script 都是 idempotent（跑多次也是安全的，但不需要）
```

### ✅ **早期依賴明確，後期自主性強**

```
Week 0（基礎設施）：嚴格順序，每個角色只做一次
├─ Infra (0.0) → Verified by scripts/verify-platform-health.sh --preflight
├─ DevOps (0.1) → Verified by scripts/verify-platform-health.sh --smoke-test
│               → 自動導入標準 dashboard（JSON from code）
├─ Boomi Admin (0.2) → Verified by scripts/run-audit-telemetry-test.sh
└─ Boomi Dev (0.3) → 只要 Boomi Admin "ready" 就可以開始

Week 1（優化）：可以平行進行，SRE 不用等 Boomi Dev
├─ SRE: 基於預配置的標準 dashboard 定制、配置告警
├─ Boomi Dev: 獨立開發，不影響 SRE
└─ 兩者都可以看到實時 metrics（dashboard 已在 Week 0.1 就有）

Week 2+（運作）：完全平行進行，低依賴
├─ Boomi Dev: 獨立開發，不影響其他
├─ SRE: 獨立配置觀測，不影響其他
├─ Boomi Admin: 獨立管理 connectors 和 audit settings
└─ Infra Admin: On-call，只在特殊情況介入
```

### ✅ **自助式 vs 需要幫忙**

```
SRE 可以自助的：
  ✅ 定制 dashboard（add/remove panels 到預配置的版本）
  ✅ 創建新 custom dashboard（完全自訂業務指標）
  ✅ Reimport 標準 dashboard（如果改乱了）
  ✅ 配置告警規則
  ✅ 調整 metrics retention policy
  ✅ 建立 on-call rotation
  ✅ 執行故障轉移測試

Boomi Developer 可以自助的：
  ✅ 修改 process 邏輯
  ✅ 寫入 audit 日誌
  ✅ 在 SigNoz 查詢/建立自訂 dashboard
  ✅ 測試 process

Boomi Admin 可以自助的：
  ✅ 配置 MongoDB 連接字符串
  ✅ 調整 audit log TTL 設定
  ✅ 新增 connector

需要 Infra Admin 幫忙的（SRE）：
  🔴 「我要改標準 dashboard 的代碼配置」→ 提 PR，Infra Admin 審查
  🔴 「我想收集更多 MongoDB metrics」→ Infra Admin 更新 scrape job
  🔴 「Backup 失敗，確認是 IRSA 權限」→ Infra Admin 檢查 IAM role

需要 Infra Admin 幫忙的（Boomi Team）：
  🔴 MongoDB 記憶/CPU 不夠
  🔴 IRSA 權限問題
  🔴 KMS/S3 訪問失敗
  🔴 Cluster 故障轉移
```

---

## 何時 Infra Admin 可以「放手」

### ✅ **Fully Autonomous（Infra Admin 不介入）**

```
1. Boomi process 開發
2. SigNoz dashboard 定制/創建（基於預配置的標準版本）
3. Custom audit log fields 新增
4. Alert 配置
5. Query 優化（應用層）
6. 在標準 dashboard 之上的個性化定制
7. Reimport 標準 dashboard（SRE 自己可以做，不怕改壞）
```

### ⚠️ **需要 Infra Admin 介入的情況**

```
1. 資源不夠（記憶、CPU、存儲）
   → Infra Admin 修改 resource requests/limits

2. 效能問題（需要調整 Kubernetes node scale）
   → Infra Admin 執行 cluster autoscaling

3. 依賴的服務故障（MongoDB/PostgreSQL/SigNoz 掛了）
   → Infra Admin 執行故障恢復

4. 災難恢復（需要還原 S3 中的備份）
   → Infra Admin + DBA 執行恢復程序

5. 安全相關（需要更新 IAM 角色、KMS 金鑰）
   → AWS Architect + Infra Admin
```

---

## 清晰的「Done」標誌

### Week 0.0 完成後：
```bash
✅ aws ec2 describe-instances | grep uat-cluster-001
✅ aws kms describe-key --key-id uat-kms-key
✅ aws s3 ls | grep uat-backups-bucket
✅ kubectl get nodes | wc -l  (should be >= 3)
✅ bash scripts/verify-platform-health.sh --preflight
   Output: ✅ All preflight checks passed
```

### Week 0.1 完成後：
```bash
✅ kubectl get pod -n mongodb  (shows: mongodb-0, mongodb-1, mongodb-2)
✅ kubectl get pod -n coredb  (shows: oms-postgresql-coredb-1, -2, -3)
✅ kubectl get pod -n branddb  (shows: oms-postgresql-branddb-1, -2, -3)
✅ kubectl get pod -n signoz  (shows: signoz-*, clickhouse-*, kafka-*)
✅ bash scripts/verify-platform-health.sh --smoke-test
   Output: ✅ All smoke tests passed
✅ SigNoz 登入後看到標準 dashboard：
   - MongoDB Overview (已自動導入)
   - PostgreSQL Overview (已自動導入)
   - Kubernetes Pod Metrics (已自動導入)
   💡 不用等 Week 1，SRE 現在就可以開始定制
```

### Week 0.2 完成後：
```bash
✅ bash scripts/run-audit-telemetry-test.sh --test-write-read
   Output: ✅ Write successful, Read successful
✅ Boomi Admin provides: "Connection string verified and tested"
```

### Week 0.3 完成後：
```bash
✅ SigNoz 中可以查詢到 audit 日誌
✅ Boomi process 跑了至少一遍，寫入了 audit records
✅ Boomi Developer: "First process deployed to UAT"
```

### Week 1 完成後：
```bash
✅ SigNoz 中有 MongoDB/PostgreSQL/SigNoz 的自訂 dashboard
   - 基礎 dashboard 仍保持可用（git 版本控制）
   - 自訂 dashboard 增加了業務相關指標
   ✅ 可以隨時 reimport 標準版本（不影響自訂部分）
✅ PagerDuty/Slack 有配置告警
✅ 故障轉移測試已執行，結果記錄在案
✅ SRE 建立了多個環境特定 dashboard（不同 view for 不同角色）
```

---

## 常見 Pitfalls 及解決方案

### Pitfall 1：Everyone provisioning at once

```
❌ Bad: Infra Admin A、B、C 同時跑 provision.sh all
   結果: Terraform state lock 競爭，某些人失敗

✅ Solution:
   1. 確定只有一個人跑 provision.sh
   2. 使用 Slack/Jira 協調
   3. 結果通知其他人
```

### Pitfall 2：Boomi Dev 等 Infra Admin 幫忙開發流程

```
❌ Bad: Boomi Dev 等著 Infra Admin 調試問題
   結果: 浪費一周，其實只是 Groovy syntax error

✅ Solution:
   1. 開發時充分利用 SigNoz（查看實時日誌）
   2. 先自己 debug（99% 的問題在應用層）
   3. 只有確定是基礎設施問題再叫 Infra Admin
```

### Pitfall 3：Boomi Admin 修改 MongoDB 配置

```
❌ Bad: Boomi Admin 要求「降低 audit log TTL 到 1 天」
       但沒有確認對業務的影響

✅ Solution:
   1. Boomi Admin 應該問業務: 「你要保留多久的 audit 記錄？」
   2. 檢查現有 policy（可能合規要求 90 天）
   3. 再決定要不要改 TTL
```

### Pitfall 4：SRE 等 Infra Admin 優化查詢

```
❌ Bad: SRE: 「SigNoz 查詢很慢」
       Infra Admin 開始優化 ClickHouse 配置

✅ Solution:
   1. SRE 先檢查查詢本身是否可以優化（SELECT * vs specific columns）
   2. 檢查是否有適當的 index（在 SigNoz 層面）
   3. 只有確定是 ClickHouse 瓶頸再找 Infra Admin
```

---

## Summary：新 UAT 的完整故事

| 時間 | 角色 | 做什麼 | 驗證方式 | 依賴 |
|------|------|--------|---------|------|
| **Week 0.0** | Infra Admin | AWS + K8s infrastructure | `--preflight` | 無 |
| **Week 0.1** | DevOps | 3 個平台 + 導入標準 dashboard | `--smoke-test` + SigNoz UI | ← Week 0.0 |
| **Week 0.2** | Boomi Admin | 測試 audit 連接 | `--test-write-read` | ← Week 0.1 |
| **Week 0.3** | Boomi Dev | 開發業務流程 | SigNoz 查詢 | ← Week 0.2 |
| **Week 1** | SRE/Boomi Admin | 定制 dashboard、配置告警 | Custom dashboard + alerts 就位 | ← Week 0.1 (可平行 0.2/0.3) |
| **Week 2+** | Mixed | 日常運作 | 各角色獨立驗證 | ← Week 1 |

**Key Insights:**
- Provision **只做一次**（Week 0.0-0.1），由專業人員做
- **Dashboard 於 Week 0.1 自動導入**（提前可用，加快進度）
- SRE **可以平行執行**（不用等 Boomi Developer）
- **標準 dashboard 版本控制在 git**（能 reimport，不怕改壞）
- 之後每個角色都有清晰的範圍和自主性
- Infra Admin 從被動等待變成主動服務（on-call）
- Boomi 團隊可以快速迭代而不依賴基礎設施

