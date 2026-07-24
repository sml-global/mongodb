import os
import stat
import unittest

from .helpers import RepositoryFixture


class EnvironmentContractTests(RepositoryFixture):
    def setUp(self):
        super().setUp()
        self.copy(
            "scripts/lib/platform-env.sh",
            "scripts/lib/environment-contracts.sh",
            "config/environment-schema/base.manifest",
            "config/environments/dev.env",
            "config/environments/uat.env",
        )

    def load(self, environment):
        return self.run_bash(
            'source scripts/lib/platform-env.sh && '
            f'load_platform_env {environment} && '
            "printf '%s|%s|%s|%s\\n' \"$ENVIRONMENT\" "
            '"$EXPECTED_AWS_ACCOUNT_ID" "$AWS_REGION" "$PROMOTION_MODE"'
        )

    def env_path(self, environment):
        return self.root / "config" / "environments" / f"{environment}.env"

    # -- Step 1 baseline: successful loads, no commands ever invoked --------

    def test_exact_dev_and_uat_contracts_load_without_commands(self):
        expected = {
            "dev": "dev|815402439714|ap-east-1|modeled\n",
            "uat": "uat|672172129937|ap-east-1|uat-build\n",
        }
        for environment, output in expected.items():
            with self.subTest(environment=environment):
                result = self.load(environment)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, output)
                self.assertFalse(self.command_log.exists())

    def test_rejects_shell_syntax_without_executing_it(self):
        uat = self.env_path("uat")
        original = uat.read_text(encoding="utf-8")
        cases = {
            "quoted": 'AWS_REGION="ap-east-1"',
            "command substitution": "AWS_REGION=$(touch exploited)",
            "backticks": "AWS_REGION=`touch exploited`",
            "export": "export AWS_REGION=ap-east-1",
            "inline comment": "AWS_REGION=ap-east-1 # wrong",
            "escape": r"AWS_REGION=ap-east-1\\x",
            "semicolon": "AWS_REGION=ap-east-1; touch exploited",
        }
        for label, replacement in cases.items():
            with self.subTest(label=label):
                uat.write_text(
                    original.replace("AWS_REGION=ap-east-1", replacement),
                    encoding="utf-8",
                )
                result = self.load("uat")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("invalid dotenv assignment", result.stderr)
                self.assertFalse((self.root / "exploited").exists())
                uat.write_text(original, encoding="utf-8")

    # -- Accepted constructs -------------------------------------------------

    def test_blank_lines_and_comments_are_ignored(self):
        uat = self.env_path("uat")
        original = uat.read_text(encoding="utf-8")
        decorated = "\n# a leading comment\n\n" + original + "\n# a trailing comment\n\n"
        uat.write_text(decorated, encoding="utf-8")

        result = self.load("uat")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "uat|672172129937|ap-east-1|uat-build\n")
        self.assertFalse(self.command_log.exists())

    def test_trims_unquoted_value_whitespace(self):
        uat = self.env_path("uat")
        original = uat.read_text(encoding="utf-8")
        uat.write_text(
            original.replace(
                "TF_STATE_BUCKET=sml-oms-uat-tfstate-672172129937",
                "   TF_STATE_BUCKET=  sml-oms-uat-tfstate-672172129937  ",
            ),
            encoding="utf-8",
        )

        result = self.load("uat")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.command_log.exists())

    # -- Rejected dotenv constructs -------------------------------------------

    def test_duplicate_key_is_rejected(self):
        uat = self.env_path("uat")
        original = uat.read_text(encoding="utf-8")
        uat.write_text(original + "AWS_REGION=ap-east-1\n", encoding="utf-8")

        result = self.load("uat")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("duplicate dotenv key", result.stderr)
        self.assertFalse(self.command_log.exists())

    def test_unknown_key_is_rejected(self):
        uat = self.env_path("uat")
        original = uat.read_text(encoding="utf-8")
        uat.write_text(original + "UNEXPECTED_KEY=some-value\n", encoding="utf-8")

        result = self.load("uat")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unknown dotenv key", result.stderr)
        self.assertFalse(self.command_log.exists())

    def test_missing_required_key_is_rejected(self):
        uat = self.env_path("uat")
        original = uat.read_text(encoding="utf-8")
        lines = [
            line for line in original.splitlines()
            if not line.startswith("PROMOTION_MODE=")
        ]
        uat.write_text("\n".join(lines) + "\n", encoding="utf-8")

        result = self.load("uat")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("missing required key: PROMOTION_MODE", result.stderr)
        self.assertFalse(self.command_log.exists())

    def test_malformed_key_name_is_rejected(self):
        uat = self.env_path("uat")
        original = uat.read_text(encoding="utf-8")
        uat.write_text(
            original.replace("AWS_REGION=ap-east-1", "aws_region=ap-east-1"),
            encoding="utf-8",
        )

        result = self.load("uat")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("invalid dotenv assignment", result.stderr)
        self.assertFalse(self.command_log.exists())

    def test_unresolved_placeholder_value_is_rejected(self):
        uat = self.env_path("uat")
        original = uat.read_text(encoding="utf-8")
        uat.write_text(
            original.replace(
                "TF_STATE_BUCKET=sml-oms-uat-tfstate-672172129937",
                "TF_STATE_BUCKET=<example>",
            ),
            encoding="utf-8",
        )

        result = self.load("uat")

        self.assertNotEqual(result.returncode, 0)
        # "<" and ">" are excluded from the value character class by the
        # dotenv assignment regex itself, so an unresolved placeholder like
        # <example> is rejected there as a malformed assignment; there is no
        # separate reachable "unresolved value" classification to assert on.
        self.assertIn("invalid dotenv assignment", result.stderr)
        self.assertFalse(self.command_log.exists())

    def test_multiline_value_attempt_is_rejected(self):
        uat = self.env_path("uat")
        original = uat.read_text(encoding="utf-8")
        uat.write_text(
            original.replace(
                "AWS_REGION=ap-east-1",
                "AWS_REGION=ap-east-1\\\nus-west-2",
            ),
            encoding="utf-8",
        )

        result = self.load("uat")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("invalid dotenv assignment", result.stderr)
        self.assertFalse(self.command_log.exists())

    def test_symlink_environment_file_is_rejected(self):
        uat = self.env_path("uat")
        dev = self.env_path("dev")
        uat.unlink()
        uat.symlink_to(dev)

        result = self.load("uat")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("must not be a symlink", result.stderr)
        self.assertFalse(self.command_log.exists())

    def test_non_regular_environment_file_is_rejected(self):
        uat = self.env_path("uat")
        uat.unlink()
        os.mkfifo(uat)

        result = self.load("uat")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("must be a regular file", result.stderr)
        self.assertFalse(self.command_log.exists())

    def test_group_writable_environment_file_is_rejected(self):
        uat = self.env_path("uat")
        uat.chmod(uat.stat().st_mode | stat.S_IWGRP)

        result = self.load("uat")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("group-writable", result.stderr)
        self.assertFalse(self.command_log.exists())

    def test_world_writable_environment_file_is_rejected(self):
        uat = self.env_path("uat")
        uat.chmod(uat.stat().st_mode | stat.S_IWOTH)

        result = self.load("uat")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("world-writable", result.stderr)
        self.assertFalse(self.command_log.exists())

    def test_environment_field_mismatch_is_rejected(self):
        uat = self.env_path("uat")
        original = uat.read_text(encoding="utf-8")
        uat.write_text(
            original.replace("ENVIRONMENT=uat", "ENVIRONMENT=dev"),
            encoding="utf-8",
        )

        result = self.load("uat")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("but uat was requested", result.stderr)
        self.assertFalse(self.command_log.exists())

    def test_wrong_immutable_values_are_rejected(self):
        uat = self.env_path("uat")
        original = uat.read_text(encoding="utf-8")
        cases = {
            "account": ("EXPECTED_AWS_ACCOUNT_ID=672172129937", "EXPECTED_AWS_ACCOUNT_ID=111111111111", "EXPECTED_AWS_ACCOUNT_ID"),
            "region": ("AWS_REGION=ap-east-1", "AWS_REGION=us-west-2", "AWS_REGION"),
            "state region": ("TF_STATE_REGION=ap-east-1", "TF_STATE_REGION=us-west-2", "TF_STATE_REGION"),
            "state prefix": ("TF_STATE_PREFIX=oms/uat", "TF_STATE_PREFIX=oms/other", "TF_STATE_PREFIX"),
            "promotion mode": ("PROMOTION_MODE=uat-build", "PROMOTION_MODE=modeled", "PROMOTION_MODE"),
        }
        for label, (needle, replacement, key_name) in cases.items():
            with self.subTest(label=label):
                uat.write_text(original.replace(needle, replacement), encoding="utf-8")
                result = self.load("uat")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(f"config {key_name} for uat is", result.stderr)
                self.assertIn("expected", result.stderr)
                self.assertFalse(self.command_log.exists())
                uat.write_text(original, encoding="utf-8")

    def test_unknown_requested_environment_is_rejected(self):
        result = self.load("production")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("accepts only dev or uat", result.stderr)
        self.assertFalse(self.command_log.exists())


