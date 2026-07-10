# Component Catalog

Every platform component deployed or managed by this repository. For each component: what it is, why we use it, how it helps, who owns it, and what depends on it.

Not sure what a term in this doc means (CRD, HelmRelease, Pod Identity, ...)? See the [Glossary](glossary.md).

**When to consult this document:**
- Understanding what a component does before provisioning or troubleshooting
- Planning upgrades (check version inventory and upgrade notes)
- Assessing impact of a change (check dependency chains)
- Onboarding new team members to the platform

**Maintenance cadence:** Review the Version Inventory quarterly (or when notified of security patches) and update versions after validated upgrades.

## Version Inventory

Single source of truth for all deployed versions. Update this table when any component is upgraded.

### Application Services

| Component | Version | Source File | How to Find Latest |
|---|---|---|---|
| MongoDB Server | 7.0.12-7 | `k8s/base/psmdb-cluster.yaml` | `helm show values percona/psmdb-db --version <op-ver>` → look for image tag |
| Percona Operator | chart 1.18.0 (app 1.18.0) | `gitops/operators/base/helmreleases.yaml` | `helm search repo percona/psmdb-operator --versions` |
| PBM (backup agent) | 2.6.0 | `k8s/base/psmdb-cluster.yaml` | Ships with operator version |
| PostgreSQL (Aurora) | 18.3 | `platform-prerequisites/terraform/postgresql/variables.tf` | `aws rds describe-db-engine-versions --engine aurora-postgresql --query 'DBEngineVersions[*].EngineVersion' --region ap-east-1` |
| SigNoz | chart 0.130.1 (app v0.130.1) | `gitops/signoz/base/helmreleases.yaml` | `helm search repo signoz/signoz --versions` |

### Platform Controllers

| Component | Version | How Installed | How to Find Latest |
|---|---|---|---|
| EKS (Kubernetes) | 1.35 | AWS-managed | `aws eks describe-cluster --name EKS-boomi-runtime-cluster --query 'cluster.version'` |
| EBS CSI Driver | EKS addon (latest) | `aws eks create-addon` | `aws eks describe-addon-versions --addon-name aws-ebs-csi-driver` |
| Flux | Helm chart `flux2` | Bootstrap script | `helm search repo fluxcd-community/flux2 --versions` |
| Kyverno | Helm chart | Bootstrap script | `helm search repo kyverno/kyverno --versions` |
| cert-manager | Helm chart | Bootstrap script | `helm search repo jetstack/cert-manager --versions` |

### Client-Side Tools

| Tool | Required Version | Managed By | How to Pin |
|---|---|---|---|
| Terraform | 1.15.7 (pinned via `.terraform-version`) | tfenv | `.terraform-version` file in repo root |
| AWS CLI | v2.x | brew/apt/winget | OS package manager |
| kubectl | v1.36.2 (client) | brew/apt/winget | Should be within ±1 of server version |
| kustomize | v5.x | brew/apt/winget | OS package manager |
| Helm | v3.x | brew/apt/winget | OS package manager |
| Groovy | v4.x (Boomi admin only) | brew/apt/sdkman | OS package manager |

### Terraform Providers

| Provider | Version Constraint | Source File |
|---|---|---|
| hashicorp/aws | >= 5.0 | `platform-prerequisites/terraform/mongodb/main.tf` |
| hashicorp/kubernetes | >= 2.26 | `platform-prerequisites/terraform/mongodb/main.tf` |
| Terraform core | >= 1.5.0 | `platform-prerequisites/terraform/mongodb/main.tf` |

### Library Dependencies (Boomi)

| Library | Version | Used By | Compatibility |
|---|---|---|---|
| mongodb-driver-sync | 5.1.2 | `scripts/groovy/boomi/BoomiAuditLogLibrary.groovy` | MongoDB 7.0+ |
| AWS SDK secretsmanager | 2.25.48 | `scripts/groovy/boomi/BoomiAuditLogLibrary.groovy` | AWS SDK v2 |

### Upgrade Notes

