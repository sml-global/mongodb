# Git Hooks

This directory contains git hooks to enforce repository policies.

## Pre-Commit Hook: Enforce sml_admin Account

**Purpose**: Ensures all commits use the corporate `sml_admin` GitHub account, not personal accounts.

**What it checks**:
- `user.name` must be `sml_admin`
- `user.email` must be `sml_admin@sml.local`

**Setup** (already done in this repo):
```bash
# This repo is already configured to use .githooks
git config core.hooksPath .githooks
```

**If the hook fails**, you'll see:
```
❌ ERROR: Git user is not configured correctly for this repository

Current configuration:
  user.name  = Frank
  user.email = agentfuture818@gmail.com

Required configuration:
  user.name  = sml_admin
  user.email = sml_admin@sml.local

To fix this, run:
  git config user.name "sml_admin"
  git config user.email "sml_admin@sml.local"
```

**To set globally** (recommended for all SML repos):
```bash
git config --global user.name "sml_admin"
git config --global user.email "sml_admin@sml.local"
```

**To bypass the hook** (NOT recommended - only for emergency commits):
```bash
git commit --no-verify -m "emergency fix"
```

## Installing in Other Repos

To use the same hook in other SML repositories:

```bash
# Copy the hook
cp .githooks/pre-commit /path/to/other-repo/.githooks/
chmod +x /path/to/other-repo/.githooks/pre-commit

# Configure the other repo
cd /path/to/other-repo
git config core.hooksPath .githooks
git config user.name "sml_admin"
git config user.email "sml_admin@sml.local"
```

## GitHub Issues

For GitHub CLI (`gh`) commands (creating issues, PRs), ensure you're authenticated with the correct account.

**`gh` has no per-repo account scoping** (unlike git's `user.name`/`user.email`, which are per-repo config) — it's a single global keyring state (`gh auth switch`) shared across every repo on the machine. This repo enforces the correct account (`sml-admin`) two ways:

### 1. `pre-push` hook (enforced automatically)

`.githooks/pre-push` blocks `git push` if the active `gh` account isn't `sml-admin`. This only covers `git push` — it does NOT cover `gh issue create`, `gh pr create`, `gh pr comment`, etc., since those are plain `gh` invocations, not git operations.

### 2. `scripts/gh` wrapper (use this for issue/PR commands)

Use `scripts/gh` instead of calling `gh` directly for anything that creates or modifies GitHub state:
```bash
scripts/gh issue create --title "..." --body "..."
scripts/gh pr create --title "..." --body "..."
scripts/gh issue comment 82 --body "..."
```
It auto-switches to `sml-admin` before running the command if the active account is wrong, so you can't accidentally create an issue/PR/comment from a personal account.

### Manual check/switch

```bash
# Check current GitHub account
gh auth status

# Switch to the corporate account (already authenticated once via keyring)
gh auth switch --hostname github.com --user sml-admin

# If sml-admin isn't authenticated yet on this machine
gh auth login
# When prompted:
# - Account: GitHub.com
# - Protocol: HTTPS
# - Authenticate: Login with a web browser
# - Login as: sml-admin
```

**Note**: The `pre-commit` hook only validates git commit identity. The `pre-push` hook validates `gh`'s active account at push time. Neither one retroactively fixes commits already made under the wrong `gh` account (that only affects PR/issue authorship metadata via the API, not commit authorship, which `pre-commit` already covers).

