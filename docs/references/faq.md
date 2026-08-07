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

## Revision History

| Date | Changes |
|---|---|
| 2026-08-07 | Initial version — MongoDB anti-affinity, network architecture, environment strategy, naming convention, safety rules, troubleshooting |
