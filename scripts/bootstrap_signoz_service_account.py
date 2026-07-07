#!/usr/bin/env python3
"""Automates the one-time SigNoz Service Account + API key bootstrap using
Playwright (headless Chromium), so this step never requires a human -- or an
AI agent -- to click through the SigNoz UI by hand.

SigNoz does not expose a documented headless/API-only way to create a
Service Account and its first API key (this itself has to authenticate with
*something*), so this script drives the same UI flow a human would, but as a
repeatable, scripted, non-interactive process:

  1. Log in with the root-user credentials (see create-signoz-root-user-secret.sh)
  2. Settings -> Service Accounts -> create one (idempotent: reuses an
     existing account with the same name instead of creating a duplicate)
  3. Assign it the given role (default: signoz-admin)
  4. Keys tab -> create a new API key and print ONLY the key value to stdout

All human-readable progress/log output goes to stderr, so this script's
stdout can be safely captured by a wrapping shell script, e.g.:

    TOKEN="$(python3 bootstrap_signoz_service_account.py --url ... --email ... --password ...)"

Usage:
  bootstrap_signoz_service_account.py --url <signoz-url> --email <root-email> \\
      --password <root-password> [--account-name NAME] [--role ROLE] \\
      [--key-name NAME] [--headed]
"""
import argparse
import sys


def log(*args):
    print(*args, file=sys.stderr, flush=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", required=True, help="SigNoz base URL, e.g. http://127.0.0.1:3301")
    parser.add_argument("--email", required=True, help="Root user email")
    parser.add_argument("--password", required=True, help="Root user password")
    parser.add_argument("--account-name", default="terraform-automation", help="Service Account name")
    parser.add_argument("--role", default="signoz-admin", help="Role to assign to the Service Account")
    parser.add_argument("--key-name", default="terraform-automation-key", help="API key name")
    parser.add_argument("--headed", action="store_true", help="Run with a visible browser window (debugging)")
    args = parser.parse_args()

    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        log("Error: the 'playwright' Python package is not installed.")
        log("Install it with: python3 -m pip install playwright && python3 -m playwright install chromium")
        return 1

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=not args.headed)
        page = browser.new_page()

        try:
            _login(page, args.url, args.email, args.password, log)
            account_id = _ensure_service_account(page, args.url, args.account_name, log)
            _ensure_role(page, account_id, args.role, log)
            key = _create_key(page, args.key_name, log)
        except Exception:
            import os
            if os.environ.get("SIGNOZ_BOOTSTRAP_DEBUG"):
                page.screenshot(path="/tmp/signoz-bootstrap-failure.png", full_page=True)
                with open("/tmp/signoz-bootstrap-failure.html", "w") as f:
                    f.write(page.content())
                log("Debug screenshot saved to /tmp/signoz-bootstrap-failure.png")
                log("Debug HTML saved to /tmp/signoz-bootstrap-failure.html")
            raise
        finally:
            browser.close()

    # ONLY the key goes to stdout.
    print(key)
    return 0


def _login(page, base_url, email, password, log):
    log(f"Logging in to {base_url} as {email} ...")
    page.goto(f"{base_url}/login", wait_until="domcontentloaded")
    page.get_by_placeholder("e.g. john@signoz.io").fill(email)
    page.get_by_role("button", name="Next").click()
    page.get_by_placeholder("Enter password").fill(password)
    page.get_by_role("button", name="Sign in with Password").click()
    page.wait_for_url(lambda url: "/login" not in url, timeout=15000)
    log("Login successful.")


def _ensure_service_account(page, base_url, account_name, log):
    log(f"Opening Service Accounts settings, ensuring '{account_name}' exists ...")
    page.goto(f"{base_url}/settings/service-accounts", wait_until="domcontentloaded")
    page.wait_for_load_state("networkidle")

    existing = page.get_by_role("button", name=f"View service account {account_name}")
    if existing.count() > 0:
        log(f"Service account '{account_name}' already exists; reusing it.")
        existing.first.click()
    else:
        log(f"Creating new service account '{account_name}' ...")
        page.get_by_role("button", name="New Service Account").click()
        page.get_by_placeholder("Enter a name").fill(account_name)
        page.get_by_role("button", name="Create Service Account").click()

    page.wait_for_selector("text=Service Account Details", timeout=10000)
    page.wait_for_timeout(500)
    url = page.url
    account_id = url.split("account=")[-1].split("&")[0]
    log(f"Service account ID: {account_id}")
    return account_id


