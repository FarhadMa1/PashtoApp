#!/usr/bin/env python3
"""Copy the screenshot PNGs into one flat directory.

Reads an xcresulttool attachment manifest when one is present, and also
picks up PNGs that the test wrote under their final names.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import sys

SCREENS = ("home", "home-new-categories", "numbers-learn", "family", "learn", "learn-list", "learn-list-numbers", "quiz", "celebration")
VARIANTS = ("light", "dark", "xl")
EXPECTED = [f"{screen}-{variant}.png" for screen in SCREENS for variant in VARIANTS]
PNG_MAGIC = b"\x89PNG\r\n\x1a\n"
MIN_BYTES = 20_000


def canonical(name: str) -> str | None:
    base = os.path.basename(name).strip()
    if not base:
        return None
    root, ext = os.path.splitext(base)
    if ext.lower() != ".png":
        root = base
    if root not in {item[:-4] for item in EXPECTED}:
        return None
    return root + ".png"


def load_manifest(path: str) -> list[tuple[str, str]]:
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
    found: list[tuple[str, str]] = []

    def walk(node: object) -> None:
        if isinstance(node, dict):
            exported = node.get("exportedFileName")
            human = node.get("suggestedHumanReadableName") or node.get("name")
            if isinstance(exported, str) and isinstance(human, str):
                found.append((exported, human))
            for value in node.values():
                walk(value)
        elif isinstance(node, list):
            for value in node:
                walk(value)

    walk(data)
    return found


def find_file(staging: str, exported: str) -> str | None:
    direct = os.path.join(staging, exported)
    if os.path.isfile(direct):
        return direct
    for root, _dirs, files in os.walk(staging):
        if exported in files:
            return os.path.join(root, exported)
    return None


def copy_png(source: str, dest: str) -> None:
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    shutil.copy2(source, dest)


def valid_png(path: str) -> str | None:
    if not os.path.isfile(path):
        return "missing"
    size = os.path.getsize(path)
    if size < MIN_BYTES:
        return f"too small ({size} bytes)"
    with open(path, "rb") as handle:
        if handle.read(len(PNG_MAGIC)) != PNG_MAGIC:
            return "not a PNG"
    return None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    parser.add_argument("--manifest-root", action="append", default=[])
    parser.add_argument("--scan", action="append", default=[])
    args = parser.parse_args()

    output = args.output
    os.makedirs(output, exist_ok=True)
    copied: dict[str, str] = {}

    for root in args.scan:
        if not os.path.isdir(root):
            print(f"scan skipped, not a directory: {root}", file=sys.stderr)
            continue
        for dirpath, _dirs, files in os.walk(root):
            for name in files:
                target = canonical(name)
                if target is None or target in copied:
                    continue
                source = os.path.join(dirpath, name)
                dest = os.path.join(output, target)
                copy_png(source, dest)
                copied[target] = source

    manifests: list[str] = []
    for root in args.manifest_root:
        direct = os.path.join(root, "manifest.json")
        if os.path.isfile(direct):
            manifests.append(direct)
        if os.path.isdir(root):
            for dirpath, _dirs, files in os.walk(root):
                if "manifest.json" in files:
                    path = os.path.join(dirpath, "manifest.json")
                    if path not in manifests:
                        manifests.append(path)
    if args.manifest_root and not manifests:
        print("no manifest.json under the attachment export", file=sys.stderr)

    for manifest in manifests:
        root = os.path.dirname(manifest)
        for exported, human in load_manifest(manifest):
            target = canonical(human)
            if target is None or target in copied:
                continue
            source = find_file(root, exported)
            if source is None:
                print(f"manifest entry {exported} was not exported", file=sys.stderr)
                continue
            dest = os.path.join(output, target)
            copy_png(source, dest)
            copied[target] = source

    missing = []
    for name in EXPECTED:
        path = os.path.join(output, name)
        problem = valid_png(path)
        if problem is None:
            print(f"ok {name} {os.path.getsize(path)}")
        else:
            missing.append(f"{name}: {problem}")
            print(f"bad {name}: {problem}", file=sys.stderr)

    if missing:
        print(f"{len(missing)} screenshot(s) missing or unusable", file=sys.stderr)
        return 1
    if len(copied) != len(EXPECTED):
        print(f"expected to copy {len(EXPECTED)} files, copied {len(copied)}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
