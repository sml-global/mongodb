"""Structural test suite for k8s/dr-drill/rbac.yaml.

Parses the real multi-document YAML with PyYAML and asserts on structured
fields rather than searching the file text. Per writing-good-tests.md
(v6.2.0): string-presence assertions counterfeit falsifiability.

Context: each drill script now targets one of 3 FIXED, reusable namespaces
(dr-drill-mongodb-restore-target, dr-drill-postgresql-restore-target,
dr-drill-clickhouse-restore-target) instead of a dynamically timestamped
one, and deletes+recreates that namespace on every run. This file's RBAC
design (see header comments in rbac.yaml) narrows the actual workload
permission grant from cluster-wide to namespace-scoped, via a persistent
ClusterRole (dr-drill-workload-operator) that each script binds to its own
namespace at runtime with a self-applied RoleBinding -- which requires a
narrowly-scoped `bind`-verb ClusterRole (dr-drill-workload-operator-binder),
per the Kubernetes RBAC role-binding-creation restrictions.
"""
import unittest
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parents[2]
RBAC_FILE = REPO_ROOT / "k8s" / "dr-drill" / "rbac.yaml"

RUNNER_SERVICE_ACCOUNTS = [
    "dr-drill-mongodb-runner",
    "dr-drill-postgresql-runner",
    "dr-drill-clickhouse-runner",
]


class DrDrillRbacStructureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.docs = [d for d in yaml.safe_load_all(RBAC_FILE.read_text()) if d]
        cls.by_key = {(d["kind"], d["metadata"]["name"]): d for d in cls.docs}

    def test_exactly_five_objects_defined(self):
        self.assertEqual(len(self.docs), 5)

    def test_namespace_manager_cluster_role_and_binding_exist(self):
        role = self.by_key[("ClusterRole", "dr-drill-namespace-manager")]
        self.assertEqual(
            role["rules"],
            [{"apiGroups": [""], "resources": ["namespaces"],
              "verbs": ["create", "delete", "get"]}],
        )
        binding = self.by_key[("ClusterRoleBinding", "dr-drill-namespace-manager")]
        self.assertEqual(binding["roleRef"]["name"], "dr-drill-namespace-manager")
        subject_names = {s["name"] for s in binding["subjects"]}
        self.assertEqual(subject_names, set(RUNNER_SERVICE_ACCOUNTS))
        for subject in binding["subjects"]:
            self.assertEqual(subject["namespace"], "dr-drill-uat")

    def test_workload_operator_cluster_role_exists_with_expected_rules(self):
        role = self.by_key[("ClusterRole", "dr-drill-workload-operator")]
        rule_resources = {tuple(r["resources"]) for r in role["rules"]}
        self.assertIn(("pods",), rule_resources)
        self.assertIn(("pods/exec",), rule_resources)
        self.assertIn(("deployments",), rule_resources)
        self.assertIn(("clusters",), rule_resources)

    def test_workload_operator_has_no_direct_cluster_role_binding(self):
        # Regression guard: this ClusterRole must be bound per-namespace via
        # a RoleBinding each script self-applies at runtime (see
        # scripts/dr-drill-mongodb-restore.sh etc.), NOT via a cluster-wide
        # ClusterRoleBinding -- a cluster-wide binding would defeat the whole
        # point of scoping workload permissions down to the 3 fixed
        # restore-target namespaces.
        self.assertNotIn(("ClusterRoleBinding", "dr-drill-workload-operator"),
                          self.by_key)

    def test_workload_operator_binder_scoped_to_bind_verb_on_named_role_only(self):
        role = self.by_key[("ClusterRole", "dr-drill-workload-operator-binder")]
        bind_rules = [r for r in role["rules"] if "bind" in r.get("verbs", [])]
        self.assertEqual(len(bind_rules), 1,
                          "must grant `bind` on exactly one rule")
        self.assertEqual(bind_rules[0]["resources"], ["clusterroles"])
        self.assertEqual(bind_rules[0]["resourceNames"],
                          ["dr-drill-workload-operator"],
                          "bind must be restricted to the one approved "
                          "ClusterRole (privilege-escalation guard)")

    def test_workload_operator_binder_can_create_rolebindings(self):
        role = self.by_key[("ClusterRole", "dr-drill-workload-operator-binder")]
        rolebinding_rules = [
            r for r in role["rules"] if r.get("resources") == ["rolebindings"]
        ]
        self.assertEqual(len(rolebinding_rules), 1)
        self.assertEqual(set(rolebinding_rules[0]["verbs"]), {"get", "create"})

    def test_workload_operator_binder_binding_covers_all_three_runners(self):
        binding = self.by_key[("ClusterRoleBinding",
                                "dr-drill-workload-operator-binder")]
        self.assertEqual(binding["roleRef"]["name"],
                          "dr-drill-workload-operator-binder")
        subject_names = {s["name"] for s in binding["subjects"]}
        self.assertEqual(subject_names, set(RUNNER_SERVICE_ACCOUNTS))
        for subject in binding["subjects"]:
            self.assertEqual(subject["namespace"], "dr-drill-uat")

    def test_no_service_account_objects_defined_here(self):
        # ServiceAccounts are owned by
        # scripts/bootstrap-dr-drill-role-arns-configmap.sh, not this file.
        kinds = {d["kind"] for d in self.docs}
        self.assertNotIn("ServiceAccount", kinds)

    def test_no_namespace_scoped_role_or_rolebinding_defined_statically(self):
        # The per-namespace RoleBinding referencing dr-drill-workload-operator
        # is fully owned/self-applied by each drill script every run (since
        # the namespace itself is deleted+recreated every run) -- it is
        # deliberately NOT statically defined here, to avoid confusion about
        # which copy is authoritative.
        kinds = {d["kind"] for d in self.docs}
        self.assertNotIn("Role", kinds)
        self.assertNotIn("RoleBinding", kinds)


if __name__ == "__main__":
    unittest.main()
