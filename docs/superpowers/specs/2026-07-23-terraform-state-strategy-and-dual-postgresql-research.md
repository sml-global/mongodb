# Research & Options: Terraform State Strategy and Dual PostgreSQL Layout

Status: RESEARCH — awaiting your decision. No infrastructure, Terraform, or
Kubernetes changes have been made. This document exists so you can pick a
direction before any implementation begins.

Author context: senior-architect comparison of this repository against
`../../Boomi/boomi-infra/infra`, cross-checked against the already-approved
[unified environment provisioning design](2026-07-22-unified-environment-provisioning-design.md).

---

## 1. The Two Questions You Asked

1. **Dual databases.** Provision two PostgreSQL clusters — a **brand** database
   and the **core OMS** database — because their IAM boundaries differ and their
   admin passwords must differ.
2. **State strategy.** Is this repo's Kubernetes/Terraform structure good
   enough? Compare it to how `boomi-infra/infra` uses Terraform + scripts.
   Should all Terraform share one state (apply everything together), or stay
   split per component? What are the real pros and cons? If the difference is
   small, provision "in one go" by the EA / infra admin.

You also confirmed: **core and brand are independent — provision order does not
matter (they can run in parallel).**

---

## 2. Ground Truth: How Each Repo Actually Works

### 2.1 Boomi `boomi-infra/infra/tf`

- **One Terraform root, one state per environment.** A single root composes ten
  modules — `network`, `iam`, `eks`, `node_groups`, `security`, `efs`,
  `addons`, `k8s_autoscaler`, `k8s_storage`, `k8s_workload` — chained with
  explicit `depends_on`.
- **AWS and Kubernetes resources live in the same root.** The `kubernetes`
  provider is configured from `module.eks` outputs (exec auth), and
  `k8s_storage` / `k8s_autoscaler` / `k8s_workload` are Terraform-managed.
- **Locking:** S3 backend **plus a DynamoDB lock table**.
- **Env separation:** `envs/<env>/terraform.tfvars` + `backend.<env>.hcl`.
- **Scripts:** `aws_sso_helper.sh`, `terraform_env.sh` (init + plan/apply only —
  destroy is manual), `bootstrap_backend.sh` (S3 + DynamoDB), and
  `discover_current_network.sh`.
- **Their own documented limitation:** because AWS and Kubernetes share one
  root, a full `plan` requires a valid Boomi install token *even when you only
  want to review AWS resources.* This is the structural cost of one combined
  state.

### 2.2 This repo (`mongodb`)

- **Split state — one state key per component.** The approved design lists
  independent state keys: `eks-platform`, `access-governance`, `eks-access`,
  `workload-identity`, `mongo`, `postgresql-core`, `postgresql-brand`,
  `signoz-observability`. Today, [scripts/provision.sh](../../../scripts/provision.sh)
  already provisions `mongodb` and `pg` as **separate states** and `all` chains
  them.
- **Kubernetes is not in Terraform.** Workloads are kustomize
  ([k8s/base](../../../k8s/base), [k8s/overlays/dev](../../../k8s/overlays/dev))
  plus GitOps/Flux ([gitops/](../../../gitops)) and Helm. Terraform owns only
  cloud prerequisites (VPC wiring, IAM, RDS, PBM bucket, Pod Identity).
- **Locking:** **native S3 lockfiles** (Terraform ≥ 1.10) — no DynamoDB table.
- **One-command experience already exists:** `provision.sh all` walks the
  dependency graph and provisions everything with a single operator command,
  *despite* split state.

### 2.3 The current single PostgreSQL root

[platform-prerequisites/terraform/postgresql/main.tf](../../../platform-prerequisites/terraform/postgresql/main.tf)
is **one** Aurora cluster with **one** `db_master_password` variable. The
reusable `postgresql-cluster` module and the `postgresql-core` /
`postgresql-brand` roots that the approved design calls for **do not exist
yet.** Requirement 1 is therefore a *build-out of an already-approved design*,
not a new decision.

---

