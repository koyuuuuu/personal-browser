#!/usr/bin/env python3
"""Publish only generated filter data; leave app releases and the SideStore feed untouched."""
import argparse
import json
from pathlib import Path

from distribution import verify_bytes
from publish_release import GitHub

TAG = "filter-data-v1"


def publish_filters(github, directory):
    if github.repo != "koyuuuuu/personal-browser-distribution" or github.request("")["private"]:
        raise ValueError("Unexpected filter distribution repository")
    root = Path(directory)
    manifest = json.loads((root / "manifest.json").read_text())
    release = github.request(f"/releases/tags/{TAG}", allow_missing=True)
    previous = None
    if release:
        existing = next((a for a in release["assets"] if a["name"] == "manifest.json"), None)
        if existing:
            previous = json.loads(github.asset(release, "manifest.json"))
            if previous["revision"] == manifest["revision"]:
                print("Filter content is unchanged; no publication needed.")
                return
    else:
        release = github.request("/releases", method="POST", body={
            "tag_name": TAG, "target_commitish": "main", "name": "Personal Browser filter data",
            "body": "WebKit rules converted with Brave adblock-rust. Filter data: GPL-3.0; converter: MPL-2.0. Original lists, conversion sources and licences are included in each filter-sources ZIP. This is not an app release. No warranty.",
            "draft": True, "prerelease": True,
        })
    assets = {a["name"]: a for a in release["assets"]}
    files = {f["name"]: f for profile in manifest["profiles"].values() for f in profile}
    for name, record in files.items():
        data = (root / name).read_bytes(); verify_bytes(data, record)
        existing = assets.get(name)
        if existing:
            if existing["size"] != len(data): raise ValueError("Immutable filter chunk changed")
            continue
        github.request(release["upload_url"].split("{")[0] + "?name=" + name, method="POST", body=data)
    archive = manifest["sourceArchive"]
    if archive not in assets:
        github.request(release["upload_url"].split("{")[0] + "?name=" + archive, method="POST", body=(root / archive).read_bytes())
    # Only the small manifest pointer is mutable. It is advertised LAST.
    if "manifest.json" in assets:
        github.request(f"/releases/assets/{assets['manifest.json']['id']}", method="DELETE")
    github.request(release["upload_url"].split("{")[0] + "?name=manifest.json", method="POST", body=(root / "manifest.json").read_bytes())
    github.request(f"/releases/{release['id']}", method="PATCH", body={"draft": False, "prerelease": True, "make_latest": "false"})
    keep = set(files)
    if previous:
        keep.update(f["name"] for profile in previous["profiles"].values() for f in profile)
    for name, asset in assets.items():
        if name.startswith(("network-", "cosmetic-")) and name.endswith(".json") and name not in keep:
            github.request(f"/releases/assets/{asset['id']}", method="DELETE")
    print("Published filter revision " + manifest["revision"] + "; app releases unchanged.")


if __name__ == "__main__":
    import os
    parser = argparse.ArgumentParser(); parser.add_argument("--directory", default="build/filter-data")
    args = parser.parse_args()
    publish_filters(GitHub(repo="koyuuuuu/personal-browser-distribution", token=os.environ["DISTRIBUTION_TOKEN"]), args.directory)
