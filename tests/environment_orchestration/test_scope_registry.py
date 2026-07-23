import unittest

from .helpers import RepositoryFixture

# Exact catalog/dependency/order constants from
# docs/superpowers/plans/2026-07-22-phase2-environment-orchestration-foundation.md,
# Task 3 Step 1 (verbatim).

EXPECTED_SCOPES = (
    "backend",
    "eks-platform",
    "access-governance",
    "eks-access",
    "platform-controllers",
    "boomi-runtime",
    "mongodb",
    "postgresql-core",
    "postgresql-brand",
    "mongodb-access",
    "database-access-core",
    "database-access-brand",
    "workload-identity",
    "signoz",
    "signoz-observability",
    "all",
)

EXPECTED_DEPENDENCIES = {
    "backend": (),
    "access-governance": ("backend",),
    "eks-platform": ("backend",),
    "eks-access": ("eks-platform",),
    "platform-controllers": ("eks-platform",),
    "workload-identity": ("eks-platform",),
    "boomi-runtime": ("eks-platform", "platform-controllers", "workload-identity"),
    "mongodb": ("eks-platform", "platform-controllers"),
    "postgresql-core": ("eks-platform",),
    "postgresql-brand": ("eks-platform",),
    "mongodb-access": ("mongodb",),
    "database-access-core": ("postgresql-core",),
    "database-access-brand": ("postgresql-brand",),
    "signoz": ("eks-platform", "platform-controllers"),
    "signoz-observability": ("signoz",),
}

EXPECTED_ALL_ORDER = (
    "backend", "access-governance", "eks-platform", "eks-access",
    "workload-identity", "platform-controllers", "boomi-runtime", "mongodb",
    "postgresql-core", "postgresql-brand", "mongodb-access",
    "database-access-core", "database-access-brand", "signoz",
    "signoz-observability",
)

EXPECTED_DESTROY_ALL_ORDER = (
    "signoz-observability", "signoz", "boomi-runtime", "mongodb-access",
    "database-access-brand", "database-access-core", "mongodb",
    "postgresql-brand", "postgresql-core", "workload-identity",
    "platform-controllers", "eks-access", "eks-platform",
)

# Deferred work-package mapping, exactly as specified in Task 3 Step 3.
EXPECTED_WORK_PACKAGE_FOR_SCOPE = {
    "eks-platform": 3,
    "platform-controllers": 3,
    "workload-identity": 3,
    "mongodb": 4,
    "postgresql-core": 4,
    "postgresql-brand": 4,
    "mongodb-access": 4,
    "database-access-core": 4,
    "database-access-brand": 4,
    "signoz": 4,
    "signoz-observability": 4,
    "boomi-runtime": 5,
}

# Scopes whose real implementation is pending only this plan's own Task 5
# foundation access fragment (not an external work package). Provision
# handler mapping only -- eks-access's destroy handler is separately
# deferred to work package 3 (see EXPECTED_DESTROY_HANDLER below).
FRAGMENT_PENDING_SCOPES = ("backend", "access-governance", "eks-access")

EXPECTED_PROVISION_HANDLER = {
    "backend": "foundation_provision_backend",
    "access-governance": "foundation_provision_access_governance",
    "eks-access": "foundation_provision_eks_access",
    "eks-platform": "scope_registry_deferred_eks_platform_provision",
    "platform-controllers": "scope_registry_deferred_platform_controllers_provision",
    "workload-identity": "scope_registry_deferred_workload_identity_provision",
    "boomi-runtime": "scope_registry_deferred_boomi_runtime_provision",
    "mongodb": "scope_registry_deferred_mongodb_provision",
    "postgresql-core": "scope_registry_deferred_postgresql_core_provision",
    "postgresql-brand": "scope_registry_deferred_postgresql_brand_provision",
    "mongodb-access": "scope_registry_deferred_mongodb_access_provision",
    "database-access-core": "scope_registry_deferred_database_access_core_provision",
    "database-access-brand": "scope_registry_deferred_database_access_brand_provision",
    "signoz": "scope_registry_deferred_signoz_provision",
    "signoz-observability": "scope_registry_deferred_signoz_observability_provision",
}

