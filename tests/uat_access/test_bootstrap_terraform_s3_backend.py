import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
BACKEND_BOOTSTRAP = REPO_ROOT / "scripts" / "bootstrap-terraform-s3-backend.sh"
EXPECTED_OWNER = "672172129937"


class TerraformS3BackendTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.temp_path = Path(self.temp_dir.name)
        self.mock_bin = self.temp_path / "bin"
        self.mock_bin.mkdir()
        self.command_log = self.temp_path / "commands.log"
        self.created_marker = self.temp_path / "bucket-created"
        self.create_attempted_marker = self.temp_path / "bucket-create-attempted"
        self.tf_dir = self.temp_path / "terraform"
        self.tf_dir.mkdir()
        (self.tf_dir / "main.tf").write_text('terraform { backend "s3" {} }\n')
        self._write_mock(
            "aws",
            """#!/usr/bin/env bash
printf 'aws %s\n' "$*" >> "$MOCK_COMMAND_LOG"
operation="${1:-} ${2:-}"
case "$operation" in
  "s3api head-bucket")
        if [[ "$MOCK_CREATE_RACE" != "none" && -f "$MOCK_CREATE_ATTEMPTED_MARKER" ]]; then
            [[ "$MOCK_CREATE_RACE" == "same-owner" ]] && exit 0
            exit 42
        fi
    if [[ "$MOCK_BUCKET_STATE" == "wrong-owner" ]]; then
      exit 42
    fi
    if [[ "$MOCK_BUCKET_STATE" == "missing" && ! -f "$MOCK_CREATED_MARKER" ]]; then
      exit 42
    fi
    ;;
  "s3api create-bucket")
        if [[ "$MOCK_CREATE_RACE" != "none" ]]; then
            : > "$MOCK_CREATE_ATTEMPTED_MARKER"
            printf 'create failed\n' >&2
            exit 43
        fi
    if [[ "$MOCK_BUCKET_STATE" == "wrong-owner" ]]; then
      exit 43
    fi
    : > "$MOCK_CREATED_MARKER"
    ;;
  "s3api get-bucket-location")
    printf '%s\n' "$MOCK_BUCKET_REGION"
    ;;
  "s3api get-bucket-versioning")
    printf '%s\n' "$MOCK_VERSIONING_STATUS"
    ;;
  "s3api get-bucket-encryption")
    [[ "$MOCK_ENCRYPTION" != "absent" ]] || exit 44
    printf '%s\n' "$MOCK_ENCRYPTION"
    ;;
  "s3api get-public-access-block")
    printf '%s\n' "$MOCK_PUBLIC_ACCESS_BLOCK"
    ;;
    "s3api head-object")
        case "$MOCK_REMOTE_STATE_STATUS" in
            exists) ;;
            absent)
                printf 'An error occurred (404) when calling the HeadObject operation: Not Found\n' >&2
                exit 42
                ;;
            forbidden)
                printf 'An error occurred (403) when calling the HeadObject operation: Forbidden\n' >&2
                exit 42
                ;;
            forbidden-not-found)
                printf 'An error occurred (403) when calling the HeadObject operation: Forbidden: Not Found\n' >&2
                exit 42
                ;;
            bad-request)
                printf 'An error occurred (400) when calling the HeadObject operation: Bad Request\n' >&2
                exit 42
                ;;
            bad-request-not-found)
                printf 'An error occurred (400) when calling the HeadObject operation: Bad Request: Not Found\n' >&2
                exit 42
                ;;
            network)
                printf 'Could not connect to the endpoint URL: https://s3.invalid\n' >&2
                exit 42
                ;;
            proxy-nosuchkey)
                printf 'Proxy error while requesting https://s3.invalid: NoSuchKey\n' >&2
                exit 42
                ;;
        esac
        ;;
    "s3api put-bucket-versioning"|"s3api put-bucket-encryption"|\
    "s3api put-public-access-block")
    ;;
  *)
    printf 'unsupported mock aws invocation: %s\n' "$*" >&2
    exit 64
    ;;
esac
""",
        )
        self._write_mock(
            "terraform",
            """#!/usr/bin/env bash
printf 'terraform %s\n' "$*" >> "$MOCK_COMMAND_LOG"
""",
        )
        self._write_mock("rg", "#!/usr/bin/env bash\nexit 0\n")

    def tearDown(self):
        self.temp_dir.cleanup()

    def _write_mock(self, name, content):
        path = self.mock_bin / name
        path.write_text(content)
        path.chmod(path.stat().st_mode | stat.S_IXUSR)

    def run_backend(
        self,
        *,
        bucket_state="existing",
        requested_region="ap-east-1",
        bucket_region="ap-east-1",
        versioning="Enabled",
        encryption="AES256",
        public_access_block="True\tTrue\tTrue\tTrue",
        expected_owner=EXPECTED_OWNER,
        remote_state_status="exists",
        create_race="none",
    ):
        env = os.environ.copy()
        env.update({
            "PATH": f"{self.mock_bin}:{env['PATH']}",
            "MOCK_COMMAND_LOG": str(self.command_log),
            "MOCK_CREATED_MARKER": str(self.created_marker),
            "MOCK_CREATE_ATTEMPTED_MARKER": str(self.create_attempted_marker),
            "MOCK_CREATE_RACE": create_race,
            "MOCK_BUCKET_STATE": bucket_state,
            "MOCK_BUCKET_REGION": bucket_region,
            "MOCK_VERSIONING_STATUS": versioning,
            "MOCK_ENCRYPTION": encryption,
            "MOCK_PUBLIC_ACCESS_BLOCK": public_access_block,
            "MOCK_REMOTE_STATE_STATUS": remote_state_status,
        })
        arguments = [
            "bash", str(BACKEND_BOOTSTRAP),
            "--tf-dir", str(self.tf_dir),
            "--bucket", "sml-oms-uat-tfstate-672172129937",
            "--region", requested_region,
            "--key", "oms/uat/access-governance.tfstate",
        ]
        if expected_owner is not None:
            arguments.extend(["--expected-bucket-owner", expected_owner])
        return subprocess.run(arguments, env=env, text=True, capture_output=True)

    def command_lines(self):
        return self.command_log.read_text().splitlines()

    def test_existing_bucket_verifies_owner_controls_and_backend_config(self):
        result = self.run_backend()

        self.assertEqual(result.returncode, 0, result.stderr)
        lines = self.command_lines()
        owner_flag = f"--expected-bucket-owner {EXPECTED_OWNER}"
        for operation in (
            "head-bucket", "get-bucket-location", "get-bucket-versioning",
            "get-bucket-encryption", "get-public-access-block", "head-object",
        ):
            line = next(line for line in lines if f"s3api {operation}" in line)
            self.assertIn(owner_flag, line)
        terraform_init = next(line for line in lines if line.startswith("terraform "))
        self.assertIn(
            f"-backend-config=expected_bucket_owner={EXPECTED_OWNER}",
            terraform_init,
        )

    def test_owner_mismatch_stops_before_terraform(self):
        result = self.run_backend(bucket_state="wrong-owner")

        self.assertNotEqual(result.returncode, 0)
        commands = "\n".join(self.command_lines())
        self.assertNotIn("put-bucket-", commands)
        self.assertNotIn("put-public-access-block", commands)
        self.assertNotIn("terraform ", commands)

    def test_wrong_region_stops_before_terraform(self):
        result = self.run_backend(bucket_region="us-east-1")

        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(line.startswith("terraform ") for line in self.command_lines()))

    def test_us_east_1_null_location_is_normalized(self):
        for bucket_region in ("None", "null"):
            with self.subTest(bucket_region=bucket_region):
                self.command_log.unlink(missing_ok=True)
                result = self.run_backend(
                    requested_region="us-east-1",
                    bucket_region=bucket_region,
                )

                self.assertEqual(result.returncode, 0, result.stderr)

    def test_eu_location_is_normalized_to_eu_west_1(self):
        result = self.run_backend(
            requested_region="eu-west-1",
            bucket_region="EU",
        )

        self.assertEqual(result.returncode, 0, result.stderr)

    def test_disabled_versioning_stops_before_terraform(self):
        result = self.run_backend(versioning="Suspended")

        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(line.startswith("terraform ") for line in self.command_lines()))

    def test_absent_encryption_stops_before_terraform(self):
        result = self.run_backend(encryption="absent")

        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(line.startswith("terraform ") for line in self.command_lines()))

    def test_incomplete_public_access_block_stops_before_terraform(self):
        result = self.run_backend(public_access_block="True True False True")

        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(line.startswith("terraform ") for line in self.command_lines()))

    def test_new_bucket_is_baselined_then_verified(self):
        result = self.run_backend(bucket_state="missing")

        self.assertEqual(result.returncode, 0, result.stderr)
        lines = self.command_lines()
        create_index = next(index for index, line in enumerate(lines) if "create-bucket" in line)
        baseline_indexes = [
            next(index for index, line in enumerate(lines) if operation in line)
            for operation in (
                "put-bucket-versioning", "put-bucket-encryption",
                "put-public-access-block",
            )
        ]
        verify_index = next(
            index for index, line in enumerate(lines)
            if index > create_index and "head-bucket" in line
        )
        terraform_index = next(
            index for index, line in enumerate(lines) if line.startswith("terraform ")
        )
        self.assertLess(create_index, min(baseline_indexes))
        self.assertLess(max(baseline_indexes), verify_index)
        self.assertLess(verify_index, terraform_index)
        owner_flag = f"--expected-bucket-owner {EXPECTED_OWNER}"
        for operation in (
            "put-bucket-versioning", "put-bucket-encryption",
            "put-public-access-block",
        ):
            line = next(line for line in lines if operation in line)
            self.assertIn(owner_flag, line)

    def test_same_owner_create_race_is_baselined_and_verified(self):
        result = self.run_backend(
            bucket_state="missing",
            create_race="same-owner",
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        commands = "\n".join(self.command_lines())
        self.assertIn("s3api create-bucket", commands)
        self.assertIn("s3api put-bucket-versioning", commands)
        self.assertTrue(any(line.startswith("terraform ") for line in self.command_lines()))

    def test_unresolved_create_race_stops_before_baseline_or_terraform(self):
        result = self.run_backend(
            bucket_state="missing",
            create_race="unresolved",
        )

        self.assertNotEqual(result.returncode, 0)
        commands = "\n".join(self.command_lines())
        self.assertNotIn("put-bucket-", commands)
        self.assertNotIn("put-public-access-block", commands)
        self.assertNotIn("terraform ", commands)

    def test_legacy_create_failure_is_not_recovered_without_expected_owner(self):
        result = self.run_backend(
            bucket_state="missing",
            create_race="same-owner",
            expected_owner=None,
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("put-bucket-", "\n".join(self.command_lines()))
        self.assertFalse(any(line.startswith("terraform ") for line in self.command_lines()))

    def test_legacy_call_omits_owner_assertions_and_backend_config(self):
        result = self.run_backend(expected_owner=None)

        self.assertEqual(result.returncode, 0, result.stderr)
        commands = "\n".join(self.command_lines())
        self.assertNotIn("--expected-bucket-owner", commands)
        self.assertNotIn("expected_bucket_owner=", commands)

    def test_local_state_migration_includes_owner_backend_config(self):
        (self.tf_dir / "terraform.tfstate").write_text("{}\n")

        result = self.run_backend(remote_state_status="absent")

        self.assertEqual(result.returncode, 0, result.stderr)
        terraform_init = next(
            line for line in self.command_lines() if line.startswith("terraform ")
        )
        self.assertIn("init -migrate-state", terraform_init)
        self.assertIn(
            f"-backend-config=expected_bucket_owner={EXPECTED_OWNER}",
            terraform_init,
        )

    def test_fresh_init_includes_owner_backend_config(self):
        result = self.run_backend(remote_state_status="absent")

        self.assertEqual(result.returncode, 0, result.stderr)
        terraform_init = next(
            line for line in self.command_lines() if line.startswith("terraform ")
        )
        self.assertIn("init -reconfigure", terraform_init)
        self.assertIn(
            f"-backend-config=expected_bucket_owner={EXPECTED_OWNER}",
            terraform_init,
        )

    def assert_remote_state_inspection_aborts(self, remote_state_status):
        (self.tf_dir / "terraform.tfstate").write_text("{}\n")
        result = self.run_backend(remote_state_status=remote_state_status)

        self.assertNotEqual(result.returncode, 0)
        self.assertIn(
            "Unable to determine whether remote state exists",
            result.stderr,
        )
        self.assertFalse(any(
            line.startswith("terraform ") for line in self.command_lines()
        ))

    def test_403_forbidden_not_found_stops_before_terraform(self):
        self.assert_remote_state_inspection_aborts("forbidden-not-found")

    def test_proxy_nosuchkey_stops_before_terraform(self):
        self.assert_remote_state_inspection_aborts("proxy-nosuchkey")

    def test_400_not_found_stops_before_terraform(self):
        self.assert_remote_state_inspection_aborts("bad-request-not-found")

    def test_ambiguous_remote_state_failures_stop_before_terraform(self):
        (self.tf_dir / "terraform.tfstate").write_text("{}\n")
        for remote_state_status in ("forbidden", "bad-request", "network"):
            with self.subTest(remote_state_status=remote_state_status):
                self.command_log.unlink(missing_ok=True)
                result = self.run_backend(remote_state_status=remote_state_status)

                self.assertNotEqual(result.returncode, 0)
                self.assertIn(
                    "Unable to determine whether remote state exists",
                    result.stderr,
                )
                self.assertFalse(any(
                    line.startswith("terraform ") for line in self.command_lines()
                ))


if __name__ == "__main__":
    unittest.main()