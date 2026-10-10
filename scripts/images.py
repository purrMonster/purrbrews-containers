#!/usr/bin/env python3
"""Resolve public OCI image digests without pulling images or running containers.

Usage: python scripts/images.py IMAGE [IMAGE ...]
Prints JSON suitable for reviewing image-lock.json updates. No credentials used.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from urllib.error import HTTPError
from urllib.parse import urlencode, urlparse
from urllib.request import Request, urlopen

ACCEPT = ", ".join(("application/vnd.oci.image.index.v1+json",
                    "application/vnd.docker.distribution.manifest.list.v2+json",
                    "application/vnd.oci.image.manifest.v1+json",
                    "application/vnd.docker.distribution.manifest.v2+json"))


def split_reference(image):
    reference = image.split("@", 1)[0]
    name, tag = reference.rsplit(":", 1)
    parts = name.split("/", 1)
    if len(parts) == 2 and ("." in parts[0] or ":" in parts[0]):
        registry, repository = parts
    else:
        registry = "registry-1.docker.io"
        repository = name if "/" in name else "library/" + name
    if not re.fullmatch(r"[a-z0-9.-]+", registry):
        raise ValueError("Unsupported registry hostname")
    if not re.fullmatch(r"[a-z0-9_./-]+", repository) or ".." in repository:
        raise ValueError("Invalid image repository")
    if not re.fullmatch(r"[A-Za-z0-9_.-]+", tag):
        raise ValueError("Invalid image tag")
    return registry, repository, tag


def resolve(image):
    registry, repository, tag = split_reference(image)
    url = f"https://{registry}/v2/{repository}/manifests/{tag}"
    headers = {"Accept": ACCEPT, "User-Agent": "purrbrews-image-audit/1"}
    try:
        response = urlopen(Request(url, headers=headers), timeout=45)
    except HTTPError as exc:
        if exc.code != 401:
            raise
        challenge = exc.headers.get("WWW-Authenticate", "")
        if not challenge.lower().startswith("bearer "):
            raise ValueError("Registry does not support anonymous bearer authentication") from exc
        values = dict(re.findall(r'(\w+)="([^"]*)"', challenge))
        realm = values["realm"]
        if urlparse(realm).scheme != "https":
            raise ValueError("Registry requested an insecure authentication endpoint")
        query = urlencode({key: values[key] for key in ("service", "scope") if key in values})
        with urlopen(Request(realm + "?" + query, headers={"User-Agent": headers["User-Agent"]}),
                     timeout=45) as token_response:
            token = json.load(token_response)
        headers["Authorization"] = "Bearer " + (token.get("token") or token["access_token"])
        response = urlopen(Request(url, headers=headers), timeout=45)
    with response:
        content = response.read()
        digest = "sha256:" + hashlib.sha256(content).hexdigest()
        declared = response.headers.get("Docker-Content-Digest", digest)
        if digest != declared:
            raise ValueError("Manifest digest does not match registry response")
    manifest = json.loads(content)
    platforms = sorted({f"{entry['platform'].get('os')}/{entry['platform'].get('architecture')}"
                        for entry in manifest.get("manifests", []) if "platform" in entry})
    return {"image": image.split("@", 1)[0], "digest": digest, "platforms": platforms,
            "registry_url": url}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("images", nargs="+")
    args = parser.parse_args()
    try:
        records = [resolve(image) for image in args.images]
    except (OSError, ValueError, KeyError) as exc:
        parser.exit(1, f"Image resolution failed ({type(exc).__name__}); no files changed.\n")
    print(json.dumps(records, indent=2))


if __name__ == "__main__":
    main()