EXPECTED_DESTROY_HANDLER = {
    "backend": "foundation_destroy_backend_blocked",
    "access-governance": "foundation_destroy_access_governance_blocked",
    "eks-access": "scope_registry_deferred_eks_access_destroy",
    "eks-platform": "scope_registry_deferred_eks_platform_destroy",
    "platform-controllers": "scope_registry_deferred_platform_controllers_destroy",
    "workload-identity": "scope_registry_deferred_workload_identity_destroy",
    "boomi-runtime": "scope_registry_deferred_boomi_runtime_destroy",
    "mongodb": "scope_registry_deferred_mongodb_destroy",
    "postgresql-core": "scope_registry_deferred_postgresql_core_destroy",
    "postgresql-brand": "scope_registry_deferred_postgresql_brand_destroy",
    "mongodb-access": "scope_registry_deferred_mongodb_access_destroy",
    "database-access-core": "scope_registry_deferred_database_access_core_destroy",
    "database-access-brand": "scope_registry_deferred_database_access_brand_destroy",
    "signoz": "scope_registry_deferred_signoz_destroy",
    "signoz-observability": "scope_registry_deferred_signoz_observability_destroy",
}

# Exactly the EXPECTED_DESTROY_ALL_ORDER scopes have a pre-destroy guard.
EXPECTED_GUARD = {
    "eks-platform": "scope_registry_pre_destroy_guard_eks_platform",
    "eks-access": "scope_registry_pre_destroy_guard_eks_access",
    "platform-controllers": "scope_registry_pre_destroy_guard_platform_controllers",
    "workload-identity": "scope_registry_pre_destroy_guard_workload_identity",
    "boomi-runtime": "scope_registry_pre_destroy_guard_boomi_runtime",
    "mongodb": "scope_registry_pre_destroy_guard_mongodb",
    "postgresql-core": "scope_registry_pre_destroy_guard_postgresql_core",
    "postgresql-brand": "scope_registry_pre_destroy_guard_postgresql_brand",
    "mongodb-access": "scope_registry_pre_destroy_guard_mongodb_access",
    "database-access-core": "scope_registry_pre_destroy_guard_database_access_core",
    "database-access-brand": "scope_registry_pre_destroy_guard_database_access_brand",
    "signoz": "scope_registry_pre_destroy_guard_signoz",
    "signoz-observability": "scope_registry_pre_destroy_guard_signoz_observability",
}

EXPECTED_STATE_KEY_VARIABLE = {
    "backend": "BACKEND_STATE_KEY",
    "access-governance": "ACCESS_GOVERNANCE_STATE_KEY",
    "eks-platform": "EKS_PLATFORM_STATE_KEY",
    "eks-access": "EKS_ACCESS_STATE_KEY",
    "platform-controllers": "PLATFORM_CONTROLLERS_STATE_KEY",
    "workload-identity": "WORKLOAD_IDENTITY_STATE_KEY",
    "boomi-runtime": "BOOMI_RUNTIME_STATE_KEY",
    "mongodb": "MONGODB_STATE_KEY",
    "postgresql-core": "POSTGRESQL_CORE_STATE_KEY",
    "postgresql-brand": "POSTGRESQL_BRAND_STATE_KEY",
    "mongodb-access": "MONGODB_ACCESS_STATE_KEY",
    "database-access-core": "DATABASE_ACCESS_CORE_STATE_KEY",
    "database-access-brand": "DATABASE_ACCESS_BRAND_STATE_KEY",
    "signoz": "SIGNOZ_STATE_KEY",
    "signoz-observability": "SIGNOZ_OBSERVABILITY_STATE_KEY",
}

PREFLIGHT_SLOTS = (
    "foundation-contract", "aws-identity-region", "kubernetes-context",
    "eks-authentication-mode",
)
SMOKE_ONLY_SLOTS = ("mongodb-audit-write-smoke", "signoz-otlp-roundtrip-smoke")

UNKNOWN_SCOPES = ("bogus-scope", "not-a-real-scope", "", "MongoDB", "mongo")


class ScopeRegistryFixture(RepositoryFixture):
    def setUp(self):
        super().setUp()
        self.copy("scripts/lib/scope-registry.sh")

    def run_registry(self, script):
        return self.run_bash("source scripts/lib/scope-registry.sh && " + script)

    def lines(self, text):
        return [line for line in text.splitlines() if line != ""]


