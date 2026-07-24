import re
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
BASE_ROOT = REPO_ROOT / "gitops" / "platform-controllers" / "base"
OVERLAYS_ROOT = REPO_ROOT / "gitops" / "platform-controllers" / "overlays"
ENV_ROOT = REPO_ROOT / "platform-prerequisites" / "terraform" / "environments"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


class ControllerRenderTests(unittest.TestCase):
    def test_base_kustomization_resources_are_scoped(self):
        text = read(BASE_ROOT / "kustomization.yaml")
        self.assertIn("- namespaces.yaml", text)
        self.assertIn("- sources.yaml", text)
        self.assertIn("- releases.yaml", text)
        self.assertIn("platform.oms/scope: platform-controllers", text)

    def test_required_controller_releases_exist(self):
        text = read(BASE_ROOT / "releases.yaml")
        required = [
            "name: cert-manager",
            "name: kyverno",
            "name: cluster-autoscaler",
            "name: metrics-server",
            "name: aws-load-balancer-controller",
        ]
        for marker in required:
            with self.subTest(marker=marker):
                self.assertIn(marker, text)

        self.assertNotIn("PerconaServerMongoDB", text)
        self.assertNotIn("Deployment", text)
        self.assertNotIn("Service\n", text)

    def test_sources_use_explicit_pinned_tags(self):
        text = read(BASE_ROOT / "sources.yaml")

        self.assertEqual(text.count("kind: OCIRepository"), 5)
        self.assertRegex(text, r"name:\s*cert-manager[\s\S]*?tag:\s*v1\.17\.2")
        self.assertRegex(text, r"name:\s*kyverno[\s\S]*?tag:\s*v3\.3\.7")
        self.assertRegex(text, r"name:\s*cluster-autoscaler[\s\S]*?tag:\s*9\.46\.6")
        self.assertRegex(text, r"name:\s*metrics-server[\s\S]*?tag:\s*3\.12\.2")
        self.assertRegex(text, r"name:\s*aws-load-balancer-controller[\s\S]*?tag:\s*1\.13\.0")

        self.assertNotRegex(text, r"tag:\s*latest")
        self.assertNotRegex(text, r"tag:\s*main")
        self.assertNotRegex(text, r"tag:\s*master")

    def test_releases_have_bounded_timeout_and_remediation(self):
        text = read(BASE_ROOT / "releases.yaml")
        self.assertGreaterEqual(text.count("timeout: 10m"), 5)
        self.assertGreaterEqual(text.count("retries: 3"), 10)
        self.assertIn("crds: CreateReplace", text)

    def test_overlays_set_environment_and_private_static_labels(self):
        dev_k = read(OVERLAYS_ROOT / "dev" / "kustomization.yaml")
        uat_k = read(OVERLAYS_ROOT / "uat" / "kustomization.yaml")
        dev_settings = read(OVERLAYS_ROOT / "dev" / "platform-settings.yaml")
        uat_settings = read(OVERLAYS_ROOT / "uat" / "platform-settings.yaml")

        self.assertIn("platform.oms/environment: dev", dev_k)
        self.assertIn("platform.oms/environment: uat", uat_k)
        self.assertIn("platform.oms/visibility: private", dev_k)
        self.assertIn("platform.oms/visibility: private", uat_k)

        self.assertIn("RENDER_VISIBILITY: private", dev_settings)
        self.assertIn("RENDER_STRATEGY: static", dev_settings)
        self.assertIn("RENDER_VISIBILITY: private", uat_settings)
        self.assertIn("RENDER_STRATEGY: static", uat_settings)

    def test_uat_binds_to_expected_cluster_identity(self):
        uat_settings = read(OVERLAYS_ROOT / "uat" / "platform-settings.yaml")
        self.assertIn("ENVIRONMENT: uat", uat_settings)
        self.assertIn('ACCOUNT_ID: "672172129937"', uat_settings)
        self.assertIn("CLUSTER_NAME: oms-uat-eks-cluster", uat_settings)
        self.assertIn(
            "CLUSTER_ARN: arn:aws:eks:ap-east-1:672172129937:cluster/oms-uat-eks-cluster",
            uat_settings,
        )

    def test_cluster_autoscaler_service_account_identity_wiring(self):
        releases = read(BASE_ROOT / "releases.yaml")
        dev_overlay = read(OVERLAYS_ROOT / "dev" / "kustomization.yaml")
        uat_overlay = read(OVERLAYS_ROOT / "uat" / "kustomization.yaml")

        self.assertIn("name: REPLACE_AUTOSCALER_SERVICE_ACCOUNT", releases)
        self.assertIn("eks.amazonaws.com/role-arn: REPLACE_CLUSTER_AUTOSCALER_ROLE_ARN", releases)
        self.assertIn("data.AUTOSCALER_SERVICE_ACCOUNT", dev_overlay)
        self.assertIn("data.AUTOSCALER_SERVICE_ACCOUNT", uat_overlay)
        self.assertIn("data.CLUSTER_AUTOSCALER_ROLE_ARN", dev_overlay)
        self.assertIn("data.CLUSTER_AUTOSCALER_ROLE_ARN", uat_overlay)

    def test_optional_controllers_are_settings_conditional(self):
        dev_settings = read(OVERLAYS_ROOT / "dev" / "platform-settings.yaml")
        uat_settings = read(OVERLAYS_ROOT / "uat" / "platform-settings.yaml")
        dev_overlay = read(OVERLAYS_ROOT / "dev" / "kustomization.yaml")
        uat_overlay = read(OVERLAYS_ROOT / "uat" / "kustomization.yaml")

        self.assertIn('SUSPEND_METRICS_SERVER: "true"', dev_settings)
        self.assertIn('SUSPEND_AWS_LOAD_BALANCER_CONTROLLER: "true"', dev_settings)
        self.assertIn('SUSPEND_METRICS_SERVER: "false"', uat_settings)
        self.assertIn('SUSPEND_AWS_LOAD_BALANCER_CONTROLLER: "false"', uat_settings)

        self.assertGreaterEqual(dev_overlay.count("spec.suspend"), 2)
        self.assertGreaterEqual(uat_overlay.count("spec.suspend"), 2)

    def test_metrics_server_has_single_ownership_path(self):
        releases = read(BASE_ROOT / "releases.yaml")
        dev_tfvars = read(ENV_ROOT / "dev" / "eks-platform.tfvars")
        uat_tfvars = read(ENV_ROOT / "uat" / "eks-platform.tfvars")

        self.assertIn("name: metrics-server", releases)
        self.assertNotIn("metrics-server", dev_tfvars)
        self.assertNotIn("metrics-server", uat_tfvars)

    def test_no_managed_addon_or_app_scope_resources(self):
        corpus = "\n".join(
            [
                read(BASE_ROOT / "kustomization.yaml"),
                read(BASE_ROOT / "namespaces.yaml"),
                read(BASE_ROOT / "sources.yaml"),
                read(BASE_ROOT / "releases.yaml"),
                read(OVERLAYS_ROOT / "dev" / "kustomization.yaml"),
                read(OVERLAYS_ROOT / "dev" / "platform-settings.yaml"),
                read(OVERLAYS_ROOT / "uat" / "kustomization.yaml"),
                read(OVERLAYS_ROOT / "uat" / "platform-settings.yaml"),
            ]
        )

        forbidden_tokens = [
            "aws_eks_addon",
            "PerconaServerMongoDB",
            "psmdb",
            "MongoDB",
            "apps/v1",
            "StatefulSet",
        ]
        for token in forbidden_tokens:
            with self.subTest(token=token):
                self.assertNotIn(token, corpus)


if __name__ == "__main__":
    unittest.main()