class EnvironmentSchemaFragmentTests(RepositoryFixture):
    def setUp(self):
        super().setUp()
        self.copy(
            "scripts/lib/platform-env.sh",
            "scripts/lib/environment-contracts.sh",
            "config/environment-schema/base.manifest",
            "config/environments/dev.env",
            "config/environments/uat.env",
        )
        self.fragments_dir = self.root / "config" / "environment-schema" / "fragments"
        self.fragments_dir.mkdir(parents=True, exist_ok=True)
        self.uat_env = self.root / "config" / "environments" / "uat.env"

    def load(self, environment, variable_names=("EXTRA_FRAGMENT_KEY",)):
        printf_format = "|".join(["%s"] * len(variable_names))
        variable_refs = " ".join(f'"${name}"' for name in variable_names)
        return self.run_bash(
            'source scripts/lib/platform-env.sh && '
            f'load_platform_env {environment} && '
            f"printf '{printf_format}\\n' {variable_refs}"
        )

    def write_fragment(self, name, content):
        (self.fragments_dir / name).write_text(content, encoding="utf-8")

    def test_fragment_adds_key_without_editing_platform_env(self):
        before = (self.root / "scripts/lib/platform-env.sh").read_text(encoding="utf-8")
        self.write_fragment(
            "10-example.manifest",
            "EXTRA_FRAGMENT_KEY|required|nonempty|-\n",
        )
        with self.uat_env.open("a", encoding="utf-8") as handle:
            handle.write("EXTRA_FRAGMENT_KEY=example-value\n")

        result = self.load("uat")
        after = (self.root / "scripts/lib/platform-env.sh").read_text(encoding="utf-8")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "example-value\n")
        self.assertEqual(before, after)
        self.assertFalse(self.command_log.exists())

    def test_fragment_composition_order_is_deterministic(self):
        self.write_fragment("05-second.manifest", "FRAGMENT_KEY_B|required|nonempty|-\n")
        self.write_fragment("01-first.manifest", "FRAGMENT_KEY_A|required|nonempty|-\n")
        with self.uat_env.open("a", encoding="utf-8") as handle:
            handle.write("FRAGMENT_KEY_A=value-a\n")
            handle.write("FRAGMENT_KEY_B=value-b\n")

        variable_names = ("FRAGMENT_KEY_A", "FRAGMENT_KEY_B")
        results = [self.load("uat", variable_names=variable_names) for _ in range(5)]

        for result in results:
            self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(results[0].stdout, "value-a|value-b\n")
        self.assertEqual(len({result.stdout for result in results}), 1)

    def test_duplicate_key_across_fragments_is_rejected(self):
        self.write_fragment("01-first.manifest", "SHARED_FRAGMENT_KEY|required|nonempty|-\n")
        self.write_fragment("02-second.manifest", "SHARED_FRAGMENT_KEY|required|nonempty|-\n")
        with self.uat_env.open("a", encoding="utf-8") as handle:
            handle.write("SHARED_FRAGMENT_KEY=value\n")

        result = self.load("uat")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("duplicate manifest key declaration", result.stderr)
        self.assertFalse(self.command_log.exists())

    def test_unknown_validator_name_in_fragment_is_rejected(self):
        self.write_fragment(
            "10-example.manifest",
            "EXTRA_FRAGMENT_KEY|required|not-a-real-validator|-\n",
        )
        with self.uat_env.open("a", encoding="utf-8") as handle:
            handle.write("EXTRA_FRAGMENT_KEY=example-value\n")

        result = self.load("uat")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unknown validator", result.stderr)
        self.assertFalse(self.command_log.exists())

    def test_omitted_fragment_required_key_is_rejected(self):
        self.write_fragment(
            "10-example.manifest",
            "EXTRA_FRAGMENT_KEY|required|nonempty|-\n",
        )
        # Deliberately do not add EXTRA_FRAGMENT_KEY to uat.env.

        result = self.load("uat")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("missing required key: EXTRA_FRAGMENT_KEY", result.stderr)
        self.assertFalse(self.command_log.exists())


if __name__ == "__main__":
    unittest.main()