def _ensure_role(page, account_id, role, log):
    log(f"Ensuring role '{role}' is assigned ...")
    page.get_by_role("combobox", name="Roles").click()

    # The multiselect renders the role as BOTH a hidden "selected value"
    # <option> element (part of the combobox's own display, not clickable)
    # AND a real checkbox in the popover list -- always target the checkbox.
    checkbox = page.get_by_role("checkbox", name=role)
    checkbox.wait_for(state="visible", timeout=10000)
    already_selected = checkbox.is_checked()

    if already_selected:
        log(f"Role '{role}' already assigned; skipping.")
    else:
        # The option row's label text visually overlaps the checkbox button
        # (Ant Design Select rendering) and the popover can render partially
        # outside the dialog's visible scroll area, so Playwright's
        # actionability checks (interception, viewport) reject a normal
        # click even though the element is the correct, real target -- a
        # raw DOM click sidesteps both checks.
        checkbox.evaluate("el => el.click()")
        log(f"Role '{role}' selected.")

    # Close the dropdown by clicking the dialog heading (a neutral, always-
    # present element) -- NOT Escape, which closes the whole "Service Account
    # Details" dialog rather than just the roles multiselect popover.
    page.get_by_role("heading", name="Service Account Details").click()

    if already_selected:
        return

    save_button = page.get_by_role("button", name="Save Changes")
    save_button.wait_for(state="visible", timeout=5000)
    # The dialog's footer button is frequently reported "outside viewport" by
    # Playwright's actionability checks even though it's visible (sticky
    # footer in a scrollable dialog) -- a raw DOM click sidesteps that.
    save_button.evaluate("el => el.click()")
    page.wait_for_timeout(500)
    log(f"Role '{role}' saved.")


def _create_key(page, key_name, log):
    log("Switching to Keys tab ...")
    page.get_by_role("radio", name="Keys").click()
    page.wait_for_timeout(500)

    add_key_button = page.get_by_role("button", name="Add Key")
    if add_key_button.count() == 0:
        add_key_button = page.get_by_role("button", name="+ Add your first key")
    add_key_button.first.click()

    # Use the textbox's accessible name (confirmed via manual inspection),
    # not get_by_label -- the "Name *" text is not a real <label for=...>
    # element here, so get_by_label silently matches nothing and leaves the
    # field empty (which then leaves "Create Key" disabled with no error).
    name_field = page.get_by_role("dialog", name="Add a New Key").get_by_role("textbox", name="Name *")
    name_field.fill(key_name)

    create_button = page.get_by_role("dialog", name="Add a New Key").get_by_role("button", name="Create Key")
    create_button.wait_for(state="visible", timeout=5000)
    # The dialog's footer button is frequently reported "outside viewport" by
    # Playwright's actionability checks even though it's visible (sticky
    # footer in a scrollable dialog) -- a raw DOM click sidesteps that.
    create_button.evaluate("el => el.click()")

    page.wait_for_selector("text=Key Created Successfully", timeout=10000)
    # The key value is rendered in a generic element right after the "Key"
    # label inside the success dialog; grab it via the dialog's text content
    # and pattern-match rather than relying on a brittle CSS selector.
    dialog_text = page.locator("text=Key Created Successfully").locator("..").locator("..").inner_text()
    key = None
    lines = [line.strip() for line in dialog_text.splitlines() if line.strip()]
    for i, line in enumerate(lines):
        if line == "Key" and i + 1 < len(lines):
            key = lines[i + 1]
            break
    if not key:
        raise RuntimeError("Could not locate the generated API key value in the confirmation dialog.")

    log("API key created successfully.")
    return key


if __name__ == "__main__":
    sys.exit(main())
