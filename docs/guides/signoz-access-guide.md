# SigNoz Access Guide for Infra Admin / Boomi Admin

This guide shows how to access the SigNoz telemetry platform to view application logs and metrics in the UAT environment.

## Prerequisites

Before you begin:
- You have `kubectl` configured for the UAT EKS cluster (`oms-uat-eks-cluster`)
- Your AWS SSO session is active (run `aws sso login` if expired)
- You have network access to your workstation's localhost

## Step 1: Retrieve SigNoz Credentials

The SigNoz admin credentials are stored in a Kubernetes Secret. Retrieve them:

```bash
# Get the admin email
kubectl get secret signoz-root-user -n signoz \
  -o jsonpath='{.data.email}' | base64 -d
# Output: admin@oms.local

# Get the admin password
kubectl get secret signoz-root-user -n signoz \
  -o jsonpath='{.data.password}' | base64 -d
# Output: <password> (copy this)
```

**Save these credentials** — you'll need them every time you log in.

### Alternative: Check the Local Password File

If you provisioned SigNoz yourself, the password was saved to a local gitignored file:

```bash
cat .local-dev-user-passwords.txt | grep -A 3 "SigNoz"
```

**⚠️ Security Note:** Never commit this file to git. It's already in `.gitignore`.

## Step 2: Open a Port-Forward to SigNoz

SigNoz runs inside the Kubernetes cluster and is not exposed to the internet by default. Create a temporary tunnel:

```bash
kubectl port-forward -n signoz svc/signoz 3301:8080
```

**Expected output:**
```
Forwarding from 127.0.0.1:3301 -> 8080
Forwarding from [::1]:3301 -> 8080
```

**Keep this terminal open** — the tunnel stays active only while the command is running.

**Port explanation:**
- `3301` = your local port (you'll use this in your browser)
- `8080` = SigNoz service port inside the cluster

## Step 3: Access the SigNoz UI

1. **Open your browser** and go to: **http://localhost:3301**

2. **Login page:** Enter the credentials from Step 1:
   - **Email:** `admin@oms.local`
   - **Password:** (the value you retrieved)

3. **First-time setup:** If this is the first login, SigNoz may show an onboarding wizard. You can:
   - Skip the wizard (click "Skip" or "Continue")
   - Or follow the prompts to create your organization

4. **You're in!** The SigNoz dashboard should load.

## Step 4: View Application Logs

Once logged in, here's how to find logs from your applications:

### A. Navigate to Logs

- Click **"Logs"** in the left sidebar (or go to http://localhost:3301/logs)

### B. Filter by Namespace

To see logs from a specific application:

1. Click **"Add Filter"** (top of the log stream)
2. Select **`k8s_namespace_name`**
3. Enter the namespace (e.g., `test-audit`, `mongodb-uat`, `boomi-uat`)
4. Click **"Apply"**

### C. Filter by Pod Name

To narrow down to a specific pod:

1. Click **"Add Filter"** again
2. Select **`k8s_pod_name`**
3. Enter the pod name (e.g., `audit-writer-test`)
4. Click **"Apply"**

### D. Search for Errors

To find error logs:

1. In the search bar at the top, type: `level:ERROR` or `msg:*failed*`
2. Or use the **Level** dropdown and select **"ERROR"**

### E. Example: Finding MongoDB Connection Failures

If you deployed the test pod (`audit-writer-test`), you should see logs like:

```json
{
  "level": "ERROR",
  "msg": "MongoDB connection failed",
  "service": "audit-writer",
  "attempt": 1,
  "error": "connection refused"
}
```

**Filters to use:**
- `k8s_namespace_name` = `test-audit`
- `k8s_pod_name` = `audit-writer-test`
- Search: `MongoDB connection failed`

## Step 5: Close the Port-Forward

When you're done viewing logs:

1. **Go back to the terminal** where `kubectl port-forward` is running
2. Press **`Ctrl+C`** to stop the tunnel
3. The SigNoz UI will become inaccessible (http://localhost:3301 will not load)

**To reconnect later:** Re-run the `kubectl port-forward` command from Step 2.

## Troubleshooting

### "Unable to connect" / "ERR_CONNECTION_REFUSED"

**Cause:** Port-forward is not running

**Fix:**
```bash
# Check if port-forward is running
ps aux | grep "kubectl port-forward"

# If not, restart it
kubectl port-forward -n signoz svc/signoz 3301:8080
```

### "Invalid credentials" / "Login failed"

**Cause:** Incorrect email or password

**Fix:** Re-run Step 1 to retrieve the current credentials from the Secret.

### "AWS SSO token expired"

**Cause:** Your AWS session timed out

**Fix:**
```bash
aws sso login
# Then retry kubectl commands
```

### "Namespace 'signoz' not found"

**Cause:** SigNoz is not provisioned yet

**Fix:** Ask your Infra Admin to provision SigNoz:
```bash
kubectl apply -k gitops/signoz/overlays/uat
```

## Alternative Access Methods

### Option B: Permanent Ingress (Production Use)

For shared team access without port-forwarding, an Ingress can be configured:

```bash
# This requires:
# 1. AWS Load Balancer Controller (already installed in UAT)
# 2. A DNS name (e.g., signoz.uat.oms.internal)
# 3. TLS certificate (optional but recommended)

# Contact your Infra Admin to set this up
```

### Option C: Using a Jump Host / Bastion

If accessing from a restricted network:

```bash
# SSH tunnel through bastion
ssh -L 3301:localhost:3301 bastion-host
# Then on bastion: kubectl port-forward -n signoz svc/signoz 3301:8080
```

## Quick Reference Card

```bash
# Login credentials
kubectl get secret signoz-root-user -n signoz -o jsonpath='{.data.email}' | base64 -d
kubectl get secret signoz-root-user -n signoz -o jsonpath='{.data.password}' | base64 -d

# Start UI access
kubectl port-forward -n signoz svc/signoz 3301:8080

# Browser: http://localhost:3301
# Email: admin@oms.local
# Password: <from command above>

# Stop UI access
# Press Ctrl+C in the port-forward terminal
```

## Next Steps

- **For Infra Admins:** See `docs/references/verification-commands.md` for SigNoz health checks
- **For Boomi Admins:** See `docs/guides/boomi-integration-guide.md` for audit log integration
- **For Dashboards:** SigNoz Observability (dashboards + alerts) provisioning is documented in `docs/references/signoz-dashboard-import-pack.md`

## Security Best Practices

1. **Never share credentials via email or Slack** — retrieve them from the Secret as needed
2. **Rotate the admin password** after initial setup (SigNoz UI → Settings → Account)
3. **Create service-specific accounts** — don't use the admin account for application telemetry
4. **Close port-forwards** when not in use — don't leave them running overnight
5. **Use SSO/SAML** for production access (requires SigNoz Enterprise)

---

**Related Documentation:**
- [SigNoz Dashboard Import Pack](../references/signoz-dashboard-import-pack.md)
- [Component Catalog](../references/component-catalog.md) — SigNoz architecture
- [Verification Commands](../references/verification-commands.md) — Health checks
