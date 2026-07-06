#!/usr/bin/env bash
set -euo pipefail

# Deploys a test pod into the cluster that writes an audit log to MongoDB
# and sends telemetry to SigNoz using cluster-internal service endpoints.
# After success (or failure), shows logs and deletes the pod.
#
# Usage:
#   scripts/run-audit-telemetry-test.sh [--namespace <ns>] [--db <name>] [--keep]

NAMESPACE="mongodb"
DB_NAME="oms_audit"
COLLECTION="auditlogs"
POD_NAME="audit-telemetry-test-$(date +%s)"
MONGO_SERVICE="psmdb-rs0-0.psmdb-rs0.mongodb.svc.cluster.local,psmdb-rs0-1.psmdb-rs0.mongodb.svc.cluster.local,psmdb-rs0-2.psmdb-rs0.mongodb.svc.cluster.local"
SIGNOZ_SERVICE="signoz.signoz.svc.cluster.local"
SIGNOZ_PORT="8080"
KEEP_POD="false"
TIMEOUT="120"

usage() {
  cat <<'EOF'
Usage:
  run-audit-telemetry-test.sh [--namespace <ns>] [--db <name>] [--keep] [--timeout <seconds>]

Deploys a test Pod in the cluster that:
  1. Writes a sample audit log record to MongoDB (cluster-internal)
  2. Sends matching OTLP telemetry to SigNoz (cluster-internal)
  3. Verifies the record exists in MongoDB (read-back)
  4. Prints results and deletes the Pod

Options:
  --namespace   Pod namespace (default: mongodb)
  --db          Target database (default: oms_audit)
  --keep        Keep the pod after completion (do not delete)
  --timeout     Seconds to wait for pod completion (default: 120)
  -h, --help    Show this help

The test record is NOT deleted from MongoDB — it remains as evidence.
The Pod is deleted after showing logs (unless --keep is used).
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --namespace) NAMESPACE="${2:-}"; shift 2 ;;
    --db) DB_NAME="${2:-}"; shift 2 ;;
    --keep) KEEP_POD="true"; shift ;;
    --timeout) TIMEOUT="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Error: unknown arg '$1'" >&2; usage; exit 1 ;;
  esac
done

# Read MongoDB credentials from existing secret
echo "Reading MongoDB credentials from psmdb-secrets..."
ADMIN_USER="$(kubectl -n "$NAMESPACE" get secret psmdb-secrets \
  -o jsonpath='{.data.MONGODB_CLUSTER_ADMIN_USER}' | base64 -d)"
ADMIN_PASS="$(kubectl -n "$NAMESPACE" get secret psmdb-secrets \
  -o jsonpath='{.data.MONGODB_CLUSTER_ADMIN_PASSWORD}' | base64 -d)"

if [[ -z "$ADMIN_USER" || -z "$ADMIN_PASS" ]]; then
  echo "Error: cannot read credentials from psmdb-secrets" >&2
  exit 1
fi

TRACE_ID="test-$(openssl rand -hex 8)"
NOW_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
NOW_NANO="$(($(date -u +%s) * 1000000000))"

echo "Deploying test pod: $POD_NAME"
echo "  Namespace: $NAMESPACE"
echo "  MongoDB: psmdb-rs0-{0,1,2} (replica set) / $DB_NAME.$COLLECTION"
echo "  SigNoz: $SIGNOZ_SERVICE:$SIGNOZ_PORT"
echo "  Trace ID: $TRACE_ID"
echo ""

# Create the test Pod
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: ${POD_NAME}
  namespace: ${NAMESPACE}
  labels:
    app: audit-telemetry-test
    test-run: "${TRACE_ID}"
