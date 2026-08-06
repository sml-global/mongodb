# Step-by-Step: Provision SigNoz Dashboards for UAT

**Goal:** Provision 5 Kubernetes/MongoDB/PostgreSQL dashboards + 5 alert rules via Terraform (GitOps/repeatable)

**Time:** ~10 minutes

---

## Step 1: Create SigNoz API Token (One-Time)

1. **Port-forward to SigNoz UI** (if not already running):
   ```bash
   kubectl port-forward -n signoz-uat svc/signoz 3302:8080
   ```

2. **Login to SigNoz**:
   - URL: http://localhost:3302
   - Email: `admin@oms.local`
   - Password: (run this to get it)
     ```bash
     kubectl get secret signoz-root-user -n signoz-uat -o jsonpath='{.data.password}' | base64 -d && echo
     ```

3. **Create API Key**:
   - Go to **Settings** (gear icon, bottom left)
   - Click **API Keys** (left sidebar)
   - Click **+ New Key**
   - Fill in:
     - **Name:** `terraform-uat-provisioner`
     - **Role:** `Admin`
     - **Expiration:** `Never` (or 1 year)
   - Click **Create**
   - **IMPORTANT:** Copy the token (shown only once!)

4. **Save token to Kubernetes secret**:
   ```bash
   kubectl create secret generic signoz-api-key \
     -n signoz-uat \
     --from-literal=token="<PASTE-YOUR-TOKEN-HERE>"
   ```

---

## Step 2: Run Terraform Provisioning

```bash
# Navigate to Terraform root
cd platform-prerequisites/terraform/signoz-observability

# Set environment variables
export SIGNOZ_ENDPOINT="http://127.0.0.1:3302"
export SIGNOZ_NAMESPACE="signoz-uat"
export SIGNOZ_ACCESS_TOKEN=$(kubectl get secret signoz-api-key -n signoz-uat -o jsonpath='{.data.token}' | base64 -d)

# Initialize Terraform with UAT state
terraform init \
  -backend-config="bucket=sml-oms-dev-tfstate" \
  -backend-config="key=oms/uat/signoz-observability.tfstate" \
  -backend-config="region=ap-east-1" \
  -reconfigure

# Plan (review changes)
terraform plan

# Apply (create dashboards + alerts)
terraform apply
```

**When prompted "Do you want to perform these actions?"** → type `yes`

---

## Step 3: Verify Dashboards

1. Go to SigNoz UI: http://localhost:3302
2. Click **Dashboards** (left sidebar)
3. You should see 5 dashboards:
   - ✅ Kubernetes Node Metrics - Overall
   - ✅ Kubernetes Pod Metrics - Overall
   - ✅ MongoDB Overview
   - ✅ AWS RDS PostgreSQL Overview
   - ✅ OpenTelemetry Collector Pipeline Health

4. Click on "Kubernetes Node Metrics - Overall"
5. Wait 2-3 minutes for metrics to populate
6. You should see CPU/memory/disk charts with live data

---

## Expected Terraform Output

```
Terraform will perform the following actions:

  # signoz_dashboard.k8s_node_metrics will be created
  + resource "signoz_dashboard" "k8s_node_metrics" {
      + id    = (known after apply)
      + title = "Kubernetes Node Metrics - Overall"
      ...
    }

  # signoz_dashboard.k8s_pod_metrics will be created
  ...

  # signoz_dashboard.mongodb will be created
  ...

  # signoz_dashboard.postgres will be created
  ...

  # signoz_dashboard.otel_collector will be created
  ...

Plan: 10 to add, 0 to change, 0 to destroy.
```

---

## What Gets Created

### Dashboards (5)

1. **Kubernetes Node Metrics**
   - CPU utilization per node
   - Memory usage per node
   - Disk I/O per node
   - Network traffic per node

2. **Kubernetes Pod Metrics**
   - CPU/memory per pod
   - Pod status (Running/Pending/Failed)
   - Restart count (crash loop detection)
   - Filterable by namespace: `mongodb-uat`, `signoz-uat`, etc.

3. **MongoDB Overview**
   - Current connections
   - Operations/sec (insert/query/update/delete)
   - Replication lag
   - Storage size