class CatalogTests(ScopeRegistryFixture):
    """Step 1: exact provision catalog."""

    def test_list_provision_scopes_is_exact(self):
        result = self.run_registry("list_provision_scopes")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(tuple(self.lines(result.stdout)), EXPECTED_SCOPES)


class DependencyGraphTests(ScopeRegistryFixture):
    """Step 1: exact dependency graph."""

    def test_dependencies_for_scope_matches_exactly(self):
        for scope, deps in EXPECTED_DEPENDENCIES.items():
            with self.subTest(scope=scope):
                result = self.run_registry(f"dependencies_for_scope {scope}")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(tuple(result.stdout.split()), deps)

    def test_all_is_not_a_dependency_graph_entry(self):
        result = self.run_registry("dependencies_for_scope all")
        self.assertNotEqual(result.returncode, 0)

    def test_verification_is_not_a_dependency_graph_entry(self):
        result = self.run_registry("dependencies_for_scope verification")
        self.assertNotEqual(result.returncode, 0)

    def test_unknown_scopes_are_rejected(self):
        for scope in UNKNOWN_SCOPES:
            with self.subTest(scope=scope):
                result = self.run_registry(f"dependencies_for_scope '{scope}'")
                self.assertNotEqual(result.returncode, 0)


class OrderResolutionTests(ScopeRegistryFixture):
    """Step 1: exact immutable full provision/destroy orders."""

    def test_resolve_provision_order_all_is_exact(self):
        result = self.run_registry("resolve_provision_order all")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(tuple(self.lines(result.stdout)), EXPECTED_ALL_ORDER)

    def test_resolve_destroy_order_all_is_exact_and_excludes_backend_and_governance(self):
        result = self.run_registry("resolve_destroy_order all")
        self.assertEqual(result.returncode, 0, result.stderr)
        order = tuple(self.lines(result.stdout))
        self.assertEqual(order, EXPECTED_DESTROY_ALL_ORDER)
        self.assertNotIn("backend", order)
        self.assertNotIn("access-governance", order)

    def test_resolve_provision_order_for_narrow_scope_includes_full_dependency_chain(self):
        result = self.run_registry("resolve_provision_order boomi-runtime")
        self.assertEqual(result.returncode, 0, result.stderr)
        order = self.lines(result.stdout)
        # every dependency must appear, and strictly before boomi-runtime
        for dependency in ("backend", "eks-platform", "platform-controllers", "workload-identity"):
            self.assertIn(dependency, order)
            self.assertLess(order.index(dependency), order.index("boomi-runtime"))

    def test_resolve_destroy_order_for_explicit_backend_and_access_governance(self):
        for scope in ("backend", "access-governance"):
            with self.subTest(scope=scope):
                result = self.run_registry(f"resolve_destroy_order {scope}")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(self.lines(result.stdout), [scope])

    def test_resolve_provision_order_rejects_unknown_scope(self):
        result = self.run_registry("resolve_provision_order bogus-scope")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")

    def test_resolve_destroy_order_rejects_unknown_scope(self):
        result = self.run_registry("resolve_destroy_order bogus-scope")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")

    def test_resolve_provision_order_rejects_verification(self):
        result = self.run_registry("resolve_provision_order verification")
        self.assertNotEqual(result.returncode, 0)

    def test_resolve_destroy_order_rejects_verification(self):
        result = self.run_registry("resolve_destroy_order verification")
        self.assertNotEqual(result.returncode, 0)