spec:
  restartPolicy: Never
  containers:
  - name: test
    image: mongo:7.0
    command:
    - /bin/bash
    - -c
    - |
      set -e
      echo "=== Audit + Telemetry Test Pod ==="
      echo "Trace ID: ${TRACE_ID}"
      echo ""

      # Step 1: Write audit record to MongoDB
      echo "[1/3] Writing audit record to MongoDB..."
      mongosh --quiet --tls --tlsAllowInvalidCertificates \
        "mongodb://${ADMIN_USER}:${ADMIN_PASS}@${MONGO_SERVICE}/${DB_NAME}?authSource=admin&replicaSet=rs0&tls=true&tlsAllowInvalidCertificates=true" \
        --eval '
          const record = {
            trace_id: "${TRACE_ID}",
            time: "${NOW_ISO}",
            action: "smoke.test.pod",
            resource_type: "test.record",
            resource_id: "TEST-001",
            user_id: "test-pod",
            meta: { source: "audit-telemetry-test-pod", pod: "${POD_NAME}" }
          };
          const result = db.getCollection("${COLLECTION}").insertOne(record);
          print("Inserted: " + result.insertedId);
        '
      echo "  MongoDB write: OK"
      echo ""

      # Step 2: Send OTLP telemetry to SigNoz
      echo "[2/3] Sending OTLP telemetry to SigNoz..."
      TELEM_RESULT=\$(curl -sf -o /dev/null -w '%{http_code}' -X POST \
        -H 'Content-Type: application/json' \
        -d '{
          "resourceLogs": [{
            "resource": {
              "attributes": [
                {"key": "service.name", "value": {"stringValue": "oms-audit-test-pod"}},
                {"key": "deployment.environment", "value": {"stringValue": "dev"}}
              ]
            },
            "scopeLogs": [{
              "scope": {"name": "oms.auditlog.test", "version": "1.0.0"},
              "logRecords": [{
                "timeUnixNano": "${NOW_NANO}",
                "severityNumber": 9,
                "severityText": "INFO",
                "body": {"stringValue": "smoke.test.pod"},
                "attributes": [
                  {"key": "trace_id", "value": {"stringValue": "${TRACE_ID}"}},
                  {"key": "action", "value": {"stringValue": "smoke.test.pod"}},
                  {"key": "pod_name", "value": {"stringValue": "${POD_NAME}"}}
                ]
              }]
            }]
          }]
        }' \
        "http://${SIGNOZ_SERVICE}:${SIGNOZ_PORT}/v1/logs" || echo "000")

      if [[ "\$TELEM_RESULT" =~ ^2 ]]; then
        echo "  SigNoz telemetry: OK (HTTP \$TELEM_RESULT)"
      else
        echo "  SigNoz telemetry: FAILED (HTTP \$TELEM_RESULT)" >&2
        exit 1
      fi
      echo ""

      # Step 3: Read back from MongoDB to verify
      echo "[3/3] Verifying record in MongoDB..."
      FOUND=\$(mongosh --quiet --tls --tlsAllowInvalidCertificates \
        "mongodb://${ADMIN_USER}:${ADMIN_PASS}@${MONGO_SERVICE}/${DB_NAME}?authSource=admin&replicaSet=rs0&tls=true&tlsAllowInvalidCertificates=true" \
        --eval '
          const doc = db.getCollection("${COLLECTION}").findOne({trace_id: "${TRACE_ID}"});
          if (doc) { print("FOUND"); } else { print("NOT_FOUND"); }
        ')

      if [[ "\$FOUND" == "FOUND" ]]; then
        echo "  Read-back: OK (record verified in MongoDB)"
      else
        echo "  Read-back: FAILED (record not found)" >&2
        exit 1
      fi

      echo ""
      echo "=== ALL TESTS PASSED ==="
      echo "Trace ID: ${TRACE_ID}"
      echo "Record kept in: ${DB_NAME}.${COLLECTION}"
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: 200m
        memory: 256Mi
EOF

echo "Pod created. Waiting for completion (timeout: ${TIMEOUT}s)..."

# Wait for pod to complete
if kubectl -n "$NAMESPACE" wait --for=condition=Ready "pod/$POD_NAME" --timeout=30s >/dev/null 2>&1; then
  : # Pod started
fi

# Wait for pod to finish (Succeeded or Failed)
end_time=$((SECONDS + TIMEOUT))
while [[ $SECONDS -lt $end_time ]]; do
  phase="$(kubectl -n "$NAMESPACE" get pod "$POD_NAME" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")"
  case "$phase" in
    Succeeded|Failed) break ;;
    *) sleep 3 ;;
  esac
done

echo ""
echo "─── Pod Logs ───"
kubectl -n "$NAMESPACE" logs "$POD_NAME" 2>/dev/null || echo "(no logs available)"
echo "────────────────"
echo ""

# Check result
phase="$(kubectl -n "$NAMESPACE" get pod "$POD_NAME" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")"
if [[ "$phase" == "Succeeded" ]]; then
  echo "Result: PASSED"
else
  echo "Result: FAILED (pod phase: $phase)" >&2
fi

# Cleanup pod
if [[ "$KEEP_POD" == "false" ]]; then
  echo "Deleting test pod..."
  kubectl -n "$NAMESPACE" delete pod "$POD_NAME" --grace-period=0 --force >/dev/null 2>&1 || true
  echo "Pod deleted."
else
  echo "Pod kept (--keep). Delete manually: kubectl -n $NAMESPACE delete pod $POD_NAME"
fi

[[ "$phase" == "Succeeded" ]] && exit 0 || exit 1
