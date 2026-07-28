# Phase 3 Current Status & Newbie Onboarding Guide

**Date:** 2026-07-28  
**Branch Status:** feat/phase3-workload-platforms (NOT YET MERGED TO MAIN)  
**Code Status:** ✅ COMPLETE (all infrastructure-as-code written)  
**Tests Status:** ✅ PASSING (132+ tests, all gates pass)  
**Deployment Status:** ⏳ NOT YET DEPLOYED (code ready, not yet applied to cluster)

---

## Question 1: Is All Code Completed for All Roadmap?

### ✅ **YES — Infrastructure-as-Code is COMPLETE**

**What's Complete (Phase 3 Tasks 1-7):**
- ✅ MongoDB Terraform (IRSA policy, KMS, S3 permissions)
- ✅ MongoDB GitOps (Helm releases, Kustomize overlays)
- ✅ MongoDB Handlers/Verifiers/Guards (bash lifecycle scripts)
- ✅ PostgreSQL Terraform (CloudNativePG backup configuration)
- ✅ PostgreSQL GitOps (operator, cluster CR, overlays)
- ✅ PostgreSQL Handlers/Verifiers/Guards (bash lifecycle scripts)
- ✅ SigNoz GitOps (operator, ClickHouse, UI manifests, overlays)
- ✅ SigNoz Handlers/Verifiers/Guards (bash lifecycle scripts)
- ✅ Platform Contracts (MongoDB, PostgreSQL, SigNoz technical documentation)
- ✅ Bootstrap Scripts (create secrets, setup prerequisites)
- ✅ Test Suites (132+ passing tests for static validation)

**What's NOT Complete (Intentionally Out of Scope):**
- ❌ Live Terraform Apply (infrastructure created but not deployed to AWS)
- ❌ Live Kubernetes Apply (manifests written but not deployed to EKS)
- ❌ Live SigNoz Setup (code ready, not yet applied to cluster)

**Current State:**
- All IaC code is written, tested, and ready for deployment
- Code is on feature branch (not merged to main yet)
- Awaiting final merge approval and live provisioning

---

## Question 2: Where Should a Newbie Start?

### **Newbie Onboarding Path (Suggested Journey)**

**Start Here Based on Your Role:**

| Role | Entry Point | Next Steps | Goal |
|---|---|---|---|
| **DevOps/Infra Operator** | [Environment Setup](docs/guides/environment-setup.md) | [Operator Runbook](docs/guides/operator-runbook.md) | Learn to provision & maintain the platform |
| **Boomi Process Owner** | [Audit Log Guide](docs/guides/boomi-audit-log-owner-guide.md) | [Integration Guide](docs/guides/boomi-integration-guide.md) | Learn to write processes that log correctly |
| **Infra Architect** | [Component Catalog](docs/references/component-catalog.md) | [Architect Reference](docs/guides/architect-reference.md) | Understand architecture & design decisions |
| **Engineer Maintaining This Repo** | [README.md](README.md) | [Phase 3 Implementation](docs/superpowers/plans/) | Understand repo structure & Phase 3 workflow |
| **New to Everything** | [Index/Hub](docs/index.md) | Pick your role above | Find your learning path |

**Quick Start for Operators:**

1. Read: [Environment Setup](docs/guides/environment-setup.md) (prerequisites, tools, AWS access)
2. Read: [Component Catalog](docs/references/component-catalog.md) (what exists & why)
3. Read: [Operator Runbook](docs/guides/operator-runbook.md) (how to provision step-by-step)
4. Run: `bash scripts/verify-platform-health.sh --preflight` (check if your environment is ready)

---

## Question 3: How to Know What This Repo Does?

### **What This Repository Is**

This is the **OMS (Order Management System) Data Layer** — it deploys three stateful platforms to Kubernetes:

```
┌─────────────────────────────────────────────────────────┐
│                   EKS Kubernetes Cluster                 │
├─────────────────────────────────────────────────────────┤
│                                                           │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │   MongoDB    │  │ PostgreSQL   │  │   SigNoz     │  │
│  │   (PSMDB)    │  │   (CNPG)     │  │  (Observ.)   │  │
│  │              │  │              │  │              │  │
│  │ - Repl Set   │  │ - HA Cluster │  │ - ClickHouse │  │
│  │ - PBM Backup │  │ - PG Backup  │  │ - Kafka      │  │
│  │ - IRSA Role  │  │ - IRSA Role  │  │ - UI         │  │
│  └──────────────┘  └──────────────┘  └──────────────┘  │
│                                                           │
└─────────────────────────────────────────────────────────┘
         ↓ Deployed via Flux GitOps
    ├── Platform 2 (Phase 2): EKS infrastructure
    ├── Terraform State: S3 backend
    └── AWS Identity: IRSA roles + KMS + S3
```

**What It Does:**
- Deploys MongoDB, PostgreSQL, and SigNoz to an EKS cluster
- Configures AWS Workload Identity (IRSA) for backup permissions
- Encrypts backups via AWS KMS
- Stores backups in AWS S3
- Monitors everything with SigNoz (traces, metrics, logs)
- Provides pre-destroy validation gates (guards)