class OrderDriftDetectionTests(ScopeRegistryFixture):
    """Step 1: prove the two hardcoded immutable order arrays never drift out
    of sync with the live `dependencies_for_scope` case statement, even
    though the orders themselves are literal data (approved tie-breaks are
    not derivable from the dependency graph alone, so they cannot simply be
    computed at runtime). If a future edit changes a dependency without
    updating both order arrays to match, this test catches it."""

    def _live_dependencies(self, scopes):
        live = {}
        for scope in scopes:
            result = self.run_registry(f"dependencies_for_scope {scope}")
            self.assertEqual(result.returncode, 0, result.stderr)
            live[scope] = tuple(result.stdout.split())
        return live

    def test_provision_order_all_respects_every_live_dependency(self):
        live_dependencies = self._live_dependencies(EXPECTED_ALL_ORDER)
        provision_index = {scope: index for index, scope in enumerate(EXPECTED_ALL_ORDER)}
        for scope, deps in live_dependencies.items():
            for dependency in deps:
                with self.subTest(scope=scope, dependency=dependency):
                    self.assertLess(
                        provision_index[dependency],
                        provision_index[scope],
                        f"{scope} appears before its live dependency {dependency} in EXPECTED_ALL_ORDER",
                    )

    def test_destroy_order_all_respects_every_live_dependency_in_reverse(self):
        live_dependencies = self._live_dependencies(EXPECTED_DESTROY_ALL_ORDER)
        destroy_index = {scope: index for index, scope in enumerate(EXPECTED_DESTROY_ALL_ORDER)}
        for scope, deps in live_dependencies.items():
            for dependency in deps:
                if dependency not in destroy_index:
                    # backend/access-governance are intentionally excluded
                    # from ordinary destroy; nothing to check against them.
                    continue
                with self.subTest(scope=scope, dependency=dependency):
                    self.assertGreater(
                        destroy_index[dependency],
                        destroy_index[scope],
                        f"{scope} is destroyed before its live dependency {dependency} in "
                        "EXPECTED_DESTROY_ALL_ORDER; a dependency must be destroyed later "
                        "than everything that depends on it",
                    )


