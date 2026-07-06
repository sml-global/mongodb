# Verification Commands Reference

Per-component health checks for validating deployments. Use these individually or run the unified script:

```bash
scripts/verify-platform-health.sh          # Full platform check
scripts/verify-platform-health.sh --preflight  # Environment-only preflight
```

**Related docs:**
- [Component Catalog](component-catalog.md) — what each component does
- [Operator Runbook](../guides/operator-runbook.md) — when to run these
- [Recovery Procedures](recovery-procedures.md) — what to do when checks fail

---

## Preflight (Environment Readiness)

```bash
# Required tools
command -v aws terraform kubectl kustomize rg openssl

# Tool versions
terraform version | head -1   # expect >= 1.5.0
aws --version                 # expect v2.x

# AWS identity
aws sts get-caller-identity   # expect correct account + role
aws configure get region      # expect ap-east-1

# Kubernetes connectivity
kubectl config current-context
kubectl cluster-info
kubectl get ns mongodb signoz 2>/dev/null

# Repository root
test -d platform-prerequisites/terraform/mongodb && echo "OK: repo root"
```

**Pass criteria:** All commands succeed, account is `815402439714`, region is `ap-east-1`, cluster is reachable.

## AWS EBS CSI Driver

```bash
# Addon status via AWS API
aws eks describe-addon \
  --cluster-name EKS-boomi-runtime-cluster \
  --addon-name aws-ebs-csi-driver \
  --query 'addon.status' \
  --output text
# Expect: ACTIVE

# CSI driver registered in cluster
kubectl get csidriver ebs.csi.aws.com
# Expect: ebs.csi.aws.com listed

# Controller pods running
kubectl -n kube-system get pods -l app.kubernetes.io/name=aws-ebs-csi-driver
# Expect: 2 controller pods Running

# Node daemonset pods
kubectl -n kube-system get pods -l app=ebs-csi-node
# Expect: one pod per node, all Running

# Recent controller logs (no errors)
kubectl -n kube-system logs deployment/ebs-csi-controller -c ebs-plugin --tail=20
```

**Pass criteria:** Addon is `ACTIVE`, CSI driver exists, controller and node pods are Running, no IAM auth errors in logs.

## EKS Pod Identity Agent

```bash
# Addon status
aws eks describe-addon \
  --cluster-name EKS-boomi-runtime-cluster \
  --addon-name eks-pod-identity-agent \
  --query 'addon.status' \
  --output text
# Expect: ACTIVE

# Agent pods running on each node
kubectl -n kube-system get pods -l app.kubernetes.io/name=eks-pod-identity-agent
# Expect: one pod per node, all Running
```

**Pass criteria:** Addon is `ACTIVE`, agent pods are Running on all nodes.

## Flux Controllers

```bash
# Required CRDs exist
kubectl get crd helmreleases.helm.toolkit.fluxcd.io
kubectl get crd helmrepositories.source.toolkit.fluxcd.io
# Expect: both exist

# Controller pods
kubectl -n flux-system get pods
# Expect: helm-controller and source-controller Running

# HelmRelease reconciliation status
kubectl get helmreleases -A
# Expect: all show Ready=True
```

**Pass criteria:** CRDs exist, controller pods Running, all HelmReleases reconciled.

## Kyverno

```bash
# CRD exists
kubectl get crd clusterpolicies.kyverno.io
# Expect: exists

# Controller pods
kubectl -n kyverno get pods
# Expect: kyverno pods Running

# Policies active
kubectl get clusterpolicies
# Expect: policies listed with READY=true

# Policy audit (check for violations)
kubectl get policyreports -A --no-headers | grep -c "fail" || echo "0 failures"
```

**Pass criteria:** CRD exists, controller Running, policies active, no unexpected violations.

## cert-manager

```bash
# CRDs exist
kubectl get crd certificates.cert-manager.io issuers.cert-manager.io
# Expect: both exist

# Controller pods
kubectl -n cert-manager get pods
# Expect: cert-manager, cert-manager-webhook, cert-manager-cainjector Running

# Certificates valid
kubectl -n mongodb get certificates
# Expect: all show READY=True

# Certificate expiry check
kubectl -n mongodb get certificates -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.notAfter}{"\n"}{end}'
```

**Pass criteria:** CRDs exist, controller pods Running, all certificates Ready and not expired.

## Percona Operator

```bash
# Operator pod running
kubectl -n mongodb get pods -l app.kubernetes.io/name=percona-server-mongodb-operator
# Expect: 1 pod Running

# Operator HelmRelease reconciled
kubectl -n mongodb get helmrelease percona-server-mongodb-operator
# Expect: Ready=True

# PerconaServerMongoDB CRD exists
kubectl get crd perconaservermongodbs.psmdb.percona.com
# Expect: exists
```

**Pass criteria:** Operator pod Running, HelmRelease reconciled, CRD available.

## MongoDB Replica Set

