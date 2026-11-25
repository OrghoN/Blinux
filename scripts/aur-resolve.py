#!/usr/bin/env python3
"""Resolve the AUR dependency closure for Blinux and write a lock file.

Given package names (from packages/aur.txt and the depends of our own
PKGBUILDs), find every dependency that the official repos cannot satisfy,
look it up on the AUR, recurse, and print the AUR package bases in build
order (dependencies first).

    scripts/aur-resolve.py [--local NAME ...] [--lock FILE] NAME ...

With --lock, also record the current AUR git commit of every package base,
so builds are pinned and every bump is a reviewable diff.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import urllib.parse
import urllib.request

AUR_RPC = "https://aur.archlinux.org/rpc/v5/info"
AUR_GIT = "https://aur.archlinux.org/{}.git"

_official_cache: dict[str, bool] = {}


def strip_version(dep: str) -> str:
    """'tcl=8.6.16-1' -> 'tcl', 'python>=3' -> 'python'."""
    return re.split(r"[<>=]", dep, maxsplit=1)[0].strip()


def in_official_repos(name: str) -> bool:
    """True if pacman's sync databases can satisfy NAME (including provides)."""
    if name not in _official_cache:
        result = subprocess.run(
            ["pacman", "-Sp", "--print-format", "%n", name],
            capture_output=True,
            text=True,
        )
        _official_cache[name] = result.returncode == 0
    return _official_cache[name]


def aur_info(names: list[str]) -> list[dict]:
    results: list[dict] = []
    for i in range(0, len(names), 100):
        chunk = names[i : i + 100]
        query = urllib.parse.urlencode([("arg[]", n) for n in chunk])
        with urllib.request.urlopen(f"{AUR_RPC}?{query}", timeout=30) as resp:
            data = json.load(resp)
        if data.get("type") == "error":
            raise SystemExit(f"AUR RPC error: {data.get('error')}")
        results.extend(data["results"])
    return results


def aur_provider_search(name: str) -> dict | None:
    """Find an AUR package that provides NAME when no package is called NAME."""
    query = urllib.parse.urlencode({"by": "provides", "arg": name})
    url = f"https://aur.archlinux.org/rpc/v5/search/{urllib.parse.quote(name)}?{query}"
    with urllib.request.urlopen(url, timeout=30) as resp:
        data = json.load(resp)
    candidates = data.get("results", [])
    if not candidates:
        return None
    best = max(candidates, key=lambda r: r.get("NumVotes", 0))
    return aur_info([best["Name"]])[0]


def resolve(roots: list[str], local: set[str]) -> tuple[list[str], dict[str, dict]]:
    """Return (build order of pkgbases, pkgbase -> info)."""
    by_name: dict[str, dict] = {}  # package name or provided name -> info
    bases: dict[str, dict] = {}
    pending = [strip_version(r) for r in roots]
    seen: set[str] = set()
    missing: list[str] = []

    while pending:
        wanted = [
            n
            for n in dict.fromkeys(pending)
            if n not in seen and n not in local and not in_official_repos(n)
        ]
        seen.update(pending)
        pending = []
        if not wanted:
            continue
        found = {r["Name"]: r for r in aur_info(wanted)}
        for name in wanted:
            info = found.get(name) or aur_provider_search(name)
            if info is None:
                missing.append(name)
                continue
            by_name[name] = info
            by_name[info["Name"]] = info
            for prov in info.get("Provides", []) or []:
                by_name[strip_version(prov)] = info
            bases[info["PackageBase"]] = info
            for field in ("Depends", "MakeDepends", "CheckDepends"):
                pending.extend(strip_version(d) for d in info.get(field, []) or [])

    if missing:
        raise SystemExit("not found in official repos or the AUR: " + ", ".join(missing))

    # Topological sort of package bases.
    order: list[str] = []
    state: dict[str, int] = {}

    def visit(base: str) -> None:
        if state.get(base) == 2:
            return
        if state.get(base) == 1:
            raise SystemExit(f"dependency cycle involving {base}")
        state[base] = 1
        info = bases[base]
        for field in ("Depends", "MakeDepends", "CheckDepends"):
            for dep in info.get(field, []) or []:
                dep_info = by_name.get(strip_version(dep))
                if dep_info and dep_info["PackageBase"] != base:
                    visit(dep_info["PackageBase"])
        state[base] = 2
        order.append(base)

    for base in sorted(bases):
        visit(base)
    return order, bases


def head_commit(base: str) -> str:
    out = subprocess.run(
        ["git", "ls-remote", AUR_GIT.format(base), "HEAD"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout.split()
    if not out:
        raise SystemExit(f"could not read AUR git HEAD for {base}")
    return out[0]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("names", nargs="+")
    ap.add_argument("--local", nargs="*", default=[], help="names built from pkgbuilds/")
    ap.add_argument("--lock", help="write '<pkgbase> <version> <commit>' lines to this file")
    args = ap.parse_args()

    order, bases = resolve(args.names, set(args.local))
    if args.lock:
        lines = [
            "# Generated by scripts/aur-resolve.py. Build order: dependencies first.",
            "# <pkgbase> <aur version> <aur git commit>",
        ]
        for base in order:
            lines.append(f"{base} {bases[base]['Version']} {head_commit(base)}")
        with open(args.lock, "w") as fh:
            fh.write("\n".join(lines) + "\n")
    for base in order:
        print(base)
    return 0


if __name__ == "__main__":
    sys.exit(main())