class GenericGraphEngineTests(ScopeRegistryFixture):
    """Step 1: cycle detection, unknown dependencies, duplicate resolution,
    and full graph pre-resolution (no partial output on failure), proved
    against small synthetic callbacks independent of this registry's own
    (acyclic, by construction) real data."""

    def test_cycle_is_detected_and_nothing_is_printed(self):
        result = self.run_registry(
            "test_cycle_deps() { case \"$1\" in a) printf '%s\\n' b ;; "
            "b) printf '%s\\n' a ;; *) return 1 ;; esac; }; "
            "_scope_registry_resolve_dependency_order test_cycle_deps a"
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("cycle detected", result.stderr)
        self.assertEqual(result.stdout, "")

    def test_unknown_dependency_is_rejected_and_nothing_is_printed(self):
        result = self.run_registry(
            "test_unknown_dep() { case \"$1\" in a) printf '%s\\n' ghost ;; "
            "*) return 1 ;; esac; }; "
            "_scope_registry_resolve_dependency_order test_unknown_dep a"
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unknown dependency", result.stderr)
        self.assertIn("ghost", result.stderr)
        self.assertEqual(result.stdout, "")

    def test_duplicate_and_shared_dependencies_are_resolved_once_in_order(self):
        result = self.run_registry(
            "test_shared_deps() { case \"$1\" in leaf) printf '%s\\n' '' ;; "
            "left) printf '%s\\n' leaf ;; right) printf '%s\\n' leaf ;; "
            "*) return 1 ;; esac; }; "
            "_scope_registry_resolve_dependency_order test_shared_deps left right left"
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        order = self.lines(result.stdout)
        self.assertEqual(order.count("leaf"), 1)
        self.assertEqual(order.count("left"), 1)
        self.assertEqual(order.count("right"), 1)
        self.assertLess(order.index("leaf"), order.index("left"))
        self.assertLess(order.index("leaf"), order.index("right"))

    def test_full_graph_pre_resolution_fails_before_any_output_even_after_a_valid_root(self):
        result = self.run_registry(
            "test_mixed_deps() { case \"$1\" in ok) printf '%s\\n' '' ;; "
            "a) printf '%s\\n' b ;; b) printf '%s\\n' a ;; *) return 1 ;; esac; }; "
            "_scope_registry_resolve_dependency_order test_mixed_deps ok a"
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")


class ScopeRejectionTests(ScopeRegistryFixture):
    """Step 1: unknown scope rejection and `verification` rejection as a
    provision/destroy scope, across every lookup function."""

    LOOKUP_FUNCTIONS = (
        "dependencies_for_scope",
        "provision_handler_for_scope",
        "destroy_handler_for_scope",
        "pre_destroy_guard_for_scope",
        "state_key_variable_for_scope",
        "implementation_requirement_for_scope",
        "resolve_provision_order",
        "resolve_destroy_order",
    )

    def test_verification_is_rejected_by_every_scope_lookup_function(self):
        for function_name in self.LOOKUP_FUNCTIONS:
            with self.subTest(function=function_name):
                result = self.run_registry(f"{function_name} verification")
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, "")

    def test_unknown_scopes_are_rejected_by_every_scope_lookup_function(self):
        for function_name in self.LOOKUP_FUNCTIONS:
            for scope in ("bogus-scope", "mongo", "pg"):
                with self.subTest(function=function_name, scope=scope):
                    result = self.run_registry(f"{function_name} {scope}")
                    self.assertNotEqual(result.returncode, 0)
                    self.assertEqual(result.stdout, "")

    def test_dispatch_scope_handler_rejects_verification_as_a_scope(self):
        for operation in ("provision", "destroy"):
            with self.subTest(operation=operation):
                result = self.run_registry(f"dispatch_scope_handler {operation} verification")
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(self.command_log.exists())


class SymbolMappingTests(ScopeRegistryFixture):
    """Step 3: exact provision/destroy/pre-destroy-guard/verifier symbol
    mappings, including the placeholder-message convention distinguishing
    backend/access-governance/eks-access (foundation fragment, Task 5) from
    genuinely deferred work-package scopes."""

    def test_provision_handler_for_scope_is_exact(self):
        for scope, symbol in EXPECTED_PROVISION_HANDLER.items():
            with self.subTest(scope=scope):
                result = self.run_registry(f"provision_handler_for_scope {scope}")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), symbol)

    def test_destroy_handler_for_scope_is_exact(self):
        for scope, symbol in EXPECTED_DESTROY_HANDLER.items():
            with self.subTest(scope=scope):
                result = self.run_registry(f"destroy_handler_for_scope {scope}")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), symbol)

    def test_pre_destroy_guard_for_scope_is_exact_for_every_destroy_all_scope(self):
        self.assertEqual(set(EXPECTED_GUARD), set(EXPECTED_DESTROY_ALL_ORDER))
        for scope, symbol in EXPECTED_GUARD.items():
            with self.subTest(scope=scope):
                result = self.run_registry(f"pre_destroy_guard_for_scope {scope}")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), symbol)

    def test_backend_and_access_governance_have_no_pre_destroy_guard(self):
        for scope in ("backend", "access-governance"):
            with self.subTest(scope=scope):
                result = self.run_registry(f"pre_destroy_guard_for_scope {scope}")
                self.assertNotEqual(result.returncode, 0)

    def test_no_pseudo_scope_can_add_a_pre_destroy_guard(self):
        for scope in ("all", "verification"):
            with self.subTest(scope=scope):
                result = self.run_registry(f"pre_destroy_guard_for_scope {scope}")
                self.assertNotEqual(result.returncode, 0)

    def test_state_key_variable_for_scope_is_exact(self):
        for scope, variable in EXPECTED_STATE_KEY_VARIABLE.items():
            with self.subTest(scope=scope):
                result = self.run_registry(f"state_key_variable_for_scope {scope}")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), variable)

    def test_fragment_pending_scopes_report_task_5_message_not_a_work_package(self):
        for scope in FRAGMENT_PENDING_SCOPES:
            with self.subTest(scope=scope):
                symbol = EXPECTED_PROVISION_HANDLER[scope]
                result = self.run_registry(symbol)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("foundation access fragment (Task 5)", result.stderr)
                self.assertNotIn("work package", result.stderr)

    def test_deferred_scopes_report_their_exact_work_package(self):
        for scope, package in EXPECTED_WORK_PACKAGE_FOR_SCOPE.items():
            with self.subTest(scope=scope):
                symbol = EXPECTED_PROVISION_HANDLER[scope]
                result = self.run_registry(symbol)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(f"{scope} requires work package {package}", result.stderr)

    def test_eks_access_destroy_is_deferred_to_work_package_3_unlike_its_provision(self):
        result = self.run_registry("scope_registry_deferred_eks_access_destroy")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("eks-access requires work package 3", result.stderr)

    def test_every_mapped_provision_symbol_is_a_real_function(self):
        for scope, symbol in EXPECTED_PROVISION_HANDLER.items():
            with self.subTest(scope=scope):
                result = self.run_registry(f"type -t {symbol}")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), "function")

    def test_every_mapped_destroy_symbol_is_a_real_function(self):
        for scope, symbol in EXPECTED_DESTROY_HANDLER.items():
            with self.subTest(scope=scope):
                result = self.run_registry(f"type -t {symbol}")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), "function")

    def test_every_mapped_guard_symbol_is_a_real_function(self):
        for scope, symbol in EXPECTED_GUARD.items():
            with self.subTest(scope=scope):
                result = self.run_registry(f"type -t {symbol}")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), "function")

    def test_every_mapped_verifier_symbol_is_a_real_function(self):
        for slot in PREFLIGHT_SLOTS + EXPECTED_ALL_ORDER + SMOKE_ONLY_SLOTS:
            with self.subTest(slot=slot):
                result = self.run_registry(
                    f"symbol=\"$(verification_handler_for_slot '{slot}')\" && type -t \"$symbol\""
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), "function")

    def test_missing_symbol_mapping_fails_closed_not_command_not_found(self):
        # An unmapped scope must fail via the registry's own lookup
        # rejection, never by falling through to bash's own
        # "command not found" for a symbol that was never mapped at all.
        result = self.run_registry("provision_handler_for_scope bogus-scope")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("no provision handler is mapped", result.stderr)

    def test_non_function_symbol_name_is_never_returned_by_a_lookup(self):
        # Every symbol string ever returned by a lookup function must name
        # an actual function, never a variable/alias/builtin/external file.
        all_symbols = (
            list(EXPECTED_PROVISION_HANDLER.values())
            + list(EXPECTED_DESTROY_HANDLER.values())
            + list(EXPECTED_GUARD.values())
        )
        script = " && ".join(f"[[ \"$(type -t {symbol})\" == function ]]" for symbol in all_symbols)
        result = self.run_registry(script)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_fragment_attempting_to_define_an_unassigned_name_has_no_effect(self):
        # A rogue "fragment" that defines a plausible-but-wrong symbol name
        # (not the canonical one returned by provision_handler_for_scope)
        # must never be invoked by dispatch: only the exact registered
        # symbol name is ever called.
        result = self.run_registry(
            "foundation_provision_workload_identity() { printf 'HIJACKED\\n'; }; "
            "symbol=\"$(provision_handler_for_scope workload-identity)\" && "
            "\"$symbol\""
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("HIJACKED", result.stdout)
        self.assertIn("workload-identity requires work package 3", result.stderr)

    def test_task_five_style_redefinition_of_the_canonical_symbol_does_take_effect(self):
        # Confirms the documented override mechanism: redefining the exact
        # canonical symbol name after sourcing the registry replaces the
        # placeholder with no special mechanism required.
        result = self.run_registry(
            "foundation_provision_backend() { printf 'REAL\\n'; }; "
            "symbol=\"$(provision_handler_for_scope backend)\" && \"$symbol\""
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "REAL")


class ImplementationRequirementTests(ScopeRegistryFixture):
    def test_deferred_scopes_report_external_work_package(self):
        for scope, package in EXPECTED_WORK_PACKAGE_FOR_SCOPE.items():
            with self.subTest(scope=scope):
                result = self.run_registry(f"implementation_requirement_for_scope {scope}")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), f"external-work-package-{package}")

    def test_fragment_pending_scopes_are_distinguished_from_work_packages(self):
        for scope in FRAGMENT_PENDING_SCOPES:
            with self.subTest(scope=scope):
                result = self.run_registry(f"implementation_requirement_for_scope {scope}")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), "foundation-fragment-pending")

    def test_all_is_graph_expansion_only(self):
        result = self.run_registry("implementation_requirement_for_scope all")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "graph-expansion-only")

    def test_verification_and_unknown_scopes_are_rejected(self):
        for scope in ("verification", "bogus-scope"):
            with self.subTest(scope=scope):
                result = self.run_registry(f"implementation_requirement_for_scope {scope}")
                self.assertNotEqual(result.returncode, 0)


