# Research: Terraform State Locking — S3-Native Lockfile vs DynamoDB

Status: RESEARCH — recommendation ready, no infrastructure or Terraform changes made.
Tracking issue: [sml-global/mongodb#12](https://github.com/sml-global/mongodb/issues/12)
Related: [2026-07-23 Terraform state strategy research](2026-07-23-terraform-state-strategy-and-dual-postgresql-research.md)

Sources are HashiCorp primary docs, the Terraform CHANGELOG in the `hashicorp/terraform`
repo, and the AWS S3 launch announcement. No secondary blog posts were used.

---

## 0. Current state of this repo (ground truth, verified 2026-08-03)

Every root uses `backend "s3" {}` with configuration injected at `terraform init`
time via `-backend-config` flags from `scripts/bootstrap-terraform-s3-backend.sh`.
No root uses DynamoDB locking anywhere — the choice is "locking" vs "no locking",
not "S3 vs DynamoDB".

| Root | `required_version` | Backend block | Locking |
| --- | --- | --- | --- |
| `access-governance` | `>= 1.10.0` | `versions.tf` | `use_lockfile = true` |
| `eks-access` | `>= 1.10.0` | `versions.tf` | `use_lockfile = true` |
| `eks-platform` | `>= 1.10.0` | `versions.tf` | `use_lockfile = true` |
| `workload-identity` | — | `main.tf` | `use_lockfile = var.eks_platform_state_use_lockfile` (true in all three tfvars) |
| `mongodb` | `>= 1.10.0` | `versions.tf` | **none** |
| `signoz-observability` | `>= 1.5.0` | `main.tf` | **none** |
| `dr-drill` | `>= 1.5.0` | `versions.tf` | **none** |

Correction to the framing of the original question: only `mongodb` already pins
`>= 1.10.0`. `signoz-observability` and `dr-drill` pin `>= 1.5.0` and therefore
need a `required_version` bump alongside the locking change — `use_lockfile` is
an unknown backend argument on Terraform < 1.10 and `terraform init` will fail
with a configuration error, not silently ignore it.

Also verified: `scripts/bootstrap-terraform-s3-backend.sh` already enables S3
bucket versioning (`put-bucket-versioning ... Status=Enabled`) and hard-fails if
versioning is not `Enabled`. That satisfies HashiCorp's versioning recommendation
for both locking mechanisms, so no bucket-side work is required.

---

## 1. What `use_lockfile` is

S3-native state locking. Terraform writes a lock object next to the state object
(`<key>.tflock`) and relies on **S3 conditional writes** so that only one writer
can create it. AWS launched conditional writes on 2024-08-20: a `PutObject` (or
`CompleteMultipartUpload`) carrying an `If-None-Match` header fails if the key
already exists, and AWS states this removes the need to "build any client-side
consensus mechanisms." That is the same primitive DynamoDB's conditional
`PutItem` provided, just inside S3 itself — so no second AWS service, table, or
IAM surface is needed.

Timeline from the Terraform CHANGELOG:

- **1.10.0** — "The s3 backend now supports S3 native state locking." Same entry
  notes that when combined with DynamoDB locking, "locks will be acquired from
  both sources," and that "In a future minor release of Terraform the DynamoDB
  locking mechanism and associated arguments will be deprecated."
- **1.11.0** — "S3 native state locking is now generally available. The
  `use_lockfile` argument enables users to adopt the S3-native mechanism for
  state locking," with "we encourage migrating to the new state locking
  mechanism."

So: shipped in 1.10, **GA since 1.11**, not experimental. This repo's toolchain
is Terraform v1.15.7, well past GA.

## 2. Is it a safe/sufficient replacement for DynamoDB locking?

Yes. The backend documentation now states plainly that "DynamoDB-based locking is
deprecated and will be removed in a future minor version," and that the S3 and
DynamoDB arguments may be configured simultaneously only as a migration aid. The
mechanism is not a weaker approximation of DynamoDB — conditional writes are
strongly consistent within S3, and S3 has offered strong read-after-write
consistency for all operations since December 2020, which was the historical
reason DynamoDB was needed in the first place.

Known constraints, all from HashiCorp's own backend docs:

- **Still opt-in.** "State locking is an opt-in feature of the S3 backend...
  Defaults to `false`." Omitting it means *no locking at all* — which is exactly
  the current situation for the three roots above.
- **IAM.** Requires `s3:GetObject`, `s3:PutObject`, and `s3:DeleteObject` on the
  lock file path (`<key>.tflock`). Any role that can already write the state
  object at `<key>` under a path-scoped policy typically covers this, but a
  policy that grants those actions on the *exact* state key string only will
  need the `.tflock` suffix added.
- **Bucket versioning.** "It is highly recommended that you enable Bucket
  Versioning on the S3 bucket" — already enforced here.
- **Requires Terraform >= 1.10** on every machine and CI runner that runs `init`.

No documented race-condition edge cases for the conditional-write path. The
residual failure mode is the familiar one shared with DynamoDB: an interrupted
run can leave a stale lock, cleared with `terraform force-unlock <ID>`.

## 3. Does HashiCorp recommend migrating?

Yes, unambiguously, and it is the only forward-compatible option. The 1.11
CHANGELOG says "we encourage migrating to the new state locking mechanism," and
the backend docs mark DynamoDB locking deprecated and slated for removal. No
first-party HashiCorp source recommends retaining DynamoDB for any specific case
(cross-region, consistency, or otherwise); the simultaneous-configuration
allowance is framed purely as a transition affordance for users on older
Terraform. Choosing DynamoDB for a greenfield root in 2026 would be adopting a
deprecated feature.

## 4. Migration path from a bare `backend "s3" {}` (no locking)

This is the easy case — there is no existing lock state to migrate, no table to
drain, and no dual-lock transition window. Adding `use_lockfile = true` changes
only how a run *acquires* a lock; it does not touch state format, state layout,
or the state object itself. Concretely:

- No `terraform state` migration, no `-migrate-state`, no state rewrite.
- `terraform init -reconfigure` (or the repo's normal init path) is required so
  the backend config change is picked up. The wrapper scripts re-run `init` with
  `-backend-config` flags on each provision, so the ordinary flow suffices.
- **The one real gotcha:** during rollout the protection is asymmetric. A run
  from an old checkout (no `use_lockfile`) will not create or respect the lock
  file, so it can still race a run from an updated checkout. Because these roots
  have *no* locking today, this is strictly better than the status quo, but the
  transition is not atomic — land the change across all roots at once and make
  sure CI runners and operator workstations are on Terraform >= 1.10 before
  relying on it.
- Version bump needed for `signoz-observability` and `dr-drill` (see §0).

## 5. Recommendation

**Add `use_lockfile = true` to all three roots. Do not introduce DynamoDB.**

Rationale: it matches the five roots that already do it, it is GA, it needs zero
new AWS infrastructure, the bucket already has versioning enforced by the
bootstrap script, and DynamoDB locking is deprecated. `dr-drill` in particular
performs destructive drill operations and `mongodb` holds the audit-trail data
layer — unlocked concurrent applies there are the highest-consequence gap.

Follow-up worth tracking separately: confirm the Terraform execution role's IAM
policy allows `s3:GetObject/PutObject/DeleteObject` on `<state-key>.tflock`, not
just on the exact state key.

### Literal diffs

`platform-prerequisites/terraform/mongodb/versions.tf` — version already fine:

```diff
 terraform {
   required_version = ">= 1.10.0"
-  backend "s3" {}
+  backend "s3" {
+    use_lockfile = true
+  }
   required_providers {
     aws = { source = "hashicorp/aws", version = ">= 6.0, < 7.0" }
   }
 }
```

`platform-prerequisites/terraform/dr-drill/versions.tf` — needs the version bump:

```diff
 terraform {
-  required_version = ">= 1.5.0"
-  backend "s3" {}
+  required_version = ">= 1.10.0"
+
+  backend "s3" {
+    use_lockfile = true
+  }

   required_providers {
```

`platform-prerequisites/terraform/signoz-observability/main.tf` — needs the version bump:

```diff
 terraform {
-  required_version = ">= 1.5.0"
+  required_version = ">= 1.10.0"

-  backend "s3" {}
+  backend "s3" {
+    use_lockfile = true
+  }

   required_providers {
```

## Sources

- Terraform S3 backend reference — <https://developer.hashicorp.com/terraform/language/backend/s3>
- Terraform CHANGELOG v1.10.0 — <https://github.com/hashicorp/terraform/blob/v1.10.0/CHANGELOG.md>
- Terraform CHANGELOG v1.11.0 — <https://github.com/hashicorp/terraform/blob/v1.11.0/CHANGELOG.md>
- AWS "Amazon S3 adds support for conditional writes" (2024-08-20) — <https://aws.amazon.com/about-aws/whats-new/2024/08/amazon-s3-conditional-writes/>
- Repo files verified: `platform-prerequisites/terraform/{mongodb,dr-drill,access-governance,eks-access,eks-platform,workload-identity}/`, `scripts/bootstrap-terraform-s3-backend.sh`
