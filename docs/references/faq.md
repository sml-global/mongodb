# Frequently Asked Questions (FAQ)

Common questions about OMS data layer infrastructure architecture, operations, and troubleshooting.

**Related docs:**
- [Glossary](glossary.md) — jargon/acronym lookup
- [Recovery Procedures](recovery-procedures.md) — incident response procedures
- [Verification Commands](verification-commands.md) — health check commands
- [Architect Reference](../guides/architect-reference.md) — architecture and design decisions

---

## MongoDB

### Why can't MongoDB schedule 3 pods on a 2-node UAT cluster?

**Problem:** MongoDB with zone-level anti-affinity (`topology.kubernetes.io/zone`) cannot schedule 3 pods on a 2-node cluster across 2 availability zones.

Error:
```
FailedScheduling: 0/2 nodes are available: 1 Insufficient cpu, 1 node(s) didn't match pod anti-affinity rules
```

**Root cause:**
- Zone-level anti-affinity spreads pods across availability zones (AZs)
- With 2 AZs and 2 nodes, you can only fit 2 pods (one per zone)
- The 3rd pod has no valid zone to schedule in

**Solution for UAT (2-node clusters):**

Change anti-affinity from zone-level to hostname-level in `k8s/overlays/uat/patch-psmdb.yaml`:

```yaml
spec:
  replsets:
    - name: rs0
      affinity:
        antiAffinityTopologyKey: kubernetes.io/hostname  # Was: topology.kubernetes.io/zone
```

This allows multiple MongoDB pods per AZ, spreading them across **nodes** instead of **zones**.

**Important: Operator doesn't auto-update StatefulSet**

After changing the `PerconaServerMongoDB` CRD, the operator does NOT automatically update the existing StatefulSet. You must delete and recreate it:

```bash
# 1. Apply the updated config
kubectl apply -k k8s/overlays/uat

# 2. Delete StatefulSet (operator recreates with new config)
kubectl delete statefulset psmdb-rs0 -n mongodb-uat --cascade=orphan

# 3. Delete pods so they recreate under new StatefulSet
kubectl delete pod psmdb-rs0-0 psmdb-rs0-1 psmdb-rs0-2 -n mongodb-uat --force --grace-period=0

# 4. If PVC has old zone affinity, delete it too
kubectl delete pvc mongod-data-psmdb-rs0-2 -n mongodb-uat

# 5. Watch pods recreate
kubectl get pods -n mongodb-uat -w
```

**Production recommendations:**

For production, use zone-level anti-affinity with **at least 3 nodes across 3 AZs** for true high availability:

```yaml
# Production: k8s/base/psmdb-cluster.yaml
spec:
  replsets:
    - name: rs0
      size: 3
      affinity:
        antiAffinityTopologyKey: topology.kubernetes.io/zone  # Production HA
```

**UAT vs Production:**
- **UAT**: hostname-level anti-affinity (2 nodes OK)
- **Production**: zone-level anti-affinity (3+ nodes, 3+ AZs required)

**Verification:**

After applying the fix:
```bash
# Check anti-affinity was updated in CRD
kubectl get perconaservermongodb psmdb -n mongodb-uat -o jsonpath='{.spec.replsets[0].affinity.antiAffinityTopologyKey}'
# Should return: kubernetes.io/hostname

# Check pod distribution
kubectl get pods -n mongodb-uat -o wide
# Should show 3 pods across 2 nodes

# Verify MongoDB cluster health
bash scripts/verify-platform-health.sh --env uat --full 2>&1 | grep mongodb
# Should show: PASS: mongodb cluster verified
```

**Related files:**
- `k8s/base/psmdb-cluster.yaml` — base config (zone-level anti-affinity for production)
- `k8s/overlays/uat/patch-psmdb.yaml` — UAT overlay (hostname-level anti-affinity)

**Session context:** Fixed during 2026-08-05 Day 0 UAT provisioning after EKS node upgrade from 4× m6i.large to 2× m6i.xlarge. See issue #70.

---

## Network Architecture

### Why are environment CIDR blocks non-overlapping?

All OMS environments share a single `/16` CIDR block (`10.200.0.0/16`) carved into non-overlapping per-environment allocations:

| Environment | VPC CIDR | Status |
|---|---|---|
| DEV | `10.200.0.0/18` (16,384 IPs) | ✅ Active |
| UAT | `10.200.64.0/18` (16,384 IPs) | ✅ Active |
| Production | `10.200.128.0/18` (16,384 IPs) | 📋 Planned |
| SIT1 | `10.200.192.0/20` (4,096 IPs) | 📋 Planned |
| SIT2 | `10.200.208.0/20` (4,096 IPs) | 📋 Planned |
| SIT3 | `10.200.224.0/20` (4,096 IPs) | 📋 Planned |