class VerificationModeTests(ScopeRegistryFixture):
    """Step 3: exact verifier-mode mapping. Component verifier slots are
    internal names only and are never accepted as public CLI mode values."""

    def test_preflight_mode_selects_exactly_the_preflight_slots(self):
        for mode in ("preflight", "--preflight"):
            with self.subTest(mode=mode):
                result = self.run_registry(f"verification_slots_for_mode {mode}")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(tuple(self.lines(result.stdout)), PREFLIGHT_SLOTS)

    def test_full_mode_and_no_flag_default_select_preflight_then_every_component_slot(self):
        expected = PREFLIGHT_SLOTS + EXPECTED_ALL_ORDER
        for mode in ("full", "--full", ""):
            with self.subTest(mode=mode or "<no-flag-default>"):
                result = self.run_registry(f"verification_slots_for_mode '{mode}'")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(tuple(self.lines(result.stdout)), expected)

    def test_smoke_test_mode_selects_full_then_immutable_smoke_slots(self):
        expected = PREFLIGHT_SLOTS + EXPECTED_ALL_ORDER + SMOKE_ONLY_SLOTS
        for mode in ("smoke-test", "--smoke-test"):
            with self.subTest(mode=mode):
                result = self.run_registry(f"verification_slots_for_mode {mode}")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(tuple(self.lines(result.stdout)), expected)

    def test_component_verifier_slot_names_are_never_accepted_as_a_public_mode(self):
        for slot in ("eks-platform", "mongodb", "aws-identity-region") + SMOKE_ONLY_SLOTS:
            with self.subTest(slot=slot):
                result = self.run_registry(f"verification_slots_for_mode {slot}")
                self.assertNotEqual(result.returncode, 0)

    def test_unknown_mode_is_rejected(self):
        result = self.run_registry("verification_slots_for_mode bogus-mode")
        self.assertNotEqual(result.returncode, 0)

    def test_resolve_verification_order_dedupes_while_preserving_order(self):
        result = self.run_registry("resolve_verification_order smoke-test")
        self.assertEqual(result.returncode, 0, result.stderr)
        order = self.lines(result.stdout)
        self.assertEqual(len(order), len(set(order)))
        self.assertEqual(tuple(order), PREFLIGHT_SLOTS + EXPECTED_ALL_ORDER + SMOKE_ONLY_SLOTS)

    def test_resolve_verification_order_rejects_unknown_mode(self):
        result = self.run_registry("resolve_verification_order bogus-mode")
        self.assertNotEqual(result.returncode, 0)


