#!/usr/bin/env bash
set -euo pipefail

# Unified platform health verification script.
# Usage:
#   scripts/verify-platform-health.sh              # Full platform check
#   scripts/verify-platform-health.sh --preflight  # Environment-only preflight

PREFLIGHT_ONLY="false"
SMOKE_TEST="false"
FAILURES=0
CHECKS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --preflight) PREFLIGHT_ONLY="true"; shift ;;
    --smoke-test) SMOKE_TEST="true"; shift ;;
    -h|--help)
      echo "Usage: verify-platform-health.sh [--preflight] [--smoke-test]"
      echo "  --preflight    Only check environment readiness (tools, AWS, k8s)"
      echo "  --smoke-test   Run end-to-end audit write + read-back verification"
      echo "  (no flag)      Full platform verification"
      exit 0
      ;;
    *) echo "Error: unknown arg '$1'" >&2; exit 1 ;;
  esac
done

pass() {
  CHECKS=$((CHECKS + 1))
  printf "  ✓ %s\n" "$1"
}

fail() {
  CHECKS=$((CHECKS + 1))
  FAILURES=$((FAILURES + 1))
  printf "  ✗ %s\n" "$1" >&2
  if [[ -n "${2:-}" ]]; then
    printf "    → %s\n" "$2" >&2
  fi
}

section() {
  echo ""
  echo "[$1]"
}

# ─── PREFLIGHT ───────────────────────────────────────────────────────────────

section "Required Tools"
for cmd in aws terraform kubectl kustomize rg openssl; do
  if command -v "$cmd" >/dev/null 2>&1; then
    pass "$cmd available"
  else
    fail "$cmd not found" "Install it and reopen your shell"
  fi
done

