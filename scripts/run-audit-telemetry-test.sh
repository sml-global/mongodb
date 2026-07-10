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
MONGO_HOST="psmdb-rs0.mongodb.svc.cluster.local"
SIGNOZ_SERVICE="signoz.signoz.svc.cluster.local"
SIGNOZ_PORT="8080"
KEEP_POD="false"
TIMEOUT="180"

usage() {
  cat <<'EOF'
Usage:
  run-audit-telemetry-test.sh [--namespace <ns>] [--db <name>] [--keep] [--timeout <seconds>]

Deploys a test Pod in the cluster that:
  1. Writes Boomi-style sample audit log records to MongoDB (cluster-internal)
  2. Sends matching OTLP telemetry to SigNoz (cluster-internal)
  3. Verifies the records exist in MongoDB (read-back)
  4. Prints results and deletes the Pod

Options:
  --namespace   Pod namespace (default: mongodb)
  --db          Target database (default: oms_audit)
  --keep        Keep the pod after completion (do not delete)
  --timeout     Seconds to wait for pod completion (default: 180)
  -h, --help    Show this help

The test records are NOT deleted from MongoDB — they remain as evidence.
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

# Read MongoDB credentials from psmdb-secrets (database admin user).
echo "Reading MongoDB database-admin credentials from psmdb-secrets..."
ADMIN_USER="$(kubectl -n "$NAMESPACE" get secret psmdb-secrets \
  -o jsonpath='{.data.MONGODB_DATABASE_ADMIN_USER}' | base64 -d)"
ADMIN_PASS="$(kubectl -n "$NAMESPACE" get secret psmdb-secrets \
  -o jsonpath='{.data.MONGODB_DATABASE_ADMIN_PASSWORD}' | base64 -d)"

if [[ -z "$ADMIN_USER" || -z "$ADMIN_PASS" ]]; then
  echo "Error: cannot read database-admin credentials from psmdb-secrets" >&2
  exit 1
fi

count_ready_mongod_pods() {
  kubectl -n "$NAMESPACE" get pods -l app.kubernetes.io/component=mongod --no-headers 2>/dev/null \
    | awk '$2=="1/1" && $3=="Running" {c++} END {print c+0}'
}

echo "Waiting for MongoDB StatefulSet rollout to stabilize (up to 300s)..."
if kubectl -n "$NAMESPACE" rollout status statefulset/psmdb-rs0 --timeout=300s >/dev/null 2>&1; then
  echo "  MongoDB rollout: stabilized"
else
  echo "Error: MongoDB StatefulSet did not stabilize within 300s" >&2
  kubectl -n "$NAMESPACE" get pods -l app.kubernetes.io/component=mongod >&2 || true
  exit 1
fi

ready_mongod="$(count_ready_mongod_pods)"
if [[ "$ready_mongod" -lt 3 ]]; then
  echo "Error: only $ready_mongod/3 mongod pods are Ready; aborting test" >&2
  kubectl -n "$NAMESPACE" get pods -l app.kubernetes.io/component=mongod >&2 || true
  exit 1
fi

TRACE_ID="test-$(openssl rand -hex 8)"
NOW_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
NOW_NANO="$(($(date -u +%s) * 1000000000))"

echo "Deploying test pod: $POD_NAME"
echo "  Namespace: $NAMESPACE"
echo "  MongoDB: $MONGO_HOST (replica set) / $DB_NAME.$COLLECTION"
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
  volumes:
  - name: mongo-ssl-internal
    secret:
      secretName: psmdb-ssl-internal
  containers:
  - name: test
    image: mongo:7.0
    volumeMounts:
    - name: mongo-ssl-internal
      mountPath: /etc/mongodb-ssl-internal
      readOnly: true
    command:
    - /bin/bash
    - -c
    - |
      set -e
      echo "=== Audit + Telemetry Test Pod ==="
      echo "Trace ID: ${TRACE_ID}"
      echo ""

      # Build client certificate PEM from mounted internal TLS secret.
      cat /etc/mongodb-ssl-internal/tls.key /etc/mongodb-ssl-internal/tls.crt > /tmp/tls-internal.pem

      # Step 1: Write Boomi-style audit records to MongoDB
      echo "[1/3] Writing Boomi-style audit records to MongoDB..."
      mongosh --quiet \
        --tls --tlsAllowInvalidCertificates \
        --tlsCAFile /etc/mongodb-ssl-internal/ca.crt \
        --tlsCertificateKeyFile /tmp/tls-internal.pem \
        "mongodb://${ADMIN_USER}:${ADMIN_PASS}@${MONGO_HOST}:27017/${DB_NAME}?authSource=admin&replicaSet=rs0&tls=true&tlsAllowInvalidCertificates=true" \
        --eval '
          const normalRecord = {
            trace_id: "${TRACE_ID}-n",
            ip: "192.168.1.78",
            time: "2026-05-26T17:25:47Z",
            action: "boomi.process.track",
            error_code: null,
            resource_type: "boomi.process",
            resource_id: "{6808CCD2-D77A-49C8-A96C-ED2CB38F9916}",
            user_id: "EDI_EPlatform_UpdateFixItem_V3",
            message: null,
            tpl_message: {
              key: "boomi.process.track.logged",
              params: {
                source_system: "boomi",
                sheet: "Normal",
                event: "Track",
                source: "EDI_EPlatform_UpdateFixItem_V3",
                source_info: "sysvar025256F066A-NV26061231-FAST26050490+KILYH(Uniqlo)_6b09992e-1ca5-4a36-81e3-d124fccae19d",
                process_id: "{6808CCD2-D77A-49C8-A96C-ED2CB38F9916}",
                event_id: "246964931",
                server_name: "DBPDHKC15 [SX] 192.168.1.78 //SS2014",
                start_time: "2026-05-26 17:25:47",
                original_message_log: "Updated fixed item:25256F066A-NV26061231-FAST26050490+KILYH(Uniqlo)_6b09992e-1ca5-4a36-81e3-d124fccae19d Rows updated:12",
                message_log: "Updated fixed item:25256F066A-NV26061231-FAST26050490+KILYH(Uniqlo)_6b09992e-1ca5-4a36-81e3-d124fccae19d Rows updated:12",
                notify: "0",
                fileconfig_id: "0"
              }
            },
            resource_changes: {
              event: ["Track", "Track"]
            },
            meta: {
              method: "BOOMI",
              path: "EDI_EPlatform_UpdateFixItem_V3",
              status: 200,
              ua: "DBPDHKC15 [SX] 192.168.1.78 //SS2014",
              sheet: "Normal",
              source_system: "boomi",
              pod: "${POD_NAME}"
            }
          };

          const errorRecord = {
            trace_id: "${TRACE_ID}-e",
            ip: "192.168.0.132",
            time: "2026-05-26T17:20:45Z",
            action: "boomi.process.error",
            error_code: "BOOMI_ON_ERROR",
            resource_type: "boomi.process",
            resource_id: "{23FC181C-7804-41BF-89F0-217BE9041A7C}",
            user_id: "EDI_Eplatform_OrderGrouping_V8",
            message: "Exception has been thrown by the target of an invocation.",
            tpl_message: {
              key: "boomi.process.error.logged",
              params: {
                source_system: "boomi",
                sheet: "Error",
                event: "On Error",
                source: "EDI_Eplatform_OrderGrouping_V8",
                source_info: "sysvar0: 2025121300047f1ff161-a393-415d-a739-7148f6b0c517",
                process_id: "{23FC181C-7804-41BF-89F0-217BE9041A7C}",
                event_id: "255802025",
                server_name: "DBPDHKC12 [NI] 192.168.0.132 //SS2014",
                start_time: "2026-05-26 17:20:45",
                original_message_log: "Exception has been thrown by the target of an invocation.",
                message_log: "Exception has been thrown by the target of an invocation.",
                notify: "0",
                fileconfig_id: "30069"
              }
            },
            resource_changes: {
              event: ["On Error", "On Error"]
            },
            meta: {
              method: "BOOMI",
              path: "EDI_Eplatform_OrderGrouping_V8",
              status: 500,
              ua: "DBPDHKC12 [NI] 192.168.0.132 //SS2014",
              sheet: "Error",
              source_system: "boomi",
              pod: "${POD_NAME}"
            }
          };

          const result = db.getCollection("${COLLECTION}").insertMany([normalRecord, errorRecord]);
          print("Inserted: " + Object.keys(result.insertedIds).length + " docs");
        '
      echo "  MongoDB write: OK"
      echo ""

      # Step 2: Send OTLP telemetry to SigNoz
      echo "[2/3] Sending OTLP telemetry to SigNoz..."
      if ! command -v curl >/dev/null 2>&1; then
        if command -v apt-get >/dev/null 2>&1; then
          apt-get update >/dev/null 2>&1 && apt-get install -y curl >/dev/null 2>&1
        elif command -v microdnf >/dev/null 2>&1; then
          microdnf install -y curl >/dev/null 2>&1
        elif command -v yum >/dev/null 2>&1; then
          yum install -y curl >/dev/null 2>&1
        fi
      fi
      if ! command -v curl >/dev/null 2>&1; then
        echo "  SigNoz telemetry: FAILED (curl unavailable in test image)" >&2
        exit 1
      fi

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
                "body": {"stringValue": "boomi.process.track"},
                "attributes": [
                  {"key": "trace_id", "value": {"stringValue": "${TRACE_ID}"}},
                  {"key": "action", "value": {"stringValue": "boomi.process.track"}},
                  {"key": "resource_type", "value": {"stringValue": "boomi.process"}},
                  {"key": "records.inserted", "value": {"intValue": "2"}},
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
      echo "[3/3] Verifying records in MongoDB..."
      FOUND=\$(mongosh --quiet \
        --tls --tlsAllowInvalidCertificates \
        --tlsCAFile /etc/mongodb-ssl-internal/ca.crt \
        --tlsCertificateKeyFile /tmp/tls-internal.pem \
        "mongodb://${ADMIN_USER}:${ADMIN_PASS}@${MONGO_HOST}:27017/${DB_NAME}?authSource=admin&replicaSet=rs0&tls=true&tlsAllowInvalidCertificates=true" \
        --eval '
          const count = db.getCollection("${COLLECTION}").countDocuments({trace_id: {\$in: ["${TRACE_ID}-n", "${TRACE_ID}-e"]}});
          if (count === 2) { print("FOUND"); } else { print("NOT_FOUND:" + count); }
        ')

      if [[ "\$FOUND" == "FOUND" ]]; then
        echo "  Read-back: OK (both records verified in MongoDB)"
      else
        echo "  Read-back: FAILED (records not found: \$FOUND)" >&2
        exit 1
      fi

      echo ""
      echo "=== ALL TESTS PASSED ==="
      echo "Trace ID: ${TRACE_ID}"
      echo "Record kept in: ${DB_NAME}.${COLLECTION}"
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 200m
        memory: 512Mi
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