```bash
# All pods running
kubectl -n mongodb get pods -l app.kubernetes.io/component=mongod
# Expect: 3 pods Running (psmdb-rs0-0, psmdb-rs0-1, psmdb-rs0-2)

# PVCs bound
kubectl -n mongodb get pvc
# Expect: 3 PVCs Bound with storageClass gp3-mongodb

# ServiceAccount identity
scripts/verify-dev-identity.sh
# Expect: exit 0

# Replica set status (via mongosh inside pod)
kubectl -n mongodb exec psmdb-rs0-0 -c mongod -- \
  mongosh --quiet --eval "rs.status().members.map(m => m.name + ' ' + m.stateStr)"
# Expect: 3 members, 1 PRIMARY + 2 SECONDARY

# Encryption active
kubectl -n mongodb exec psmdb-rs0-0 -c mongod -- \
  mongosh --quiet --eval "db.serverStatus().security"
# Expect: encryptionKeyManager shows active

# Secrets exist
kubectl -n mongodb get secret psmdb-encryption-key psmdb-secrets
# Expect: both exist
```

**Pass criteria:** 3 pods Running, PVCs Bound, correct ServiceAccount, replica set healthy with 1 primary + 2 secondaries, encryption active.

## PostgreSQL (Aurora)

```bash
# Cluster status
aws rds describe-db-clusters \
  --db-cluster-identifier pg18-dev \
  --query 'DBClusters[0].Status' \
  --output text
# Expect: available

# Writer instance status
aws rds describe-db-instances \
  --db-instance-identifier pg18-dev-writer \
  --query 'DBInstances[0].DBInstanceStatus' \
  --output text
# Expect: available

# Endpoint reachable (from allowed network)
aws rds describe-db-clusters \
  --db-cluster-identifier pg18-dev \
  --query 'DBClusters[0].Endpoint' \
  --output text
# Note: actual TCP connectivity test requires access from within VPC
```

**Pass criteria:** Cluster and writer instance both `available`.

## SigNoz

```bash
# Pods running
kubectl -n signoz get pods
# Expect: signoz, clickhouse, zookeeper, otel-collector pods Running

# HelmRelease reconciled
kubectl -n signoz get helmrelease signoz
# Expect: Ready=True

# PVCs bound
kubectl -n signoz get pvc
# Expect: PVCs for clickhouse Bound

# Dashboard health (via port-forward)
kubectl -n signoz port-forward svc/signoz 3301:8080 &
PF_PID=$!
sleep 2
curl -sf http://127.0.0.1:3301/api/v1/health && echo "OK: dashboard healthy"
kill $PF_PID 2>/dev/null

# Or via ingress (production)
# scripts/open-signoz-ui.sh --mode ingress --namespace signoz --ingress signoz
```

**Pass criteria:** All pods Running, HelmRelease reconciled, PVCs Bound, dashboard returns healthy.

## StorageClass

```bash
# Exists with correct provisioner
kubectl get storageclass gp3-mongodb \
  -o jsonpath='{.provisioner}{"\n"}{.volumeBindingMode}'
# Expect: ebs.csi.aws.com and WaitForFirstConsumer
```

**Pass criteria:** StorageClass exists, provisioner is `ebs.csi.aws.com`, binding mode is `WaitForFirstConsumer`.

## Terraform State Backend

```bash
# Bucket exists and is accessible
aws s3api head-bucket --bucket sml-oms-dev-tfstate
# Expect: no error (exit 0)

# State objects exist
aws s3api head-object --bucket sml-oms-dev-tfstate --key oms/dev/mongo.tfstate 2>/dev/null && echo "OK: mongo state"
aws s3api head-object --bucket sml-oms-dev-tfstate --key oms/dev/pg.tfstate 2>/dev/null && echo "OK: pg state"

# Bucket versioning enabled
aws s3api get-bucket-versioning --bucket sml-oms-dev-tfstate --query 'Status' --output text
# Expect: Enabled
```

**Pass criteria:** Bucket accessible, state objects exist, versioning enabled.

## PBM Backup Bucket

```bash
# Bucket exists
aws s3api head-bucket --bucket sml-aw-gb0-d-oms-gen-s3-01
# Expect: no error

# Versioning enabled
aws s3api get-bucket-versioning --bucket sml-aw-gb0-d-oms-gen-s3-01 --query 'Status' --output text
# Expect: Enabled

# Public access blocked
aws s3api get-public-access-block --bucket sml-aw-gb0-d-oms-gen-s3-01 --query 'PublicAccessBlockConfiguration'
# Expect: all four settings true
```

**Pass criteria:** Bucket accessible, versioned, public access blocked.

## End-to-End Smoke Test

Validates the full audit-log write path: MongoDB insert → telemetry send → SigNoz receives.

```bash
# Requires: MongoDB port-forward + SigNoz port-forward active
kubectl -n mongodb port-forward svc/psmdb-rs0 27017:27017 &
PF_MONGO=$!
kubectl -n signoz port-forward svc/signoz 3301:8080 &
PF_SIGNOZ=$!
sleep 3

# Run the test harness
scripts/write-auditlog-and-telemetry.sh

# Verify audit log exists in MongoDB
kubectl -n mongodb exec psmdb-rs0-0 -c mongod -- \
  mongosh --quiet --eval "db.getSiblingDB('test_db').auditlogs.countDocuments()"
# Expect: >= 1

# Cleanup
kill $PF_MONGO $PF_SIGNOZ 2>/dev/null
```

**Pass criteria:** Script exits 0, audit log count increments, telemetry accepted by SigNoz.