## 3. The Core Insight: Two Orthogonal Axes

The comparison only makes sense if we separate two things that are easy to
conflate:

- **Axis A — State granularity:** one combined state vs. many per-component
  states.
- **Axis B — Operator experience:** "EA runs one command and everything is
  provisioned."

**These are independent.** `provision.sh all` already delivers Axis B (one
command, one-go, EA-driven) *with* split state. Collapsing state is **not**
required to get the one-command experience you want.

A third hidden axis is **where Kubernetes lives**: Boomi puts K8s workloads
inside Terraform state; this repo keeps them in GitOps/kustomize. That choice
drives most of the risk difference below.

### 3.4 The Real Question: What Is the Right *Unit* of State?

The choice is not binary — "one global state" vs. "a state per resource." Both
extremes are wrong. The mature principle is:

> **A Terraform state boundary should equal a lifecycle + ownership + blast-radius boundary.**

Put resources in the *same* state when they are created, changed, and destroyed
together, owned by the same people, and share a blast radius. Put them in
*different* states when any of those three differ.

Seen this way, Boomi and this repo are **not actually in conflict** — they are
right-sizing differently because their platforms differ:

- Boomi provisions essentially **one** deliverable (a molecule on its EKS), so a
  single state is correctly right-sized for them.
- This repo already applies the *same* principle internally: the `eks-platform`
  scope bundles VPC + EKS + node groups + add-ons + EFS into **one** state (a
  Boomi-style single root at the platform layer, because those share a
  lifecycle), while keeping `mongo`, `postgresql-core`, `postgresql-brand`, and
  `signoz-observability` in **separate** states because they do not.

So Decision 1 is really: *for the OMS platform, where do the
lifecycle / ownership / blast-radius boundaries actually fall?* Requirement 1
answers part of it directly — core and brand have **different IAM and different
admin passwords**, i.e. different ownership and different blast radius, which is
the textbook signal to keep them in separate states.

### 3.5 The Deciding Lens: Ownership, Permission, and Change Cadence

You proposed reasoning from *who is allowed to run it* and *when / how often it
changes*, rather than from Terraform mechanics. **This is the strongest lens,
and it should drive the decision.** It refines §3.4: the best state boundary is
the one that matches a **permission plane** (who holds the credentials) and a
**change cadence** (how often it legitimately changes). Map every scope onto
those two and the state boundaries fall out on their own.

| Plane | Scopes | Credential it needs | Owner | Change cadence | Blast radius | Phase |
|---|---|---|---|---|---|---|
| **1. Base infrastructure** | `backend`, `eks-platform`, `access-governance`, `eks-access`, `workload-identity`, `mongodb` prereqs (PBM bucket/IAM/namespace), `postgresql-core`, `postgresql-brand` | **Elevated AWS IAM** (VPC, EKS, IAM, RDS, S3, KMS, Pod Identity) | **Infra Admin only** | Rare (build / major change) | High | Day-0 / Day-1 |
| **2. Platform workloads (GitOps)** | Percona operator, MongoDB cluster CRs, Kyverno policies, SigNoz platform install, `platform-controllers` | Cluster RBAC (`kubectl` / Flux) — **not** cloud admin | Platform / DevOps operator (mostly Flux auto-reconcile) | Medium; continuous reconcile | Cluster-scoped | Day-1 / Day-2 |
| **3. Observability config** | `signoz-observability` (dashboards, alerts, thresholds, notification channels) | **SigNoz API token only** | Observability / app team | **High** (tuned frequently) | Tiny (config only) | Day-2, after base is up |
| **4. Data-access governance (SoD)** | `database-access-core`, `database-access-brand`, `mongodb-access` | DB admin creds (not necessarily AWS admin) | **DBA / data owner — deliberately a different person from the infra admin who created the cluster** | Low–medium | Per-database | Day-1 / Day-2 |