class DecisiveDispatchTests(ScopeRegistryFixture):
    """The decisive provision test: `all` reports
    "eks-platform requires work package 3" with an empty handler command
    log, and neither backend nor access-governance may run before the
    unsupported graph is rejected."""

    def test_all_provision_fails_on_eks_platform_before_backend_or_governance_run(self):
        result = self.run_registry("dispatch_scope_handler provision all")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("eks-platform requires work package 3", result.stderr)
        self.assertNotIn("backend requires the foundation access fragment", result.stderr)
        self.assertNotIn("access-governance requires the foundation access fragment", result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertFalse(self.command_log.exists())

    def test_narrow_scope_cascade_also_fails_before_its_own_pending_dependency_runs(self):
        result = self.run_registry("dispatch_scope_handler provision eks-access")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("eks-platform requires work package 3", result.stderr)
        self.assertNotIn("eks-access requires", result.stderr)
        self.assertFalse(self.command_log.exists())

    def test_destroy_all_fails_closed_on_the_first_deferred_scope(self):
        result = self.run_registry("dispatch_scope_handler destroy all")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("signoz-observability requires work package 4", result.stderr)
        self.assertFalse(self.command_log.exists())

    def test_dispatch_rejects_unknown_operation(self):
        result = self.run_registry("dispatch_scope_handler rebuild all")
        self.assertNotEqual(result.returncode, 0)

    def test_dispatch_rejects_unknown_scope(self):
        result = self.run_registry("dispatch_scope_handler provision bogus-scope")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.command_log.exists())


if __name__ == "__main__":
    unittest.main()