tf_version="$(terraform version -json 2>/dev/null | grep -o '"terraform_version":"[^"]*"' | cut -d'"' -f4 || echo "0.0.0")"
if [[ "$(printf '%s\n' "1.5.0" "$tf_version" | sort -V | head -1)" == "1.5.0" ]]; then
  pass "terraform >= 1.5.0 ($tf_version)"
else
  fail "terraform < 1.5.0 ($tf_version)" "Upgrade to >= 1.5.0"
fi

section "AWS Identity"
if aws sts get-caller-identity >/dev/null 2>&1; then
  account="$(aws sts get-caller-identity --query 'Account' --output text 2>/dev/null)"
  pass "AWS authenticated (account: $account)"
else
  fail "AWS not authenticated" "Run: aws sso login --profile default"
fi

region="$(aws configure get region 2>/dev/null || echo "")"
if [[ "$region" == "ap-east-1" ]]; then
  pass "AWS region: $region"
elif [[ -n "$region" ]]; then
  fail "AWS region: $region (expected ap-east-1)" "export AWS_REGION=ap-east-1"
else
  fail "AWS region not set" "export AWS_REGION=ap-east-1"
fi

section "Kubernetes Access"
if kubectl cluster-info >/dev/null 2>&1; then
  ctx="$(kubectl config current-context 2>/dev/null)"
  pass "Cluster reachable (context: $ctx)"
else
  fail "Cluster not reachable" "Run: aws eks update-kubeconfig --name EKS-boomi-runtime-cluster --region ap-east-1"
fi

section "Repository Root"
if [[ -d "platform-prerequisites/terraform/mongodb" ]]; then
  pass "Repository root confirmed"
else
  fail "Not at repository root" "cd to the repository root directory"
fi

if [[ "$PREFLIGHT_ONLY" == "true" ]]; then
  echo ""
  echo "Preflight: $CHECKS checks, $FAILURES failures"
  [[ $FAILURES -eq 0 ]] && exit 0 || exit 1
fi

# ─── PLATFORM CONTROLLERS ────────────────────────────────────────────────────

section "EBS CSI Driver"
if kubectl get csidriver ebs.csi.aws.com >/dev/null 2>&1; then
  pass "CSI driver registered"
else
  fail "CSI driver missing" "Install EBS CSI addon or use --bootstrap-platform-controllers"
fi

addon_status="$(aws eks describe-addon --cluster-name EKS-boomi-runtime-cluster --addon-name aws-ebs-csi-driver --query 'addon.status' --output text 2>/dev/null || echo "NOT_FOUND")"
if [[ "$addon_status" == "ACTIVE" ]]; then
  pass "EBS CSI addon: ACTIVE"
else
  fail "EBS CSI addon: $addon_status" "Expected ACTIVE"
fi

section "Flux Controllers"
for crd in helmreleases.helm.toolkit.fluxcd.io helmrepositories.source.toolkit.fluxcd.io; do
  if kubectl get crd "$crd" >/dev/null 2>&1; then
    pass "CRD: $crd"
  else
    fail "CRD missing: $crd" "Install Flux controllers"
  fi
done

section "Kyverno"
if kubectl get crd clusterpolicies.kyverno.io >/dev/null 2>&1; then
  pass "CRD: clusterpolicies.kyverno.io"
else
  fail "CRD missing: clusterpolicies.kyverno.io" "Install Kyverno"
fi

section "cert-manager"
for crd in certificates.cert-manager.io issuers.cert-manager.io; do
  if kubectl get crd "$crd" >/dev/null 2>&1; then
    pass "CRD: $crd"
  else
    fail "CRD missing: $crd" "Install cert-manager"
  fi
done

# ─── MONGODB ─────────────────────────────────────────────────────────────────

section "MongoDB"
if kubectl get ns mongodb >/dev/null 2>&1; then
  pass "Namespace: mongodb"
else
  fail "Namespace mongodb missing" "Run Terraform prerequisites"
fi

for secret in psmdb-encryption-key psmdb-secrets; do
  if kubectl -n mongodb get secret "$secret" >/dev/null 2>&1; then
    pass "Secret: $secret"
  else
    fail "Secret missing: $secret" "Run: scripts/bootstrap-dev-secrets.sh"
  fi
done

pod_count="$(kubectl -n mongodb get pods -l app.kubernetes.io/component=mongod --no-headers 2>/dev/null | grep -c Running || echo 0)"
if [[ "$pod_count" -ge 3 ]]; then
  pass "MongoDB pods: $pod_count Running"
elif [[ "$pod_count" -ge 1 ]]; then
  fail "MongoDB pods: only $pod_count Running (expected 3)" "Check pod events"
else
  fail "No MongoDB pods running" "Apply workload manifests"
fi

pvc_bound="$(kubectl -n mongodb get pvc --no-headers 2>/dev/null | grep -c Bound || echo 0)"
if [[ "$pvc_bound" -ge 3 ]]; then
  pass "MongoDB PVCs: $pvc_bound Bound"
else
  fail "MongoDB PVCs: $pvc_bound Bound (expected 3)" "Check StorageClass and EBS CSI"
fi

# ─── POSTGRESQL ──────────────────────────────────────────────────────────────

section "PostgreSQL"
pg_status="$(aws rds describe-db-clusters --db-cluster-identifier pg18-dev --query 'DBClusters[0].Status' --output text 2>/dev/null || echo "NOT_FOUND")"
if [[ "$pg_status" == "available" ]]; then
  pass "Aurora cluster: available"
elif [[ "$pg_status" == "NOT_FOUND" ]]; then
  fail "Aurora cluster not found" "Run: scripts/provision-platform-prereq.sh pg"
else
  fail "Aurora cluster: $pg_status" "Expected: available"
fi

# ─── SIGNOZ ──────────────────────────────────────────────────────────────────

section "SigNoz"
if kubectl get ns signoz >/dev/null 2>&1; then
  pass "Namespace: signoz"
else
  fail "Namespace signoz missing" "Run: scripts/provision.sh signoz"
fi

signoz_pods="$(kubectl -n signoz get pods --no-headers 2>/dev/null | grep -c Running || echo 0)"
if [[ "$signoz_pods" -ge 3 ]]; then
  pass "SigNoz pods: $signoz_pods Running"
elif [[ "$signoz_pods" -ge 1 ]]; then
  fail "SigNoz pods: only $signoz_pods Running" "Check HelmRelease and PVCs"
else
  fail "No SigNoz pods running" "Run: scripts/provision.sh signoz"
fi

# ─── STORAGE ─────────────────────────────────────────────────────────────────

section "Storage"
if kubectl get storageclass gp3-mongodb >/dev/null 2>&1; then
  binding="$(kubectl get storageclass gp3-mongodb -o jsonpath='{.volumeBindingMode}' 2>/dev/null)"
  if [[ "$binding" == "WaitForFirstConsumer" ]]; then
    pass "StorageClass gp3-mongodb (WaitForFirstConsumer)"
  else
    fail "StorageClass binding mode: $binding" "Expected WaitForFirstConsumer"
  fi
else
  fail "StorageClass gp3-mongodb missing" "Apply k8s/base/storageclass-gp3-mongodb.yaml"
fi

# ─── TERRAFORM STATE ─────────────────────────────────────────────────────────

section "Terraform State"
if aws s3api head-bucket --bucket sml-oms-dev-tfstate 2>/dev/null; then
  pass "State bucket accessible"
else
  fail "State bucket not accessible" "Check AWS permissions or bucket existence"
fi

# ─── SMOKE TEST (optional) ────────────────────────────────────────────────────

if [[ "$SMOKE_TEST" == "true" ]]; then
  section "End-to-End Smoke Test"

  # Check if port-forwards are running
  if ! curl -sf http://127.0.0.1:27017 >/dev/null 2>&1 && ! mongosh --quiet --eval "db.runCommand({ping:1})" 'mongodb://127.0.0.1:27017/?directConnection=true' >/dev/null 2>&1; then
    fail "MongoDB not reachable on localhost:27017" "Run: kubectl -n mongodb port-forward svc/psmdb-rs0 27017:27017"
  else
    pass "MongoDB reachable on localhost:27017"

    # Write a test record
    TRACE_ID="smoke-test-$(date +%s)"
    WRITE_RESULT="$(mongosh --quiet 'mongodb://127.0.0.1:27017/?directConnection=true' --eval "
      const r = db.getSiblingDB('test_db').smoke_test.insertOne({
        trace_id: '$TRACE_ID', time: new Date().toISOString(), action: 'smoke.test'
      });
      print(r.insertedId ? 'OK' : 'FAIL');
    " 2>/dev/null || echo "FAIL")"

    if [[ "$WRITE_RESULT" == *"OK"* ]]; then
      pass "MongoDB write succeeded (trace: $TRACE_ID)"

      # Read back
      READ_RESULT="$(mongosh --quiet 'mongodb://127.0.0.1:27017/?directConnection=true' --eval "
        const doc = db.getSiblingDB('test_db').smoke_test.findOne({trace_id: '$TRACE_ID'});
        print(doc ? 'FOUND' : 'NOT_FOUND');
      " 2>/dev/null || echo "NOT_FOUND")"

      if [[ "$READ_RESULT" == *"FOUND"* ]]; then
        pass "MongoDB read-back verified"
      else
        fail "MongoDB read-back failed" "Document not found after write"
      fi

      # Cleanup
      mongosh --quiet 'mongodb://127.0.0.1:27017/?directConnection=true' --eval "
        db.getSiblingDB('test_db').smoke_test.deleteOne({trace_id: '$TRACE_ID'});
      " >/dev/null 2>&1
    else
      fail "MongoDB write failed" "Check MongoDB auth and connectivity"
    fi
  fi

  # SigNoz telemetry send
  if curl -sf http://127.0.0.1:3301/api/v1/health >/dev/null 2>&1; then
    pass "SigNoz reachable on localhost:3301"

    TELEM_RESULT="$(curl -sf -o /dev/null -w '%{http_code}' -X POST \
      -H 'Content-Type: application/json' \
      -d '{"resourceLogs":[{"resource":{"attributes":[{"key":"service.name","value":{"stringValue":"smoke-test"}}]},"scopeLogs":[{"logRecords":[{"timeUnixNano":"'"$(date +%s)"'000000000","body":{"stringValue":"smoke-test"}}]}]}]}' \
      http://127.0.0.1:3301/v1/logs 2>/dev/null || echo "000")"

    if [[ "$TELEM_RESULT" =~ ^2 ]]; then
      pass "SigNoz telemetry accepted (HTTP $TELEM_RESULT)"
    else
      fail "SigNoz telemetry rejected (HTTP $TELEM_RESULT)" "Check SigNoz frontend/collector"
    fi
  else
    fail "SigNoz not reachable on localhost:3301" "Run: kubectl -n signoz port-forward svc/signoz 3301:8080"
  fi
fi

# ─── SUMMARY ─────────────────────────────────────────────────────────────────

echo ""
echo "─────────────────────────────────────────"
echo "Total: $CHECKS checks, $FAILURES failures"
if [[ $FAILURES -eq 0 ]]; then
  echo "Result: ALL PASSED"
  exit 0
else
  echo "Result: $FAILURES FAILED"
  exit 1
fi