**"Base infra" = Plane 1**: the Terraform-owned AWS layer plus MongoDB platform
prerequisites, owned solely by the Infra Admin. Planes 2–4 are day-2 surfaces
owned by *other* staff, and — tellingly — most of them are **not even Terraform**
(GitOps for Plane 2, API-as-code for Plane 3).

Why this lens is decisive:

- If all of this lived in **one combined Terraform state**, then editing a SigNoz
  alert threshold (Plane 3 — frequent, low-risk) would require `terraform apply`
  rights on a state that also contains the VPC, EKS, IAM, and **both DB master
  passwords**. You would be handing dashboard editors de-facto platform-admin
  and read access to every database secret. That is the opposite of least
  privilege.
- **Split state lets you attach per-state-key backend IAM** (S3/KMS access
  scoped to each `*.tfstate`), so each plane holds exactly the credentials it
  needs — and nothing more.
- For an **audit-log platform** specifically, being able to prove "dashboard
  editors cannot touch the database or IAM" is a segregation-of-duties and
  compliance win, not just an ergonomics one.
- Requirement 1 lives across two planes on purpose: the Infra Admin *creates*
  core and brand (Plane 1), but *who may log in* is governed separately per
  database (Plane 4) — core denies Boomi Admin / Process-Owner, brand grants DB
  admin. That separation is only clean if the states are separate.