**Where It Fits:**
- **Phase 1** (not in this repo): EKS cluster created via Terraform
- **Phase 2** (not in this repo): IRSA roles, KMS keys, S3 buckets, service accounts
- **Phase 3** (THIS REPO): Deploy workload platforms (MongoDB, PostgreSQL, SigNoz)
- **Phase 4** (future): Day-2 operations, scaling, recovery procedures

---

## Question 4: How to Get Started?

### **Step-by-Step Onboarding**

**IF YOU WANT TO UNDERSTAND THE CODE (No cluster required):**

1. **Read the Entry Point:**
   ```bash
   # Open in your editor
   cat docs/index.md  # What is everything?
   cat README.md      # Repo structure
   ```

2. **Pick Your Learning Path:**
   - Operator? → Read `docs/guides/environment-setup.md`
   - Architect? → Read `docs/guides/architect-reference.md`
   - Boomi User? → Read `docs/guides/boomi-audit-log-owner-guide.md`

3. **Explore the Infrastructure-as-Code:**
   ```bash
   # See what MongoDB deployment looks like
   ls -la gitops/mongodb/base/
   cat gitops/mongodb/base/kustomization.yaml
   
   # See MongoDB test suite
   cat tests/mongodb/test_documentation.py
   
   # See bootstrap scripts
   cat scripts/create-signoz-clickhouse-secret.sh
   ```

4. **Review the Contracts:**
   ```bash
   cat docs/references/mongodb-platform-contract.md
   cat docs/references/postgresql-platform-contract.md
   cat docs/references/signoz-platform-contract.md
   ```

**IF YOU WANT TO ACTUALLY PROVISION (Requires AWS + EKS cluster):**

1. Complete [Environment Setup](docs/guides/environment-setup.md)
   - AWS SSO configured
   - Kubernetes access granted
   - Tools installed (terraform, kustomize, kubectl)

2. Run Preflight Check:
   ```bash
   bash scripts/verify-platform-health.sh --preflight
   ```

3. Follow [Operator Runbook](docs/guides/operator-runbook.md):
   ```bash
   bash scripts/provision.sh all --auto-approve
   bash scripts/provision.sh signoz --auto-approve
   bash scripts/provision.sh signoz-observability --auto-approve
   ```

---

## Question 5: What's the Journey/Sequence?

### **Three Different Journeys**

**Journey A: DevOps Operator (Most Common)**

```
1. Environment Setup
   └─ Install tools (terraform, kubectl, kustomize)
   └─ Configure AWS SSO
   └─ Gain EKS cluster access

2. Read Component Catalog
   └─ Understand what MongoDB/PostgreSQL/SigNoz are
   └─ Understand IRSA, KMS, S3, PBM backups

3. Read Operator Runbook (Step-by-Step)
   └─ Understand provisioning order
   └─ Understand how to troubleshoot
   └─ Understand day-2 operations

4. Run Preflight Check
   └─ Verify AWS permissions
   └─ Verify Kubernetes access
   └─ Verify prerequisites

5. Provision Platform (Phase 3)
   └─ Run: bash scripts/provision.sh all --auto-approve
   └─ Watch: SigNoz dashboards populate
   └─ Verify: bash scripts/verify-platform-health.sh --smoke-test

6. Maintain & Monitor (Day 2)
   └─ Run daily health checks
   └─ Manage backups (PBM, CNPG)
   └─ Review SigNoz metrics/alerts
```

**Journey B: Boomi Process Developer (Different)**

```
1. Skip infrastructure setup (DevOps handles it)

2. Read Boomi Integration Guide
   └─ Learn audit logging API
   └─ Learn metric/tracing API
   └─ Learn error handling

3. Read Audit Log Contract
   └─ Understand what fields to send
   └─ Understand validation rules
   └─ Understand failure behaviors

4. Write Your Boomi Process
   └─ Import audit logging library
   └─ Call writeAuditLog() at key points
   └─ Add tracing (stopwatch) around business logic

5. Test Locally
   └─ Write unit tests with mocked backends

6. Deploy to Cluster
   └─ DevOps deploys your process to Boomi
   └─ Logs appear in MongoDB audit collection
   └─ Traces appear in SigNoz dashboard
```

**Journey C: Repository Maintainer (This Repo)**

```
1. Read AGENTS.md (this file)
   └─ Understand scope rules & safety gates
   └─ Understand when to use superpowers skills

2. Read Phase 3 Plan
   └─ Understand why 7 tasks
   └─ Understand design-first discipline

3. Read Phase 3 Design Documents
   └─ Gatekeeper evaluations
   └─ Why each component was designed a certain way
   └─ What guard rails exist

4. For Bug Fixes/New Features
   └─ Follow TDD (write test first)
   └─ Run all 4 validation gates
   └─ Use gatekeeper 4-perspective review
   └─ Create atomic commits

5. For Merging to Main
   └─ Ensure all tests pass (132+)
   └─ Ensure all gates pass (terraform, kustomize, git status)
   └─ Get AWS/DevOps/Architect approval
   └─ Merge with structured commit message
```

---

## Question 6: What Are the Tests Actually Doing?

