#!/usr/bin/env python3
"""Validate, plan and deploy the existing fleet manifests without reading secrets."""
from __future__ import annotations

import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import platform
import re
import shlex
import shutil
import socket
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def inventory(root=ROOT):
    """node.conf remains authoritative for app order; fleet.json adds policy."""
    policy = json.loads((root / "fleet.json").read_text(encoding="utf-8"))
    if not isinstance(policy, dict) or policy.get("schema") != 1:
        raise ValueError("Unsupported fleet inventory schema")
    nodes = policy["nodes"]
    if not isinstance(nodes, dict) or not nodes:
        raise ValueError("fleet.json must contain a nonempty nodes object")
    discovered = {path.parent.name for path in (root / "stacks").glob("*/node.conf")}
    if set(nodes) != discovered:
        raise ValueError("fleet.json nodes must match stacks/*/node.conf")
    for name, node in nodes.items():
        if not isinstance(node, dict):
            raise ValueError(f"{name}: policy must be an object")
        if not re.fullmatch(r"[A-Za-z][A-Za-z0-9_-]*", name):
            raise ValueError("Invalid node identifier")
        directory = root / "stacks" / name
        text = (directory / "node.conf").read_text(encoding="utf-8")
        matches = re.findall(r"^APPS=\(([^)]*)\)", text, re.M)
        if len(matches) != 1:
            raise ValueError(f"{name}: exactly one APPS array is required")
        apps = shlex.split(matches[0], comments=True)
        if len(apps) != len(set(apps)) or not apps:
            raise ValueError(f"{name}: empty or duplicate app list")
        if any(not re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9_-]*", app) for app in apps):
            raise ValueError(f"{name}: invalid app identifier")
        present = {path.parent.name for path in directory.glob("*/docker-compose.yml")}
        if set(apps) != present:
            raise ValueError(f"{name}: APPS must match Compose directories")
        if node.get("platform") not in ("linux", "windows"):
            raise ValueError(f"{name}: unsupported platform")
        optional = node.get("optional", [])
        if not isinstance(optional, list) or not all(isinstance(app, str) for app in optional):
            raise ValueError(f"{name}: optional apps must be a list of names")
        if len(optional) != len(set(optional)) or not set(optional) <= set(apps):
            raise ValueError(f"{name}: invalid optional apps")
        if node.get("tier") not in ("essential", "data", "recovery", "household", "optional", "compute"):
            raise ValueError(f"{name}: unsupported service tier")
        if not isinstance(node.get("prerequisites"), list) or not all(
                isinstance(item, str) and item.strip() for item in node["prerequisites"]):
            raise ValueError(f"{name}: prerequisites must be a list of nonempty descriptions")
        node["apps"] = apps
        node["optional"] = optional
    return nodes


def selected_apps(node, included):
    unknown = set(included) - set(node["optional"])
    if unknown:
        raise ValueError("Unknown optional app selection: " + ", ".join(sorted(unknown)))
    return [app for app in node["apps"] if app not in node["optional"] or app in included]


def command_plan(root, name, node, included, timeout):
    directory = root / "stacks" / name
    apps = selected_apps(node, included)
    if node["platform"] == "linux":
        phases = [("configure", ["bash", str(directory / "setup-secrets.sh")]),
                  ("firewall", ["sudo", "bash", str(directory / "firewall.sh")])]
        prefix = ["bash", str(directory / "compose.sh")]
    else:
        shell = "powershell.exe" if os.name == "nt" else "pwsh"
        prefix_ps = [shell, "-NoProfile", "-File"]
        phases = [("configure", prefix_ps + [str(directory / "setup-secrets.ps1")])]
        prefix = prefix_ps + [str(directory / "compose.ps1")]
    for app in apps:
        phases.append((f"deploy:{app}", prefix + [app, "up", "-d", "--wait",
                                                 "--wait-timeout", str(timeout)]))
    return phases


def git_output(root, *arguments):
    result = subprocess.run(["git", "-C", str(root), *arguments], capture_output=True,
                            text=True, check=True, timeout=30)
    return result.stdout.strip()


def require_release(root, release):
    if not re.fullmatch(r"[0-9a-f]{40}", release):
        raise ValueError("--release must be a full 40-character commit ID")
    if git_output(root, "rev-parse", "HEAD") != release:
        raise ValueError("Checkout does not match the requested release")
    if git_output(root, "status", "--porcelain", "--untracked-files=normal"):
        raise ValueError("Deployment requires a clean checkout; inspect git status")
    return release


