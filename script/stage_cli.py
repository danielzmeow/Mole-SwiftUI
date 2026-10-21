#!/usr/bin/env python3
"""Stage an unchanged, version-pinned CLI into a local development app bundle."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent


def main():
    bundle = ROOT / "dist" / "MoleShell.app"
    resources = bundle / "Contents" / "Resources"
    contract_path = ROOT / "macos" / "Compatibility.json"
    contract = json.loads(contract_path.read_text())
    # Do not silently pair a new checkout/working tree with an old Adapter contract.
    subprocess.run([
        "git", "diff", "--exit-code", contract["sourceCommit"], "--",
        "mole", "mo", "bin", "lib", "cmd", "internal", "go.mod", "go.sum",
    ], cwd=ROOT, check=True, stdout=subprocess.DEVNULL)
    version_line = f'VERSION="{contract["version"]}"'
    if version_line not in (ROOT / "mole").read_text().splitlines():
        raise RuntimeError("Update macos/Compatibility.json after reviewing the upstream interface changes.")
    cli = resources / "CLI"
    cli.mkdir(parents=True, exist_ok=True)
    paths = subprocess.check_output([
        "git", "ls-files", "-z", "--", "mole", "mo", "bin", "lib", "LICENSE"
    ], cwd=ROOT).decode().split("\0")
    for name in filter(None, paths):
        destination = cli / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / name, destination)
    local_go = ROOT / "macos" / ".build" / "toolchains" / "go" / "bin" / "go"
    go = os.environ.get("GO") or shutil.which("go") or str(local_go)
    if not shutil.which(go):
        raise RuntimeError("Go 1.26+ is required to build the bundled CLI. Install Go or set GO to its executable.")
    environment = dict(os.environ, CGO_ENABLED="0")
    environment.setdefault("GOCACHE", str(ROOT / "macos" / ".build" / "go-cache"))
    environment.setdefault("GOMODCACHE", str(ROOT / "macos" / ".build" / "go-mod"))
    for name in ("analyze", "status"):
        subprocess.run([
            go, "build", "-trimpath", "-ldflags=-s -w", "-o",
            str(cli / "bin" / f"{name}-go"), f"./cmd/{name}",
        ], cwd=ROOT, env=environment, check=True)
    shutil.copy2(contract_path, resources / "Compatibility.json")
    print(f"Bundled Mole {contract['version']} from {contract['sourceCommit'][:12]}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"CLI staging failed: {error}", file=sys.stderr)
        sys.exit(1)