### **IMPORTANT: Tests are NOT Live Provisioning**

**What Tests ARE Doing (Static Validation):**

| Test Type | Example | What It Validates | Provisions? |
|---|---|---|---|
| **File Existence** | `test_versions_tf_exists()` | Terraform file exists on disk | ❌ NO |
| **Syntax Validation** | `terraform fmt -check && terraform validate` | Terraform code has correct syntax | ❌ NO (checks locally) |
| **Manifest Validation** | `kustomize build gitops/mongodb/overlays/uat` | Kustomize manifests render to valid YAML | ❌ NO (renders only) |
| **Content Verification** | `test_prerequisites_includes_irsa_role()` | Contract doc contains "IRSA role" keyword | ❌ NO |
| **Import Validation** | `import pathlib` + file exists | Python files can be imported | ❌ NO |
| **Copy-Paste Detection** | `grep -irE "mongodb\|postgresql"` in SigNoz code | No cross-scope contamination | ❌ NO |

**What Tests are NOT Doing:**

❌ Creating AWS resources (IRSA roles, KMS keys, S3 buckets)  
❌ Provisioning Kubernetes pods  
❌ Actually deploying to EKS  
❌ Creating databases or ClickHouse instances  
❌ Testing real backup/recovery workflows  
❌ Testing actual SigNoz telemetry ingestion  

### **Why Tests Are Static, Not Live**

**Reason 1: Safety**
- Live provisioning to AWS is dangerous (costs money, creates real resources)
- Tests must be safe to run locally, in CI/CD, without a real cluster

**Reason 2: Speed**
- Terraform validate takes seconds
- Actual `terraform apply` takes 10+ minutes per component
- Static tests run in CI faster

**Reason 3: Isolation**
- Each developer/CI run must not interfere with others
- Static tests have zero side effects

**Reason 4: Verification**
- Tests verify code is ready to deploy
- Actual deployment is a separate, manual step (with approval gates)

### **When Are Things Actually Deployed?**

```
Local Development:
  1. Engineer writes code
  2. Engineer runs tests (static validation)
  3. All tests pass → code is ready
  4. Engineer commits to feature branch

CI/CD Pipeline:
  1. PR opened (tests run automatically)
  2. All 4 gates must pass (tests + terraform + kustomize + git)
  3. Code review approved

Manual Deployment (Operator):
  1. Operator reads Runbook
  2. Operator runs: bash scripts/provision.sh all
  3. Terraform ACTUALLY applies to AWS (creates resources)
  4. Flux ACTUALLY applies to Kubernetes (deploys workloads)
  5. Bash scripts ACTUALLY create secrets
  6. Operator verifies: bash scripts/verify-platform-health.sh --smoke-test
```

---

## Current State Summary

| Item | Status | Location |
|---|---|---|
| **Terraform Code** | ✅ Written + Tested | `platform-prerequisites/terraform/{mongodb,postgresql,signoz}/` |
| **GitOps Manifests** | ✅ Written + Tested | `gitops/{mongodb,postgresql,signoz}/` |
| **Bash Scripts** | ✅ Written + Tested | `scripts/` + `scripts/lib/` |
| **Test Suites** | ✅ 132+ Passing | `tests/{mongodb,postgresql,signoz}/` |
| **Documentation** | ✅ Complete | `docs/references/` + `docs/guides/` |
| **Code Review** | ✅ 4-Perspective Approval | All gatekeepers CLEAR |
| **Merged to Main** | ⏳ PENDING | Currently on feat/phase3-workload-platforms branch |
| **Deployed to Cluster** | ⏳ NOT YET | Awaiting operator to run provisioning scripts |

---

## For a Newbie: Recommended First Task

**If you want to understand this repo without touching production:**

1. **Read** `docs/index.md` (5 min)
   - Understand what this repo does
   - Pick your role

2. **Read** `docs/references/component-catalog.md` (15 min)
   - Learn about MongoDB, PostgreSQL, SigNoz
   - Learn what each does

3. **Explore** the Terraform code (20 min)
   ```bash
   # Look at MongoDB Terraform
   cat platform-prerequisites/terraform/mongodb/README.md
   cat platform-prerequisites/terraform/mongodb/main.tf
   ```

4. **Explore** the GitOps manifests (20 min)
   ```bash
   # Look at MongoDB deployment
   cat gitops/mongodb/base/kustomization.yaml
   kustomize build gitops/mongodb/overlays/uat  # See what renders
   ```

5. **Read** a test file to understand validation (15 min)
   ```bash
   cat tests/mongodb/test_documentation.py
   ```

**Total Time: ~1.5 hours** to understand the full scope without any provisioning.

---

## Next Steps for This Conversation

**Option 1: Merge Phase 3 to Main**
- Run the final validation gates
- Create atomic commit
- Merge to main
- Clean up worktree

**Option 2: Explore Phase 3 Code First**
- I can walk you through specific components
- Show you how the IaC works
- Explain design decisions

**Option 3: Plan for Actual Deployment**
- Discuss prerequisites (AWS account, EKS cluster)
- Discuss how to run provisioning scripts
- Discuss day-2 operations

**What would you like to do?**
