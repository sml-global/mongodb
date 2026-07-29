"""Validate that environment VPC/subnet CIDR allocations do not overlap.

Used both as a standalone check (see __main__) and as a library imported by
tests/network_cidr/test_cidr_allocation.py.
"""
import ipaddress
import re
import sys
from pathlib import Path

_VPC_CIDR_RE = re.compile(r'vpc_cidr\s*=\s*"([^"]+)"')
_LIST_VAR_RE = re.compile(r'(\w*subnet_cidrs)\s*=\s*\[([^\]]*)\]', re.DOTALL)
_STRING_RE = re.compile(r'"([^"]+)"')


def parse_environment_cidrs(tfvars_path: Path) -> dict:
    """Extract vpc_cidr and every subnet CIDR listed in a *.tfvars file."""
    text = tfvars_path.read_text(encoding="utf-8")

    vpc_match = _VPC_CIDR_RE.search(text)
    if not vpc_match:
        raise ValueError(f"{tfvars_path}: no vpc_cidr found")
    vpc_cidr = vpc_match.group(1)

    subnets: list[str] = []
    for _, list_body in _LIST_VAR_RE.findall(text):
        subnets.extend(_STRING_RE.findall(list_body))

    return {"vpc_cidr": vpc_cidr, "subnets": subnets}


def validate_no_overlaps(environments: dict[str, dict]) -> list[str]:
    """Return a list of conflict descriptions; empty list means everything is valid."""
    conflicts: list[str] = []

    networks: dict[str, ipaddress.IPv4Network] = {}
    for name, data in environments.items():
        networks[name] = ipaddress.ip_network(data["vpc_cidr"])

    # 1. No two environment VPC CIDRs may overlap.
    names = list(networks)
    for i, name_a in enumerate(names):
        for name_b in names[i + 1:]:
            if networks[name_a].overlaps(networks[name_b]):
                conflicts.append(
                    f"VPC CIDR overlap: {name_a} ({networks[name_a]}) overlaps "
                    f"{name_b} ({networks[name_b]})"
                )

    # 2. Every subnet must be contained within its own environment's VPC CIDR,
    #    and no two subnets within the same environment may overlap each other.
    for name, data in environments.items():
        vpc_net = networks[name]
        subnet_nets = [ipaddress.ip_network(cidr) for cidr in data["subnets"]]

        for subnet in subnet_nets:
            if not subnet.subnet_of(vpc_net):
                conflicts.append(
                    f"{name}: subnet {subnet} is not contained within its own vpc_cidr {vpc_net}"
                )

        for i, subnet_a in enumerate(subnet_nets):
            for subnet_b in subnet_nets[i + 1:]:
                if subnet_a.overlaps(subnet_b):
                    conflicts.append(
                        f"{name}: subnet {subnet_a} overlaps subnet {subnet_b}"
                    )

    return conflicts


def _discover_environment_tfvars(environments_dir: Path) -> dict[str, Path]:
    result = {}
    for env_dir in sorted(environments_dir.iterdir()):
        candidate = env_dir / "eks-platform.tfvars"
        if candidate.is_file():
            result[env_dir.name] = candidate
    return result


if __name__ == "__main__":
    repo_root = Path(__file__).resolve().parents[1]
    environments_dir = repo_root / "platform-prerequisites" / "terraform" / "environments"
    tfvars_by_env = _discover_environment_tfvars(environments_dir)
    parsed = {name: parse_environment_cidrs(path) for name, path in tfvars_by_env.items()}
    found_conflicts = validate_no_overlaps(parsed)
    if found_conflicts:
        for conflict in found_conflicts:
            print(f"CONFLICT: {conflict}", file=sys.stderr)
        sys.exit(1)
    print(f"OK: {len(parsed)} environment(s) checked, no CIDR conflicts.")