Honest counter-point (so this isn't one-sided): permission boundaries **can**
also be enforced on a combined state via CI/CD — humans hold no credentials and
only trigger pipelines they're authorized for. But that pushes all least
privilege into pipeline gymnastics, still can't stop an authorized run from
touching unrelated resources, and still co-locates every secret in one state
file. Split state enforces the same segregation at the storage layer, simply.

**Conclusion of the lens: it confirms Option B.** Base infra (Plane 1) is one
high-privilege, low-cadence, Infra-Admin domain — correctly one (or a few coarse)
states. Planes 2–4 are different owners, credentials, and cadences — correctly
separate, and mostly not Terraform at all. The reason to split provisioning is
exactly what you described: **dashboards and access grants change after the base
is up, by different people, so they must not share a blast radius or a
credential with the base infra.**

---

## 4. Decision 1 — Terraform State Strategy

### Option A — Keep split state + one-command `all` (current model)

One state per component; `provision.sh all` orchestrates the dependency graph.

**Pros**
- Small blast radius: a bad apply or corrupt/locked state in one component
  cannot damage VPC, EKS, both databases, and telemetry at once.
- **Independent failure domains for credentials, compute, and data** — directly
  satisfies requirement 1 (core vs. brand can be built, changed, or destroyed
  independently). Note: this is *isolated compute and credential* isolation, not
  full network isolation — both clusters still share the underlying VPC/network
  blast radius unless separately networked (see §5).
- **Alpha-provider quarantine:** the SigNoz API provider (which has already
  produced multiple provider bugs) stays in its own state and cannot block a
  VPC/EKS change.
- **Least privilege by plane:** the EA/infra-admin plane (VPC/IAM/EKS) and the
  app-data plane (DB roles, dashboards) can be governed by *who may touch which
  state*.
- Faster, targeted plans; concurrent work on unrelated components; per-component
  retention gates on destroy.
- **Still one-go** via `all`.

**Cons**
- Cross-state references need remote-state data sources or passed inputs.
- Ordering is orchestrated (the `all` graph) rather than automatic within one
  Terraform graph.
- More backend keys to manage.

### Option B — Hybrid: split state, adopt Boomi's cleaner conventions

Same split-state safety as Option A, but borrow the genuinely better parts of
Boomi's layout: **module composition inside each root** (network/eks/iam/etc.),
**per-env `backend.<env>.hcl` + `tfvars`**, and the **SSO-helper + account-guard
+ backend-bootstrap** script pattern.

**Pros:** all of Option A, plus cleaner reuse, consistent env handling, and a
familiar script ergonomics that matches what your team already knows from Boomi.

**Cons:** a modest one-time refactor of root layouts and env-config conventions;
must reconcile Boomi's DynamoDB-lock habit with this repo's native S3 lockfiles
(recommend keeping native S3 lockfiles).

### Option C — Single combined state (Boomi-style), amend the design

One root, one state, `terraform apply` provisions AWS + databases (+ possibly
K8s) together.

**Pros**
- Simplest mental model; Terraform resolves ordering automatically; direct
  cross-resource references (no remote-state wiring); closest to Boomi
  familiarity.

**Cons (heavy for *this* platform)**
- **Maximum blast radius:** one state now spans VPC, EKS, both Auroras, and
  telemetry.
- **Provider contamination:** an alpha SigNoz provider crash can block unrelated
  infrastructure changes.
- **Inherits Boomi's documented pain:** you'd need every credential/endpoint
  present just to *plan* anything (Boomi's README calls this out for their
  shared AWS+K8s root).
- **K8s-in-TF day-2 problems** if K8s is folded in: chicken/egg (provider needs
  the cluster before plan), drift, messy destroys — the very reasons this repo
  chose GitOps/Flux.
- **Least privilege lost;** no concurrency (one lock); all-or-nothing destroy
  that cannot honor per-component retention gates.
- **Amends an approved design:** the unified spec's Non-Goals *explicitly
  reject* "combining all components into one Terraform state" and "copying the
  Boomi infra implementation." Choosing C requires updating that spec and
  formally accepting the risks above.

### Decision drivers at a glance

| Driver | A (split) | B (hybrid) | C (combined) |
|---|---|---|---|
| One-command EA provisioning | Yes (`all`) | Yes (`all`) | Yes |
| Blast radius of a bad apply | Smallest | Smallest | Largest |
| Core/brand independence (req 1) | Native | Native | Manual/`-target` only |
| Alpha SigNoz provider isolation | Yes | Yes | No |
| Least-privilege by plane | Yes | Yes | No |
| **Secret exposure in state** (DB admin passwords) | Confined to DB states; few readers | Confined to DB states | Co-located with everything; every state reader sees both DB passwords |
| **Provider-version upgrade coupling** | Per-root, independent cadence | Per-root | Upgrading aws/kubernetes/SigNoz forces a re-plan of the whole platform |
| **Lock contention / parallel ops** | Per-component locks | Per-component | One lock — any op blocks all others |
| **State size & plan/refresh time** | Small per root | Small | Grows monolithic; slows as resources accumulate |
| **DR / restore granularity** | Restore one component's state | Per component | All-or-nothing state restore |
| **Team RBAC / ownership mapping** | Natural (DB team owns DB states) | Natural | Cannot partition one state by team |
| **State refactor / import risk** | Localized | Localized | Every `state mv`/import touches the shared file |
| Plan/apply speed on small change | Fast | Fast | Slow (whole graph) |
| Cross-component references | Remote-state data sources (runtime coupling) | Remote-state | Direct references (compile-time safety) |
| Cross-component wiring effort | Higher | Higher | Lowest |
| Automatic dependency ordering | Orchestrated (`all` graph) | Orchestrated | Terraform graph (automatic) |
| Concurrent independent work | Yes | Yes | No |
| Destroy granularity + retention gates | Per component | Per component | All-or-nothing |
| Consistency with approved design | Full | Full (additive) | Requires amendment |
| Familiarity vs. Boomi | Medium | High | Highest |

### Steelman: when combined state (Option C) is genuinely the right call

To be fair to the model you're leaning toward, combined state wins when:

- The platform is **one tightly-coupled deliverable** with a single lifecycle
  and a single owning team (Boomi's exact situation).
- Cross-component references dominate and **stale remote-state outputs** are a
  bigger real risk than blast radius (combined state gives compile-time
  reference safety).
- The team is small and the **operational cost of maintaining an orchestrator
  dependency graph** outweighs the isolation benefits.
- Every component shares the **same provider set and upgrade cadence**, so
  version coupling is a non-issue.

Notably, this repo already *honors* this steelman where it applies: `eks-platform`
is a single combined-state root precisely because VPC + EKS + node groups +
add-ons + EFS are one tightly-coupled, same-owner, same-lifecycle deliverable.
The disagreement with Boomi is only about whether the **databases and telemetry**
belong in that same state — and requirement 1 (different IAM, different
passwords, isolated compute/credential domains) says they do not. Note that a
shared VPC/network blast radius remains regardless of state strategy; state
isolation does not by itself give network isolation (see §5 for the precise
boundary each database gets).

### Recommendation

**Option B (split state, coarse-grained per layer, plus Boomi's cleaner module
and per-env conventions).** The ownership / permission + change-cadence lens
(§3.5) is the primary driver: the split falls out of *who is allowed to run each
plane* and *how often it changes*, and it is the strongest argument of all.
Rationale, in order of weight:

1. **Least privilege by permission plane (§3.5).** Only the Infra Admin should
   hold rights to the base-infra states; dashboard/alert editors and DBAs must
   not. Combined state makes that nearly impossible; split state enforces it at
   the backend-IAM layer.
2. "Provisioned in one go by EA/infra-admin" is **already delivered** by
   `provision.sh all` — collapsing state adds nothing to the goal you actually
   care about.
2. Requirement 1 is a hard signal *against* combining: two DBs with different
   IAM and different admin passwords are, by definition, different
   ownership + blast-radius boundaries. Combined state would also **co-locate
   both DB master passwords with your whole platform state**, forcing every
   state reader into scope of those secrets.
3. The alpha SigNoz provider must stay quarantined; combined state couples its
   upgrade/crash surface to VPC/EKS.
4. The repo already right-sizes correctly (`eks-platform` combined; data +
   telemetry split). The improvement worth making is **cleaner module and
   per-env conventions from Boomi (Option B)**, not collapsing state.

Choose Option C only if you consciously accept the steelman trade-offs above
*and* the design amendment — in which case I would keep Kubernetes in GitOps and
still quarantine SigNoz, i.e. "combined AWS platform+data state" rather than
"literally everything," to bound the damage.

---

## 5. Decision 2 — Dual PostgreSQL Layout (core + brand)

This is already approved in the unified design; only the implementation is
pending. Under Option A/B it maps cleanly:

- **One reusable module** `modules/postgresql-cluster` (built from today's
  single-root resources) — no provider/backend lock-in.
- **Two thin roots** calling that module:
  - `postgresql-core` — core OMS database.
  - `postgresql-brand` — brand database.
- **Separate state keys:** `oms/<env>/postgresql-core.tfstate` and
  `oms/<env>/postgresql-brand.tfstate` (isolated compute and credential
  domains — both still share the underlying VPC/network unless separately
  networked; state isolation bounds Terraform blast radius, not network blast
  radius).
- **Different admin passwords:** each root references its **own master-secret**
  entry (distinct Secrets Manager references / distinct `db_master_password`
  inputs). No password is shared between clusters.
- **Different IAM boundary:** core OMS **denies** Boomi Admin / Process-Owner
  login+grant; brand **grants** DB admin. Enforced in the per-cluster
  `database-access-core` / `database-access-brand` configuration scopes, plus
  distinct security groups, subnets, cluster identifiers, DB names, monitoring
  dimension (`core` / `brand`), and final-snapshot IDs.
- **Order:** independent — the `all` graph runs them in parallel (per your
  decision).

Under Option C, both clusters would live in the single state and independence
would be reduced to `-target` discipline — a downgrade against your stated
requirement that their IAM and lifecycles differ.

---

## 6. Is the Kubernetes Structure "Good Enough"?

Assessment: **structurally sound, but currently MongoDB-centric.** Today
[k8s/base](../../../k8s/base) + [k8s/overlays/dev](../../../k8s/overlays/dev) +
[gitops/](../../../gitops) form a clean kustomize + Flux model. The approved
design already extends this with `platform-controllers` (cert-manager, Kyverno,
Flux via Helm) and `boomi-runtime` (versioned manifests) plus dev/uat overlays.

Recommendation: **keep Kubernetes in GitOps/kustomize; do not move it into
Terraform** (that is the one Boomi pattern to avoid). The improvement worth
making is completing the overlay/component set the design already defines, not
changing the ownership model.

---

## 7. The README User Journey — Is It Correct, and How Do We Cope?

You asked whether the documented journey in [README.md](../../../README.md) is
correct and how we should cope with it. Assessment:

### 7.1 What the journey gets right (and why it matters for Decision 1)

The README's onboarding flow and "Why These Scopes Are Separate" section are
**internally consistent and well-argued** for separation. Its stated rationale —
failure isolation, dependency correctness, operational flexibility, lower blast
radius — is *exactly* the argument for split state. The four-step full-stack
sequence (`all` → `signoz` → `signoz-observability` → `verify --smoke-test`)
correctly encodes a real dependency: `signoz-observability` needs a live SigNoz
API that does not exist until `signoz` is healthy. **This documented journey is
the strongest existing evidence that split state is intentional, not accidental**
— and it argues against Option C.

### 7.2 Where the journey is now incorrect / incomplete

Two gaps, both created by the direction of this work, not by past mistakes:

1. **Missing platform-foundation stage.** Today `provision.sh all` = MongoDB +
   PostgreSQL data-layer prerequisites only; it *assumes the EKS cluster already
   exists*. If the EA / infra-admin is to provision "in one go" end-to-end, the
   journey is missing an earlier stage (`backend` → `eks-platform` →
   `access-governance` → `eks-access`) that the approved design defines but the
   README does not yet show.
2. **`pg` scope no longer maps 1:1.** Requirement 1 splits PostgreSQL into
   `postgresql-core` + `postgresql-brand`. The README's single "PostgreSQL
   only" path and its "`all` = Mongo + PG" description become inaccurate the
   moment two clusters exist.

### 7.3 How to cope (recommended)

Keep the layered journey — it is correct in spirit — and evolve it:

- **Add an explicit "Platform Foundation" stage** ahead of the data-layer `all`,
  owned by the EA / infra-admin, so the end-to-end one-command story is honest
  about what it provisions.
- **Update `all` / `pg` semantics** to canonical scope names: `all` fans
  PostgreSQL out to `postgresql-core` + `postgresql-brand` (run in parallel per
  your order decision); replace the single "PostgreSQL only" row with core and
  brand rows.
- **Preserve the four-step full-stack sequence and the "separation is
  intentional" rationale** verbatim — it is correct and it is your best
  documented justification for split state.
- Update the README **Onboarding Flow**, **Provisioning Choices**, and **Why
  These Scopes Are Separate** tables in the same change so the journey, the
  scopes, and the state model stay in agreement.

This journey rework is required under Option A/B and is *also* required under
Option C (the foundation stage and dual-DB rename are independent of the state
decision) — so it is safe to align on the journey now regardless of Decision 1.

---

## 8. What to Borrow vs. Not Borrow From Boomi

**Borrow:** module composition inside each root; per-env `backend.<env>.hcl` +
`tfvars`; SSO-helper + account-guard + backend-bootstrap script ergonomics.

**Do not borrow:** Kubernetes workloads inside Terraform state; DynamoDB lock
table (native S3 lockfiles are simpler); a single combined state.

### 8.1 Concrete Target Structure (Boomi conventions applied to this repo)

This is the design to build against, derived from the Boomi patterns above and
kept consistent with the approved
[unified design](2026-07-22-unified-environment-provisioning-design.md). It does
**not** collapse state; it applies Boomi's *module + per-env + guard-script*
conventions on top of the existing split-state model.

Terraform layout under `platform-prerequisites/terraform/`:

```text
reusable/                      # existing shared module code (no provider/backend lock-in)
modules/
  postgresql-cluster/          # NEW — extracted from today's single postgresql/ root
    main.tf  variables.tf  outputs.tf
postgresql-core/               # NEW thin root -> module.postgresql-cluster (core OMS inputs)
  main.tf  variables.tf  outputs.tf  providers.tf  versions.tf  (backend "s3" {})
postgresql-brand/              # NEW thin root -> module.postgresql-cluster (brand inputs)
  main.tf  variables.tf  outputs.tf  providers.tf  versions.tf  (backend "s3" {})
eks-platform/ access-governance/ eks-access/ mongodb/ signoz-observability/   # existing / per approved design
envs/
  dev/   <component>.tfvars   backend.dev.hcl
  uat/   <component>.tfvars   backend.uat.hcl
  account_ids.env.example    sso.env.example
```

Script conventions (adopted, native-S3-lock preserved):

- A shared `scripts/lib/aws-env.sh` modeled on Boomi's `aws_sso_helper.sh`:
  `resolve_{account,region,profile}_for_env` + `ensure_aws_sso_session` +
  caller-account assertion before any backend access. **No DynamoDB** — keep
  `backend "s3" { use_lockfile = true }`.
- `provision.sh` / `destroy.sh` / `verify-platform-health.sh` gain
  `--env <dev|uat>` and a per-scope state-key map (already mandated by the
  approved design), each scope initialized with its own `backend.<env>.hcl`.

Mapping to the four permission planes (§3.5) — each cell is a distinct backend
state key with plane-scoped backend IAM:

| Plane | Terraform roots / owners | State keys (`oms/<env>/*.tfstate`) |
|---|---|---|
| 1 Base infra (Infra Admin) | `eks-platform`, `access-governance`, `eks-access`, `workload-identity`, `mongodb`, `postgresql-core`, `postgresql-brand` | one key per root |
| 2 Platform workloads | GitOps (`k8s/` + `gitops/` via Flux) — **not Terraform** | none |
| 3 Observability config | `signoz-observability` (SigNoz API token only) | `signoz-observability` |
| 4 Data-access (SoD) | `database-access-core`, `database-access-brand`, `mongodb-access` — guarded DB config, own creds | none / small state per approved design |

Dual-PostgreSQL specifics (requirement 1):

- **One reusable module** parameterized by cluster identifier, DB name, master
  secret reference, subnets/SG, monitoring dimension (`core` / `brand`), and
  final-snapshot ID.
- **`postgresql-core`** — distinct master secret; core OMS access governed in
  `database-access-core` (Plane 4) which **denies** Boomi Admin / Process-Owner
  login+grant.
- **`postgresql-brand`** — distinct master secret; `database-access-brand`
  **grants** DB admin.
- The two roots run **in parallel** (independent — per your order decision).

---

## 9. Decisions For You To Pick

1. **State strategy:** Option A (keep split), **Option B (split + adopt Boomi
   conventions — recommended)**, or Option C (combined state, amend the design
   and accept the steelman trade-offs in §4).
2. **If Option C:** confirm you accept the secret-co-location, blast-radius,
   alpha-provider-coupling, and least-privilege trade-offs, and that I should
   first update the approved spec's Non-Goals before any build. Also confirm the
   bound: "combined AWS platform+data state" vs. "literally everything."
3. **Dual PostgreSQL:** confirm the module + two-root + two-secret + two-IAM
   layout in §5 (independent / parallel order already confirmed).
4. **User journey (independent of Decision 1):** approve reworking the README to
   add the Platform Foundation stage and split `pg` → `postgresql-core` +
   `postgresql-brand`, preserving the existing four-step sequence and
   "separation is intentional" rationale.
5. **Scope of first implementation:** UAT-first (per approved design) or
   dev-first — and whether this belongs in the current
   `feat/uat-access-foundation` worktree or a new branch.
6. **Ownership / permission model (§3.5):** confirm the four-plane split — Infra
   Admin owns all base-infra Terraform + MongoDB; Platform Operator owns
   GitOps/Flux; Observability owner owns SigNoz dashboards/alerts; DBA owns
   database-access grants — and that per-plane least privilege (segregation of
   duties) is a hard requirement. This is the strongest argument for split
   state; confirming it effectively settles Decision 1 toward Option B.

No code, Terraform, or Kubernetes changes will be made until you choose.