@contextmanager
def deployment_lock(path):
    """The OS releases this advisory lock even if the deploy process is killed."""
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    with path.open("a+b") as stream:
        if os.name == "nt":
            import msvcrt
            if path.stat().st_size == 0:
                stream.write(b"0")
                stream.flush()
            stream.seek(0)
            try:
                msvcrt.locking(stream.fileno(), msvcrt.LK_NBLCK, 1)
            except OSError as exc:
                raise ValueError("Another deployment is running for this node") from exc
            try:
                yield
            finally:
                stream.seek(0)
                msvcrt.locking(stream.fileno(), msvcrt.LK_UNLCK, 1)
        else:
            import fcntl
            try:
                fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError as exc:
                raise ValueError("Another deployment is running for this node") from exc
            try:
                yield
            finally:
                fcntl.flock(stream, fcntl.LOCK_UN)


def save_state(path, record):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    descriptor, temporary = tempfile.mkstemp(prefix=".deployment-", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            json.dump(record, stream, indent=2)
            stream.write("\n")
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def deploy(root, name, node, args):
    expected_platform = {"Windows": "windows", "Linux": "linux"}.get(platform.system())
    if expected_platform != node["platform"]:
        raise ValueError("Run deployment on the target node's supported operating system")
    if socket.gethostname().split(".")[0].casefold() != name.casefold():
        raise ValueError("Run deployment locally on the named node")
    if os.name != "nt" and os.geteuid() == 0:
        raise ValueError("Run deployment as the node operator; sudo is scoped to individual steps")
    if not args.acknowledge_prerequisites:
        raise ValueError("Read the plan and node README, then use --acknowledge-prerequisites")
    phases = command_plan(root, name, node, args.include_optional, args.wait_timeout)
    for binary in {command[0] for _, command in phases} | {"git", "docker"}:
        if not shutil.which(binary):
            raise ValueError(f"Required command is missing: {binary}")
    state_dir = root / ".fleet"
    # One operator lock across checkouts; scheduled jobs and legacy wrappers
    # remain separate operations and must not overlap a deployment.
    lock_dir = Path.home() / ".local" / "state" / "purrbrews"
    with deployment_lock(lock_dir / f"{name}.lock"):
        release = require_release(root, args.release)
        record = {"node": name, "release": release, "status": "running",
                  "started_at": datetime.now(timezone.utc).isoformat(), "completed_phases": []}
        state_path = state_dir / f"{name}.json"
        save_state(state_path, record)
        try:
            for phase, command in phases:
                record["phase"] = phase
                save_state(state_path, record)
                print(f"[{name}] {phase}", flush=True)
                subprocess.run(command, cwd=root / "stacks" / name, check=True,
                               env=dict(os.environ, PURRBREWS_KEEP_IMAGES="1"))
                record["completed_phases"].append(phase)
            record["status"] = "succeeded"
        except (subprocess.CalledProcessError, OSError, KeyboardInterrupt):
            record["status"] = "failed"
            print(f"Deployment stopped at {record['phase']}. Completed steps remain applied. "
                  "Inspect local status and the recovery guide before retrying.", file=sys.stderr)
            raise
        finally:
            record["finished_at"] = datetime.now(timezone.utc).isoformat()
            save_state(state_path, record)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)
    sub.add_parser("validate", help="validate manifest and policy consistency")
    for action in ("plan", "deploy", "status"):
        command = sub.add_parser(action)
        command.add_argument("node")
        if action != "status":
            command.add_argument("--include-optional", action="append", default=[], metavar="APP")
            command.add_argument("--wait-timeout", type=int, default=180)
        if action == "deploy":
            command.add_argument("--release", required=True)
            command.add_argument("--acknowledge-prerequisites", action="store_true")
    args = parser.parse_args(argv)
    try:
        nodes = inventory()
        if args.action == "validate":
            print(f"Validated {len(nodes)} nodes and {sum(len(n['apps']) for n in nodes.values())} apps")
            return 0
        if args.node not in nodes:
            raise ValueError("Unknown node; choose: " + ", ".join(nodes))
        node = nodes[args.node]
        if args.action == "status":
            path = ROOT / ".fleet" / f"{args.node}.json"
            print(path.read_text(encoding="utf-8") if path.exists()
                  else "No deployment record exists in this checkout; live state is unverified.")
            return 0
        if args.wait_timeout < 1:
            raise ValueError("--wait-timeout must be positive")
        phases = command_plan(ROOT, args.node, node, args.include_optional, args.wait_timeout)
        if args.action == "plan":
            print(f"{args.node}: {node['platform']}, tier={node['tier']}")
            for prerequisite in node["prerequisites"]:
                print(f"Prerequisite: {prerequisite}")
            for phase, command in phases:
                print(f"{phase}: {shlex.join(command)}")
            return 0
        deploy(ROOT, args.node, node, args)
        return 0
    except (ValueError, KeyError, OSError, subprocess.SubprocessError) as exc:
        # Deployment command output is never copied into persistent state.
        print(f"fleet: {exc}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("fleet: interrupted", file=sys.stderr)
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
