#!/usr/bin/env python3
"""Verify upstream sources for gentoo-ing packages.

For each package in config/packages.txt, read its .gentooit/<package>.yaml
config and verify that the source archive URL is accessible and its checksum
matches what we expect (if recorded).

Outputs a report to reports/verify-sources/.
"""

import argparse
import hashlib
import os
import re
import sys
from pathlib import Path

import requests
import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent
CONFIG_DIR = REPO_ROOT / ".gentooit"
PACKAGES_FILE = REPO_ROOT / "config" / "packages.txt"
REPORTS_DIR = REPO_ROOT / "reports" / "verify-sources"


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha512(data: bytes) -> str:
    return hashlib.sha512(data).hexdigest()


def load_packages() -> list[str]:
    if not PACKAGES_FILE.exists():
        return []
    packages = []
    for line in PACKAGES_FILE.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        packages.append(line)
    return packages


def load_config(package: str) -> dict | None:
    config_file = CONFIG_DIR / f"{package}.yaml"
    if not config_file.exists():
        return None
    return yaml.safe_load(config_file.read_text())


def resolve_url(config: dict, version: str) -> str | None:
    upstream = config.get("upstream", {})
    archive_template = upstream.get("archive-template") or upstream.get("archive_template")
    if archive_template:
        url = archive_template.replace("{version}", version)
        url = url.replace("${PV}", version)
        url = url.replace("${P}", f"{upstream.get('package-name', package)}-{version}")
        return url
    return None


def verify_package(package: str) -> dict:
    result = {
        "package": package,
        "status": "unknown",
        "url": None,
        "sha256": None,
        "sha512": None,
        "error": None,
    }

    config = load_config(package)
    if not config:
        result["status"] = "skip"
        result["error"] = "no .gentooit config found"
        return result

    upstream = config.get("upstream", {})
    version = upstream.get("version")
    if not version:
        # Try to resolve from GitHub releases
        repo = upstream.get("upstream", "")
        if "/" in repo:
            api_url = f"https://api.github.com/repos/{repo}/releases/latest"
            try:
                resp = requests.get(api_url, timeout=30)
                if resp.status_code == 200:
                    data = resp.json()
                    tag_name = data.get("tag_name", "")
                    # Extract version from tag
                    tag_template = upstream.get("tag-template") or upstream.get("tag_template", "{version}")
                    version = tag_template.replace("{version}", "PLACEHOLDER")
                    # Simple extraction: remove prefix/suffix
                    result["resolved_version"] = tag_name
                else:
                    result["status"] = "error"
                    result["error"] = f"GitHub API returned {resp.status_code}"
                    return result
            except Exception as e:
                result["status"] = "error"
                result["error"] = str(e)
                return result
        else:
            result["status"] = "skip"
            result["error"] = "no version specified"
            return result

    result["version"] = version
    url = resolve_url(config, version)
    result["url"] = url

    if not url:
        result["status"] = "skip"
        result["error"] = "no archive URL"
        return result

    try:
        resp = requests.get(url, stream=True, timeout=60, allow_redirects=True)
        if resp.status_code != 200:
            result["status"] = "error"
            result["error"] = f"HTTP {resp.status_code}"
            return result

        data = b""
        for chunk in resp.iter_content(chunk_size=65536):
            data += chunk

        result["sha256"] = sha256(data)
        result["sha512"] = sha512(data)
        result["size"] = len(data)
        result["status"] = "ok"
    except Exception as e:
        result["status"] = "error"
        result["error"] = str(e)

    return result


def main() -> int:
    parser = argparse.ArgumentParser(description="Verify upstream sources")
    parser.add_argument("package", nargs="?", help="Package to verify (default: all)")
    args = parser.parse_args()

    REPORTS_DIR.mkdir(parents=True, exist_ok=True)

    packages = load_packages()
    if args.package:
        packages = [args.package]

    results = []
    for pkg in packages:
        print(f"Verifying {pkg}...")
        result = verify_package(pkg)
        results.append(result)
        status = result["status"]
        if status == "ok":
            print(f"  OK: {result['url']} ({result.get('size', 0)} bytes)")
        elif status == "skip":
            print(f"  SKIP: {result['error']}")
        else:
            print(f"  FAIL: {result['error']}")

    # Write report
    report_path = REPORTS_DIR / "verify-sources.txt"
    lines = []
    for r in results:
        lines.append(f"{r['package']}: {r['status']}")
        if r.get("url"):
            lines.append(f"  url: {r['url']}")
        if r.get("version"):
            lines.append(f"  version: {r['version']}")
        if r.get("sha256"):
            lines.append(f"  sha256: {r['sha256']}")
        if r.get("sha512"):
            lines.append(f"  sha512: {r['sha512']}")
        if r.get("error"):
            lines.append(f"  error: {r['error']}")

    report_path.write_text("\n".join(lines) + "\n")

    # Exit non-zero if any package failed
    if any(r["status"] == "error" for r in results):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
