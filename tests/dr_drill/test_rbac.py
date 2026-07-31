"""Structural test suite for k8s/dr-drill/rbac.yaml.

Parses the real multi-document YAML with PyYAML and asserts on structured
fields rather than searching the file text. Per writing-good-tests.md
(v6.2.0): string-presence assertions counterfeit falsifiability.

Context: each drill script targets one of 3 FIXED, reusable namespaces
(dr-drill-mongodb-restore-target, dr-drill-postgresql-restore-target,
dr-drill-clickhouse-restore-target), provisioned ONCE (namespace,
ServiceAccount, RBAC) by scripts/bootstrap-dr-drill-role-arns-configmap.sh
and never deleted -- only the workload object inside each one (a
Deployment, or the CNPG Cluster for postgresql) is cycled per run (see D19).
This file's RBAC grants a persistent ClusterRole
(dr-drill-workload-operator) to each orchestrator ServiceAccount, scoped via
a namespace-scoped RoleBinding to just its own fixed restore-target
namespace -- both defined statically here and applied once by the bootstrap
script, never self-applied by a runner ServiceAccount at runtime.
"""
import unittest
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parents[2]
RBAC_FILE = REPO_ROOT / "k8s" / "dr-drill" / "rbac.yaml"

EXPECTED_ROLE_BINDINGS = {
    "dr-drill-mongodb-restore-target": "dr-drill-mongodb-runner",
    "dr-drill-postgresql-restore-target": "dr-drill-postgresql-runner",
    "dr-drill-clickhouse-restore-target": "dr-drill-clickhouse-runner",
}


class DrDrillRbacStructureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.docs = [d for d in yaml.safe_load_all(RBAC_FILE.read_text()) if d]

    def test_exactly_four_objects_defined(self):
        # 1 ClusterRole + 3 namespace-scoped RoleBindings (one per fixed
        # restore-target namespace). No ClusterRoleBinding, no Role/
        # RoleBinding granting namespace or rolebinding/bind permissions.
        self.assertEqual(len(self.docs), 4)

    def test_no_cluster_scoped_namespace_management_permissions_exist(self):
        # Regression guard for a Critical bug caught in review: a prior
        # revision granted namespace create/delete/get CLUSTER-WIDE via a
        # dr-drill-namespace-manager ClusterRole/ClusterRoleBinding. Fixed
        # (D19): namespaces are provisioned once by the bootstrap script,
        # never by the runner ServiceAccounts, so no such grant should exist
        # anywhere in this file at all.
        for doc in self.docs:
            self.assertNotEqual(doc["metadata"]["name"], "dr-drill-namespace-manager")
            for rule in doc.get("rules", []):
                self.assertNotIn("namespaces", rule.get("resources", []))

    def test_no_rolebinding_or_clusterrole_bind_escalation_permissions_exist(self):
        # Regression guard for a Critical bug caught in review: a prior
        # revision granted `rolebindings:create` + `clusterroles:bind`
        # CLUSTER-WIDE (only resourceNames-restricted on the ClusterRole
        # being bound, not on the target namespace) via a
        # dr-drill-workload-operator-binder ClusterRole/ClusterRoleBinding --
        # letting any runner ServiceAccount self-grant workload-operator
        # permissions in ANY namespace. Fixed (D19): the 3 RoleBindings below
        # are static and applied once by the bootstrap script, so no runner
        # ServiceAccount needs -- or is granted -- rolebindings:create or
        # clusterroles:bind anywhere in this file.
        for doc in self.docs:
            self.assertNotEqual(doc["metadata"]["name"], "dr-drill-workload-operator-binder")
            for rule in doc.get("rules", []):
                self.assertNotIn("rolebindings", rule.get("resources", []))
                self.assertNotIn("bind", rule.get("verbs", []))

    def test_no_cluster_role_binding_objects_exist(self):
        # No ClusterRole in this file should ever be bound cluster-wide.
        kinds = {d["kind"] for d in self.docs}
        self.assertNotIn("ClusterRoleBinding", kinds)

    def test_workload_operator_cluster_role_exists_with_expected_rules(self):
        roles = [d for d in self.docs if d["kind"] == "ClusterRole"]
        self.assertEqual(len(roles), 1)
        role = roles[0]
        self.assertEqual(role["metadata"]["name"], "dr-drill-workload-operator")
        rule_resources = {tuple(r["resources"]) for r in role["rules"]}
        self.assertIn(("pods",), rule_resources)
        self.assertIn(("pods/exec",), rule_resources)
        self.assertIn(("deployments",), rule_resources)
        self.assertIn(("clusters",), rule_resources)

    def test_exactly_three_namespace_scoped_role_bindings_exist(self):
        bindings = [d for d in self.docs if d["kind"] == "RoleBinding"]
        self.assertEqual(len(bindings), 3)
        namespaces = {b["metadata"]["namespace"] for b in bindings}
        self.assertEqual(namespaces, set(EXPECTED_ROLE_BINDINGS))

    def test_each_role_binding_scopes_workload_operator_to_its_own_namespace_only(self):
        bindings = {d["metadata"]["namespace"]: d for d in self.docs if d["kind"] == "RoleBinding"}
        for namespace, expected_sa in EXPECTED_ROLE_BINDINGS.items():
            binding = bindings[namespace]
            self.assertEqual(binding["roleRef"]["kind"], "ClusterRole")
            self.assertEqual(binding["roleRef"]["name"], "dr-drill-workload-operator")
            subjects = binding["subjects"]
            self.assertEqual(len(subjects), 1,
                              f"RoleBinding in {namespace} must grant exactly "
                              "one ServiceAccount (its own drill's orchestrator)")
            self.assertEqual(subjects[0]["name"], expected_sa)
            self.assertEqual(subjects[0]["namespace"], "dr-drill-uat")

    def test_no_service_account_objects_defined_here(self):
        # ServiceAccounts are owned by
        # scripts/bootstrap-dr-drill-role-arns-configmap.sh, not this file.
        kinds = {d["kind"] for d in self.docs}
        self.assertNotIn("ServiceAccount", kinds)

    def test_no_namespace_objects_defined_here(self):
        # Namespaces are owned by
        # scripts/bootstrap-dr-drill-role-arns-configmap.sh, not this file.
        kinds = {d["kind"] for d in self.docs}
        self.assertNotIn("Namespace", kinds)


if __name__ == "__main__":
    unittest.main()