4. **AWS RDS PostgreSQL Overview**
   - CPU utilization
   - Database connections
   - Read/Write IOPS
   - Free storage

5. **OpenTelemetry Collector Pipeline Health**
   - Export failures
   - Queue length
   - Processing rate

### Alert Rules (5)

1. **MongoDB No Data** — Fires if no MongoDB metrics for 10min
2. **PostgreSQL CPU High** — Fires if CPU > 80% for 5min
3. **K8s Node CPU High** — Fires if node CPU > 90% for 5min
4. **OTel Export Failures** — Fires if export failures > 100/min
5. **Boomi Telemetry No Data** — Fires if no Boomi audit logs for 10min

---

## Troubleshooting

### Problem: "Error: 401 Unauthorized"

**Cause:** API token invalid or expired

**Fix:**
```bash
# Verify token is in secret
kubectl get secret signoz-api-key -n signoz-uat -o jsonpath='{.data.token}' | base64 -d && echo

# If empty or wrong, recreate:
kubectl delete secret signoz-api-key -n signoz-uat
# Then go back to Step 1 and create a new API key
```

---

### Problem: "Error: connection refused"

**Cause:** Port-forward not running or wrong port

**Fix:**
```bash
# Check if port-forward is running
lsof -ti:3302

# If not, start it:
kubectl port-forward -n signoz-uat svc/signoz 3302:8080
```

---

### Problem: Dashboards created but show "No Data"

**Cause:** Metrics not flowing yet (takes 2-5 minutes after OTEL agent restart)

**Fix:**
1. Wait 5 minutes
2. Check OTEL agent logs:
   ```bash
   kubectl logs -n signoz-uat -l app.kubernetes.io/component=otel-agent --tail=20
   ```
3. Verify no errors (should see successful metric exports)
4. Refresh SigNoz dashboard

---

### Problem: "Error: dashboard already exists"

**Cause:** You ran terraform twice and it's trying to create duplicates

**Fix:**
```bash
# Import existing dashboards into state
terraform import signoz_dashboard.k8s_node_metrics <dashboard-id>

# Or destroy and recreate
terraform destroy
terraform apply
```

---

## After Provisioning

### Update Documentation

Add this to your team's runbook:

**SigNoz UAT Dashboards:**
- Provisioned via Terraform (repeatable)
- State: `s3://sml-oms-dev-tfstate/oms/uat/signoz-observability.tfstate`
- To update: Edit `platform-prerequisites/terraform/signoz-observability/*.tf` and re-run `terraform apply`
- API token stored in secret: `signoz-api-key` (namespace: `signoz-uat`)

### Share with Team

1. Port-forward command:
   ```bash
   kubectl port-forward -n signoz-uat svc/signoz 3302:8080
   ```

2. Login credentials:
   - Email: `admin@oms.local`
   - Password: (get from secret or `.local-dev-user-passwords.txt`)

3. Key dashboards:
   - **K8s Pod Metrics** → Filter by namespace to monitor specific workloads
   - **MongoDB Overview** → Monitor audit trail database health
   - **OTel Collector** → Detect telemetry pipeline issues

---

## Re-Running (Idempotent)

Terraform is idempotent — running it multiple times is safe:

```bash
# Update dashboard definition
vim platform-prerequisites/terraform/signoz-observability/dashboards.tf

# Re-apply (updates in-place, doesn't create duplicates)
export SIGNOZ_ACCESS_TOKEN=$(kubectl get secret signoz-api-key -n signoz-uat -o jsonpath='{.data.token}' | base64 -d)
export SIGNOZ_ENDPOINT="http://127.0.0.1:3302"
terraform apply
```

**Result:** Terraform updates the existing dashboard (same ID), doesn't create a new one.

---

## Summary

✅ **Repeatable** — Terraform provisions dashboards as code (no manual UI clicks)  
✅ **Version-controlled** — Dashboard JSON in Git (`dashboards/signoz-import-pack/`)  
✅ **Idempotent** — Safe to re-run; updates in place  
✅ **Environment-isolated** — UAT has separate state from DEV  
✅ **Team-shareable** — Anyone with kubectl + Terraform can provision

**Next:** Add Boomi-specific dashboard (custom queries from earlier doc)
