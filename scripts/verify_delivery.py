#!/usr/bin/env python3
"""Read-only anonymous delivery check: latest IPA normally, all retained IPAs on archive changes."""
import argparse
import json
import time
import tempfile
import urllib.request
from pathlib import Path

from distribution import BUNDLE_ID, MAX_IPA_BYTES, release_config, verify_bytes
from inspect_ipa import inspect_ipa

ROOT = Path(__file__).resolve().parents[1]


def fetch(url, limit):
    request = urllib.request.Request(url, headers={"User-Agent": "PersonalBrowser-delivery-check"})
    with urllib.request.urlopen(request, timeout=60) as response:
        data = response.read(limit + 1)
    if len(data) > limit:
        raise ValueError("Delivery response exceeded its size limit")
    return data


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--all-versions", action="store_true")
    parser.add_argument("--expected-version")
    parser.add_argument("--expected-build")
    args = parser.parse_args()
    config = release_config(ROOT)
    repo = config["public_repository"]
    feed_url = f"https://raw.githubusercontent.com/{repo}/main/source.json?check={time.time_ns()}"
    app = json.loads(fetch(feed_url, 4 * 1024 * 1024))["apps"][0]
    if app["bundleIdentifier"] != BUNDLE_ID:
        raise ValueError("Delivered app identity changed")
    versions = app["versions"] if args.all_versions else app["versions"][:1]
    if not versions:
        raise ValueError("No delivered version")
    latest = versions[0]
    if args.expected_version and latest["version"] != args.expected_version:
        raise ValueError("The newly published version is not at the front of the feed")
    if args.expected_build and latest["buildVersion"] != args.expected_build:
        raise ValueError("The newly published build is not at the front of the feed")
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "PersonalBrowser.ipa"
        for version in versions:
            if not version["downloadURL"].startswith(f"https://github.com/{repo}/releases/download/"):
                raise ValueError("Unexpected IPA delivery origin")
            data = fetch(version["downloadURL"], MAX_IPA_BYTES)
            verify_bytes(data, version)
            path.write_bytes(data)
            inspected = inspect_ipa(path, "18.4.1", BUNDLE_ID, unsigned=True)
            if inspected["version"] != version["version"] or inspected["build"] != version["buildVersion"]:
                raise ValueError("Feed and IPA versions differ")
            print(f"Delivery verified: {version['version']} build{version['buildVersion']}")


if __name__ == "__main__":
    main()