**Rationale:** This design enables future **Transit Gateway or VPC peering** without renumbering. Overlapping CIDRs would block both options.

See [Environment Reference § Network Architecture](environment-reference.md#network-architecture) for full details.

---

## Environment Strategy

### Why does UAT use Aurora but DEV uses CNPG?

**Cost optimization decision:** DEV and SIT use in-cluster CloudNativePG (CNPG) for PostgreSQL (free beyond EBS storage), while UAT and Production use AWS Aurora (managed RDS, higher cost but enterprise support).

| Environment | PostgreSQL Engine | Rationale |
|---|---|---|
| DEV | CloudNativePG (CNPG), self-managed | Cost-cutting; dev load is light |
| SIT | CloudNativePG (CNPG), self-managed | Cost-cutting; SIT load is light |
| UAT | AWS Aurora (managed RDS) | Same engine as production for realistic validation |
| Production | AWS Aurora (managed RDS) | Enterprise support, multi-AZ HA, automated backups |

**Version alignment:** DEV/SIT track the same PostgreSQL engine version as UAT/Production where possible.

See [Environment Reference § Database Engine Split](environment-reference.md#database-engine-split) for full rationale.

### Why are MongoDB, SigNoz, and PostgreSQL separate scopes?

The three scopes have independent lifecycles:
- **MongoDB + PostgreSQL** (`all` scope) — core data layer, must provision together
- **SigNoz** (telemetry platform) — separate because it has independent failure modes
- **SigNoz Observability** (dashboards/alerts as code) — requires a live, authenticated SigNoz API

**Design decision:** Scope separation prevents cascading failures. If SigNoz is down, MongoDB/PostgreSQL remain unaffected.

See README.md § "Why These Scopes Are Separate" for full dependency diagram.

---

## Naming Convention

### Why do application namespaces have `-{env}` suffix but platform services don't?

**Convention (approved in UAT-ARCHITECTURE-ISSUES-NAMESPACE-LOGGING.md § Issue 1):**
- **Application workloads:** MUST have environment suffix (e.g., `mongodb-uat`, `signoz-dev`, `boomi-prod`)
- **Platform services:** NO suffix (e.g., `cert-manager`, `kyverno`, `flux-system`)

**Rationale:**
- **Multi-tenancy ready** — if we ever co-locate dev+uat in same cluster
- **Visual clarity** — `kubectl get pods -A` shows environment at a glance
- **Easier RBAC/network policies** — rules like "all `-uat` namespaces"
- **Prevents accidents** — harder to run dev script against UAT

**Legacy exceptions:**
- DEV uses `mongodb` and `signoz` (no suffix) for backward compatibility
- `EKS-boomi-runtime-cluster` predates convention (documented exception)

See [Component Catalog § Naming Convention](component-catalog.md#naming-convention) for full details.

---

## Safety Rules

### Why is only UAT allowed for live operations?

**CRITICAL SAFETY RULE:** Only UAT environment (account `672172129937`) is allowed for live infrastructure operations via Claude Code.

**Forbidden environments:**
- ❌ DEV (account `815402439714`) — read-only, no provision/destroy/modify
- ❌ Production (account `632674123947`) — does not exist yet, all operations forbidden
- ❌ SIT (account TBD) — does not exist yet, all operations forbidden

**Rationale:** Protects DEV, Production, and SIT environments from accidental changes during UAT work.

**Allowed operations in non-UAT:**
- ✅ Reading code, documentation, manifests
- ✅ Running tests (`pytest`)
- ✅ Viewing git history, diffs, logs
- ✅ AWS CLI read-only commands (`describe-*`, `list-*`, `get-*`)
- ❌ Any write/modify/delete operations

See CLAUDE.md § "CRITICAL SAFETY RULES" for complete details.

---

## Troubleshooting

### Why does Terraform node upgrade fail with "PodEvictionFailure"?

**Symptom:** When upgrading EKS node instance types while reducing node count (e.g., 4× m6i.large → 2× m6i.xlarge), Terraform fails with:

```
Error: waiting for EKS Node Group version update: unexpected state 'Failed'
last error: PodEvictionFailure: Reached max retries while trying to evict pods
```

**Root cause:** Multiple overlapping PodDisruptionBudgets (PDBs) prevent pod eviction when there's insufficient capacity.

**Solution:** Use the zero-downtime two-pass upgrade pattern:

1. **Pass 1:** Add new nodes WITHOUT changing instance type (increases capacity)
2. **Pass 2:** Change instance type and reduce to target size (drains old nodes)

See [Recovery Procedures § EKS Node Upgrade with PodDisruptionBudgets](recovery-procedures.md#eks-node-upgrade-with-poddisruptionbudgets) for complete troubleshooting steps.

Also see [Architect Reference § EKS Node Instance Type Upgrade](../guides/architect-reference.md#eks-node-instance-type-upgrade) for the production-safe upgrade pattern.

---

### Why does the SigNoz Helm upgrade get stuck in `pending-upgrade`?

**Symptom:** After bumping the SigNoz chart version (e.g. 0.130.1 → 0.136.1), the Flux `HelmRelease` gets stuck in `pending-upgrade`, and the `signoz-telemetrystore-migrator` pre-upgrade hook job fails or hangs.

**Root cause:** The chart's pre-upgrade migration hook runs a ClickHouse schema migration written for the *new* chart version's expectations (e.g. requiring `object_serialization_version`, added in ClickHouse 25.12.x), but Helm applies chart values before the ClickHouse operator has actually reconciled the `ClickHouseInstallation` (CHI) CR onto the new image. The migration hook races ahead of the ClickHouse upgrade and can run against a ClickHouse server that doesn't support what it needs yet.

**Fix (automated):** `scripts/provision-k8s-components.sh`'s `apply_signoz()` calls `sync_clickhouse_image_ahead_of_helm_upgrade()` before applying the SigNoz kustomize overlay. It resolves the target chart version's own default `clickhouse.image` (via `helm show values signoz/signoz --version <version>`), compares it to the live CHI's current image, and if the target is *newer*, patches the CHI directly and waits for the operator to roll the pod before letting Helm's migration hook run. See issue #125 and the originating incident in #123/#124.

**If it still gets stuck** (e.g. this automation predates your checkout, or the chart's migration expectations changed again): manually patch the CHI's pod template image to match the new chart's default, wait for `kubectl -n <namespace> get pods -l clickhouse.altinity.com/chi=<chi-name>` to show `2/2 Running`, then suspend/resume (or `helm upgrade --force`) the stuck HelmRelease.

### Why must ClickHouse image bumps only ever go forward, never backward?

**Symptom (confirmed live, see below):** Patching a running `ClickHouseInstallation` CR's pod image to an *older* tag than what's currently running causes the ClickHouse container to `CrashLoopBackOff` immediately — even between close versions (e.g. `25.12.5` → `25.5.6`).

**Root cause:** Once ClickHouse has started on a newer version, it can migrate on-disk data/metadata to that version's format. An older binary doesn't necessarily know how to read the newer format, so a downgrade is not a safe symmetric operation — it can break the server outright, not just "revert a setting."

**How this was found:** While validating the fix for the `pending-upgrade` race above, a live test in UAT (2026-08-10) intentionally patched the CHI backward from `25.12.5` to `25.5.6` to simulate stale-image drift. The ClickHouse pod immediately `CrashLoopBackOff`'d and had to be patched forward again to recover. This also uncovered a real bug in the first draft of `sync_clickhouse_image_ahead_of_helm_upgrade()`: it blindly patched toward whatever image the *configured chart version* declared as default, with no check that this was actually newer than what was already running. Because the chart version string being tested (`0.130.1`, pre-#123) is older than what UAT was actually running (`25.12.4`, from the later `0.136.1` chart), the function "corrected" ClickHouse **backward**, breaking it a second time.

**Fix:** the function now compares the current and target image tags with `sort -V` before patching. If the target is not newer, it logs a warning and skips the sync entirely, leaving ClickHouse untouched, rather than downgrading it. A same-minor-line, forward, compatible bump (`25.12.4` → `25.12.5`) was also verified live in UAT: the function correctly detected the drift, patched forward, waited for the pod to roll, and the SigNoz apply completed cleanly.

**Takeaway:** never manually patch a live `ClickHouseInstallation` CR backward to "test" or "fix" something unless you are prepared for the ClickHouse pod to crash and need a few minutes to recover it. If you need to simulate stale-image drift for testing, only ever drift within versions you've confirmed are mutually compatible (e.g. adjacent patch releases of the same minor line), never across a version where you don't know the on-disk format changed.

---

## Revision History

| Date | Changes |
|---|---|
| 2026-08-10 | Added SigNoz/ClickHouse pre-upgrade sync FAQ — `pending-upgrade` race (#125) and the forward-only ClickHouse image constraint discovered while validating the fix live in UAT |
| 2026-08-07 | Initial version — MongoDB anti-affinity, network architecture, environment strategy, naming convention, safety rules, troubleshooting |