- **Percona Operator**: current 1.18.0 is 4 versions behind latest (1.22.0). Upgrade path: 1.18→1.19→1.20→1.21→1.22 (one minor at a time). Check [Percona Operator release notes](https://docs.percona.com/percona-operator-for-mongodb/ReleaseNotes/index.html) and the [upgrade matrix](https://docs.percona.com/percona-operator-for-mongodb/update.html) for inter-version compatibility. See [Architect Reference § Upgrade Procedures](../guides/architect-reference.md#upgrade-procedures).
- **SigNoz**: current 0.130.1, latest 0.131.0 — minor version bump, generally safe. Check [SigNoz changelog](https://github.com/SigNoz/signoz/releases).
- **PostgreSQL**: pinned at 18.3. AWS may release newer point releases — check via `aws rds describe-db-engine-versions`.
- **EKS**: AWS manages control plane upgrades. Node groups may need manual update. Check [EKS version calendar](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html).
- **MongoDB driver 5.1.2**: compatible with MongoDB 7.0. If upgrading MongoDB to 8.0+, verify driver compatibility at [MongoDB driver compatibility](https://www.mongodb.com/docs/drivers/java/sync/current/compatibility/).

---

## Application Services

### MongoDB (Percona Server for MongoDB)

| Aspect | Detail |
|---|---|
| **What** | A distributed document database running as a 3-node replica set on EKS, managed by the Percona Operator. |
| **Why** | Stores the OMS audit trail — immutable event records for compliance and traceability. Document model fits audit log schemas naturally (nested objects, flexible fields, append-heavy writes). |
| **How it helps** | Provides durable, encrypted-at-rest audit storage with point-in-time recoverability via PBM backups. Application services write structured audit events; compliance teams query them. |
| **Namespace** | `mongodb` |
| **Owner** | Infra Architect / Platform team |
| **Depends on** | EBS CSI Driver (storage), cert-manager (TLS), Percona Operator (lifecycle), Pod Identity (IAM), Kyverno (policy) |
| **Depended on by** | Boomi audit log library, SigNoz (telemetry correlation) |
| **Provisioned by** | `scripts/provision.sh mongodb` |
| **Verification** | [Verification Commands § MongoDB](verification-commands.md#mongodb-replica-set) |

### PostgreSQL (Aurora)

| Aspect | Detail |
|---|---|
| **What** | AWS Aurora PostgreSQL 18-compatible cluster with a single provisioned writer instance. |
| **Why** | Primary application database for OMS — stores orders, inventory, customers, and operational data. Relational model suits transactional workloads with strong consistency. |
| **How it helps** | Managed service with automatic backups, failover, and patching. Single writer is cost-effective for dev; scales to multi-AZ in production. |
| **Namespace** | N/A (AWS managed service, not in Kubernetes) |
| **Owner** | Infra Architect / Platform team |
| **Depends on** | VPC, private subnets, security groups (all provisioned by Terraform) |
| **Depended on by** | OMS application services |
| **Provisioned by** | `scripts/provision.sh pg` |
| **Verification** | [Verification Commands § PostgreSQL](verification-commands.md#postgresql-aurora) |

### SigNoz

| Aspect | Detail |
|---|---|
| **What** | Open-source application telemetry platform providing distributed tracing, metrics collection, and log aggregation. Backed by ClickHouse for storage. |
| **Why** | Unified observability for OMS services — correlates traces, metrics, and logs in one dashboard. No enterprise license required. |
| **How it helps** | Boomi processes and application services send OTLP telemetry (traces + logs). Operators use the SigNoz dashboard to diagnose latency, errors, and audit-log flow. Supports alerting rules. |
| **Namespace** | `signoz` |
| **Owner** | Infra Architect / Boomi Admin (shared) |
| **Depends on** | Flux (HelmRelease delivery), EBS CSI Driver (ClickHouse storage) |
| **Depended on by** | Boomi audit log library (telemetry send), operators (dashboard) |
| **Provisioned by** | `scripts/provision.sh signoz` |
| **Verification** | [Verification Commands § SigNoz](verification-commands.md#signoz) |

### SigNoz K8s Infra Monitoring

| Aspect | Detail |
|---|---|
| **What** | The official SigNoz `k8s-infra` Helm chart — a DaemonSet (host metrics per node) plus a Deployment (cluster-level k8s object metrics), both OpenTelemetry Collector agents. |
| **Why** | Without it, SigNoz only sees application-level audit-log telemetry. This adds EKS node/pod CPU, memory, disk, and network visibility in the same dashboard. |
| **How it helps** | Operators can see node capacity and pod health without a separate monitoring stack (e.g., Prometheus/Grafana). Directly answers "is the cluster healthy" without leaving SigNoz. |
| **Namespace** | `signoz` |
| **Owner** | Infra Architect / Platform team |
| **Depends on** | SigNoz otel-collector (data destination), Flux (HelmRelease delivery) |
| **Depended on by** | Operators (Infrastructure Monitoring → Hosts dashboard) |
| **Provisioned by** | `bash scripts/provision.sh signoz` (applies `gitops/signoz/base/helmrelease-k8s-infra.yaml`) |
| **Verification** | `kubectl -n signoz get pods -l app.kubernetes.io/name=k8s-infra` — see [Architect Reference § Infrastructure And Database Monitoring](../guides/architect-reference.md#infrastructure-and-database-monitoring) |

### MongoDB Metrics Collector

| Aspect | Detail |
|---|---|
| **What** | A dedicated lightweight OpenTelemetry Collector (`otel/opentelemetry-collector-contrib`) running in the `mongodb` namespace with the native `mongodb` receiver. |
| **Why** | MongoDB is not monitored as infrastructure by default — only Boomi's application-level audit writes are visible in SigNoz. This adds replica-set connections, operations, replication, memory, and cache metrics. |
| **How it helps** | Reuses the Percona-Operator-provisioned `clusterMonitor` credentials (no new secrets) and the existing `psmdb-ssl-internal` TLS cert, so MongoDB health is visible in the same SigNoz instance as everything else. |
| **Namespace** | `mongodb` |
| **Owner** | Infra Architect / Platform team |
| **Depends on** | MongoDB ReplicaSet (`psmdb-secrets`, `psmdb-ssl-internal`), SigNoz otel-collector (data destination) |
| **Depended on by** | Operators (MongoDB dashboards/alerts in SigNoz) |
| **Provisioned by** | `kubectl apply -k k8s/overlays/dev` (applies `k8s/base/mongodb-metrics-collector.yaml`) |
| **Verification** | `kubectl -n mongodb logs deployment/mongodb-metrics-collector --tail=50` — see [Architect Reference § Infrastructure And Database Monitoring](../guides/architect-reference.md#infrastructure-and-database-monitoring) |

### PostgreSQL Metrics Collector

| Aspect | Detail |
|---|---|
| **What** | A two-container Deployment in the `mongodb` namespace: a Prometheus CloudWatch Exporter (`quay.io/prometheus/cloudwatch-exporter`) polling AWS CloudWatch `AWS/RDS` metrics, plus an OpenTelemetry Collector scraping and forwarding them via OTLP. |
| **Why** | Aurora PostgreSQL is fully managed — there is no host/pod to run a direct monitoring agent on. CloudWatch already publishes CPU, IOPS, connections, replication lag, and volume metrics for it; this brings those into the same SigNoz dashboard as MongoDB and Boomi telemetry. |
| **How it helps** | Uses a dedicated least-privilege IAM role (read-only: `cloudwatch:ListMetrics`, `GetMetricData`, `GetMetricStatistics`) bound via EKS Pod Identity — no database credentials, no write access to any AWS resource. |
| **Namespace** | `mongodb` |
| **Owner** | Infra Architect / Platform team |
| **Depends on** | `aws_iam_role.postgres_cloudwatch_monitor` + `aws_eks_pod_identity_association.postgres_cloudwatch_monitor` (Terraform), Aurora cluster `pg18-dev` / instance `pg18-dev-writer`, SigNoz otel-collector (data destination) |
| **Depended on by** | Operators (PostgreSQL dashboards/alerts in SigNoz) |
| **Provisioned by** | `bash scripts/provision-platform-prereq.sh pg` (IAM role/pod identity) then `kubectl apply -k k8s/overlays/dev` (applies `k8s/base/postgres-metrics-collector.yaml`) |
| **Verification** | `kubectl -n mongodb logs deployment/postgres-metrics-collector -c cloudwatch-exporter --tail=50` — see [Architect Reference § Infrastructure And Database Monitoring](../guides/architect-reference.md#infrastructure-and-database-monitoring) |

### SigNoz Dashboards & Alerts (as Code)

| Aspect | Detail |
|---|---|
| **What** | A Terraform root using the official `SigNoz/signoz` provider that declares dashboards and alert rules for every monitored signal (K8s, MongoDB, PostgreSQL, OTel Collector pipelines, Boomi app telemetry). |
| **Why** | Dashboards/alerts are otherwise UI-only (clicked together by hand). Managing them as code makes them reviewable, reproducible across environments, and re-appliable with one command. |
| **How it helps** | Sources dashboard JSON from [dashboards/signoz-import-pack](../../dashboards/signoz-import-pack) via `jsondecode()`, so templates aren't hand-transcribed into HCL. |
| **Namespace** | N/A (SigNoz application-layer config, not a k8s workload) |
| **Owner** | Infra Architect / Platform team |
| **Depends on** | SigNoz root user bootstrap (`signoz-root-user` Secret), a Service Account + API key (`signoz-api-key` Secret) — auto-bootstrapped via a headless-browser script if missing, see [SigNoz Dashboard Import Pack](signoz-dashboard-import-pack.md) |
| **Depended on by** | Operators / EA (dashboard views, alert notifications) |
| **Provisioned by** | `bash scripts/provision.sh signoz-observability` (wraps `platform-prerequisites/terraform/signoz-observability`) |
| **Verification** | `curl $SIGNOZ_ENDPOINT/api/v1/rules -H "SIGNOZ-API-KEY: $SIGNOZ_ACCESS_TOKEN"` — see the Terraform root's [README.md](../../platform-prerequisites/terraform/signoz-observability/README.md) for a known provider-side cosmetic drift caveat |

## Platform Controllers

### Flux (Helm + Source Controllers)

| Aspect | Detail |
|---|---|
| **What** | A GitOps toolkit that watches git-tracked `HelmRelease` and `HelmRepository` manifests and reconciles Helm chart installations automatically. |
| **Why** | Declarative Helm chart management — operators define desired state in YAML, Flux ensures the cluster matches. No manual `helm install` drift. |
| **How it helps** | The Percona Operator and SigNoz are both installed via Flux HelmReleases. When chart versions or values change in git, Flux applies them automatically. |
| **Namespace** | `flux-system` |
| **Owner** | Platform team |
| **Depends on** | EKS cluster |
| **Depended on by** | Percona Operator, SigNoz, any future Helm-managed workload |
| **CRDs provided** | `helmreleases.helm.toolkit.fluxcd.io`, `helmrepositories.source.toolkit.fluxcd.io` |
| **Verification** | [Verification Commands § Flux](verification-commands.md#flux-controllers) |

### Kyverno

| Aspect | Detail |
|---|---|
| **What** | A Kubernetes-native policy engine that validates, mutates, and generates resources at admission time. |
| **Why** | Enforces infrastructure guardrails without custom webhooks — storage class constraints, sidecar resource requirements, and secret creation restrictions. |
| **How it helps** | Prevents misconfigurations from reaching the cluster. For example: blocks PVCs without `WaitForFirstConsumer` binding (which would create disks in the wrong AZ), and requires PBM sidecar resource limits. |
| **Namespace** | `kyverno` |
| **Owner** | Platform team |
| **Depends on** | EKS cluster |
| **Depended on by** | MongoDB workload (policy validation at admission) |
| **CRDs provided** | `clusterpolicies.kyverno.io` |
| **Verification** | [Verification Commands § Kyverno](verification-commands.md#kyverno) |

### cert-manager

| Aspect | Detail |
|---|---|
| **What** | A Kubernetes add-on that automates TLS certificate issuance, renewal, and injection from various certificate authorities. |
| **Why** | MongoDB inter-node and client TLS requires valid certificates. Manual certificate management is error-prone and does not auto-renew. |
| **How it helps** | Defines `Certificate` and `Issuer` resources declaratively. cert-manager provisions the certificate, stores it in a Kubernetes Secret, and renews it before expiry. |
| **Namespace** | `cert-manager` |
| **Owner** | Platform team |
| **Depends on** | EKS cluster |
| **Depended on by** | MongoDB TLS certificates |
| **CRDs provided** | `certificates.cert-manager.io`, `issuers.cert-manager.io` |
| **Verification** | [Verification Commands § cert-manager](verification-commands.md#cert-manager) |

### AWS EBS CSI Driver

| Aspect | Detail |
|---|---|
| **What** | A Kubernetes CSI (Container Storage Interface) driver that provisions, attaches, and manages AWS EBS volumes as PersistentVolumes. |
| **Why** | MongoDB and SigNoz (ClickHouse) require durable block storage. The in-tree EBS provisioner is deprecated; CSI is the supported path. |
| **How it helps** | When a PVC with `storageClassName: gp3-mongodb` is created, this driver provisions a gp3 EBS volume in the correct AZ, attaches it to the node, and formats it. Handles resize and snapshot operations. |
| **Namespace** | `kube-system` (controller pods) |
| **Owner** | Platform team |
| **Depends on** | EKS cluster, IAM role (via Pod Identity or IRSA) |
| **Depended on by** | StorageClass `gp3-mongodb`, all PVCs for MongoDB and SigNoz |
| **Installed as** | EKS managed addon (`aws-ebs-csi-driver`) |
| **Verification** | [Verification Commands § EBS CSI](verification-commands.md#aws-ebs-csi-driver) |

### EKS Pod Identity Agent

| Aspect | Detail |
|---|---|
| **What** | An EKS addon that enables Kubernetes ServiceAccounts to assume IAM roles without requiring an OIDC provider. Successor to IRSA. |
| **Why** | The EBS CSI Driver and MongoDB workload ServiceAccount need AWS IAM permissions (S3, KMS). Pod Identity simplifies this binding — no OIDC provider URL configuration needed. |
| **How it helps** | The Terraform stack creates an `EKS Pod Identity Association` that maps a ServiceAccount to an IAM role. The agent injects temporary credentials into pods using that ServiceAccount. |
| **Namespace** | `kube-system` |
| **Owner** | Platform team |
| **Depends on** | EKS cluster |
| **Depended on by** | EBS CSI Driver (when using Pod Identity auth), MongoDB workload ServiceAccount |
| **Installed as** | EKS managed addon (`eks-pod-identity-agent`) |
| **Verification** | [Verification Commands § Pod Identity](verification-commands.md#eks-pod-identity-agent) |

## Infrastructure Components

### StorageClass (gp3-mongodb)

| Aspect | Detail |
|---|---|
| **What** | A Kubernetes StorageClass defining gp3 EBS volume parameters with `WaitForFirstConsumer` volume binding mode. |
| **Why** | Ensures MongoDB PVCs get gp3 performance (3000 IOPS baseline, 125 MB/s throughput) and volumes are created in the same AZ as the scheduled pod. |
| **How it helps** | Without `WaitForFirstConsumer`, the volume might be created in a different AZ than the pod, causing permanent scheduling failures. This StorageClass prevents that. |
| **Owner** | Infra Architect |
| **Depends on** | EBS CSI Driver |
| **Depended on by** | MongoDB PVCs, SigNoz ClickHouse PVCs |
| **Defined in** | `k8s/base/storageclass-gp3-mongodb.yaml` |
| **Verification** | [Verification Commands § StorageClass](verification-commands.md#storageclass) |

### Terraform S3 State Backend

| Aspect | Detail |
|---|---|
| **What** | A single S3 bucket (`sml-oms-dev-tfstate`, region `ap-east-1`) storing all Terraform state files with versioning, encryption, and public access block. Each Terraform root writes to its own **key** (S3's term for the object path/"folder+filename") inside that one bucket -- there is no separate bucket per root. |
| **Why** | Terraform state must be shared across operators and persisted durably. Local state creates drift and ownership conflicts. |
| **How it helps** | All operators read/write the same infrastructure state. Versioning allows state recovery if corruption occurs. |
| **Owner** | Platform team |
| **Depends on** | AWS S3 permissions |
| **Depended on by** | All Terraform operations |
| **Provisioned by** | `scripts/bootstrap-terraform-s3-backend.sh` |
| **Verification** | [Verification Commands § Terraform State](verification-commands.md#terraform-state-backend) |

Every root shares the same bucket and region; only the key (path) differs:

| Terraform root | Bucket | Region | State key (path within bucket) |
|---|---|---|---|
| `platform-prerequisites/terraform/mongodb` | `sml-oms-dev-tfstate` | `ap-east-1` | `oms/dev/mongo.tfstate` |
| `platform-prerequisites/terraform/postgresql` | `sml-oms-dev-tfstate` | `ap-east-1` | `oms/dev/pg.tfstate` |
| `platform-prerequisites/terraform/signoz-observability` | `sml-oms-dev-tfstate` | `ap-east-1` | `oms/dev/signoz-observability.tfstate` |

So, for example, the MongoDB prerequisites' state is the single object at
`s3://sml-oms-dev-tfstate/oms/dev/mongo.tfstate` -- "`oms/dev/`" is the shared
key prefix (S3 has no real folders; this just groups objects visually), and
`mongo.tfstate` is that root's own file within it. There is no separate
Terraform root/state for the plain `signoz` scope -- that scope is a Flux
HelmRelease + kustomize apply only, with no Terraform state at all.

### PBM Backup Bucket

| Aspect | Detail |
|---|---|
| **What** | An S3 bucket (`sml-aw-gb0-d-oms-gen-s3-01`) storing Percona Backup for MongoDB backup archives. |
| **Why** | MongoDB point-in-time recovery requires durable off-cluster backup storage. S3 provides this with low cost and high durability. |
| **How it helps** | PBM sidecar in each MongoDB pod writes incremental and full backups to this bucket. Recovery operations read from it. |
| **Owner** | Infra Architect |
| **Depends on** | IAM role (via Pod Identity), S3 permissions |
| **Depended on by** | PBM backup agent (sidecar in MongoDB pods) |
| **Provisioned by** | Terraform (`platform-prerequisites/terraform/reusable/main.tf`) |
| **Verification** | [Verification Commands § PBM Bucket](verification-commands.md#pbm-backup-bucket) |

### Percona Operator (psmdb-operator)

| Aspect | Detail |
|---|---|
| **What** | A Kubernetes operator that manages the full lifecycle of Percona Server for MongoDB clusters — deployment, scaling, backup, restore, and upgrades. |
| **Why** | Running MongoDB on Kubernetes requires complex orchestration (replica set initialization, rolling upgrades, backup coordination). The operator automates this. |
| **How it helps** | Operators define a `PerconaServerMongoDB` CR; the operator creates StatefulSets, configures replica set membership, manages TLS, and coordinates PBM backups. |
| **Namespace** | `mongodb` (operator deployment) |
| **Owner** | Infra Architect |
| **Depends on** | Flux (HelmRelease delivery), EKS cluster |
| **Depended on by** | MongoDB ReplicaSet (PerconaServerMongoDB CR) |
| **Provisioned by** | Flux reconciling `gitops/operators/base/helmreleases.yaml` |
| **Verification** | [Verification Commands § Percona Operator](verification-commands.md#percona-operator) |
