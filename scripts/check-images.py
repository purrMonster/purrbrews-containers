#!/usr/bin/env python3
"""Offline check that every active registry image matches the reviewed lock file."""
from __future__ import annotations

import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]


def check(root=ROOT):
    lock = json.loads((root / "image-lock.json").read_text(encoding="utf-8"))
    if lock.get("schema") != 1:
        raise ValueError("Unsupported image-lock schema")
    expected = {}
    for image in lock["images"]:
        if not re.fullmatch(r"sha256:[0-9a-f]{64}", image["digest"]):
            raise ValueError("Malformed digest in image-lock.json")
        reference = image["image"] + "@" + image["digest"]
        if reference in expected:
            raise ValueError("Duplicate image in image-lock.json")
        expected[reference] = set(image["files"])
    paths = list((root / "stacks").rglob("docker-compose.yml"))
    paths += list((root / "stacks/_shared").glob("*.yml"))
    paths += [root / path for path in ("bootstrap/compose.yaml", "bootstrap/Dockerfile",
              "stacks/grinder/embedding-worker/Dockerfile", "stacks/cellar/restic/restore-test.sh",
              "init/roastery-init.ps1")]
    actual = {}
    for path in paths:
        content = path.read_text(encoding="utf-8")
        references = re.findall(r"(?:^\s*image:\s+|^x-image:\s+&image\s+|^FROM\s+|^PG_IMAGE=)([^\s#]+)", content, re.M)
        if path.name == "roastery-init.ps1":
            references += re.findall(r"nvidia/cuda:[^\s]+", content)
        for reference in references:
            if reference.startswith("*") or reference.endswith(":local"):
                continue
            actual.setdefault(reference, set()).add(path.relative_to(root).as_posix())
    if actual != expected:
        raise ValueError("Image references or file coverage differ from image-lock.json; review and update both")
    return len(expected)


if __name__ == "__main__":
    try:
        print(f"Verified {check()} locked registry images (offline)")
    except (OSError, ValueError, KeyError) as exc:
        print(f"Image lock: {exc}", file=sys.stderr)
        raise SystemExit(1)
