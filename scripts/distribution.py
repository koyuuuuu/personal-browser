#!/usr/bin/env python3
"""Validate private releases and generate a public binary-only SideStore source."""
import hashlib
import json
import plistlib
import re
import zipfile
from datetime import datetime, timezone
from pathlib import Path

from inspect_ipa import inspect_ipa

BUNDLE_ID = "local.personalbrowser.app"
SOURCE_ID = "local.personalbrowser.source"
MAX_IPA_BYTES = 100 * 1024 * 1024


def release_config(root):
    config = json.loads((Path(root) / "distribution/release.json").read_text())
    version_key(config["version"])
    if config["bundle_id"] != BUNDLE_ID or config["data_schema"] != 1:
        raise ValueError("Bundle ID and data schema must remain compatible with v0.1.0")
    if not re.fullmatch(r"koyuuuuu/[A-Za-z0-9_.-]+", config["public_repository"]) or config["public_repository"] == "koyuuuuu/personal-browser":
        raise ValueError("A distinct public binary-only distribution repository is required")
    source = config.get("source_repository", "koyuuuuu/personal-browser")
    if source not in ["koyuuuuu/personal-browser", "koyuuuuu/personal-browser-public", "koyuuuuu/personal-browser-clean"] or source == config["public_repository"]:
        raise ValueError("Unexpected source repository")
    return config


def build_number(root, run_number):
    offset = release_config(root).get("build_number_offset", 0)
    if type(offset) is not int or offset < 0 or not str(run_number).isdigit() or int(run_number) < 1:
        raise ValueError("Invalid workflow build number")
    return str(offset + int(run_number))


def version_key(version):
    if not isinstance(version, str) or not re.fullmatch(r"(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)", version):
        raise ValueError("Expected a three-component numeric marketing version")
    return tuple(map(int, version.split(".")))


def release_tag(info):
    version_key(info["version"])
    build = str(info["build"])
    if not re.fullmatch(r"[1-9]\d*", build):
        raise ValueError("Build number must be a positive integer")
    return f"v{info['version']}-build.{build}"


def inspect_release(ipa, root, source_commit, build_number):
    config = release_config(root)
    info = inspect_ipa(ipa, "18.4.1", BUNDLE_ID, unsigned=True)
    if info["version"] != config["version"] or info["build"] != str(build_number):
        raise ValueError("IPA version/build does not match release configuration")
    if not re.fullmatch(r"[0-9a-f]{40}", source_commit):
        raise ValueError("A complete source commit SHA is required")
    size = Path(ipa).stat().st_size
    if size > MAX_IPA_BYTES:
        raise ValueError("IPA exceeds the configured delivery file-size limit")
    with zipfile.ZipFile(ipa) as archive:
        name = next(n for n in archive.namelist() if re.fullmatch(r"Payload/[^/]+\.app/Info\.plist", n))
        plist = plistlib.loads(archive.read(name))
    info.update(source_commit=source_commit, data_schema=1, size=size,
                date=datetime.now(timezone.utc).isoformat(),
                description=config["release_notes"],
                appPermissions={"entitlements": [], "privacy": {
                    key: value for key, value in plist.items() if key.endswith("UsageDescription")
                }})
    info["tag"] = release_tag(info)
    return info


def source_document(config, records):
    if not records:
        raise ValueError("At least one verified release is required")
    seen = set()
    for record in records:
        version_key(record["version"])
        if record.get("bundle_id") != BUNDLE_ID or record.get("data_schema", 1) != 1:
            raise ValueError("Incompatible release identity or data format")
        identity = (record["version"], str(record["build"]))
        if identity in seen:
            raise ValueError("Duplicate version/build")
        seen.add(identity)
        if not re.fullmatch(r"v[0-9.]+(?:-build\.[1-9]\d*)?", record["tag"]):
            raise ValueError("Invalid release tag")
        if not re.fullmatch(r"[0-9a-f]{64}", record["sha256"]):
            raise ValueError("Invalid IPA checksum")
        if not isinstance(record["size"], int) or not 0 < record["size"] <= MAX_IPA_BYTES:
            raise ValueError("Invalid IPA size")
    records = sorted(records, key=lambda r: (version_key(r["version"]), int(r["build"])), reverse=True)
    versions = [{
        "version": r["version"], "buildVersion": str(r["build"]), "date": r["date"],
        "localizedDescription": r.get("description", ""),
        "downloadURL": f"https://github.com/{config['public_repository']}/releases/download/{r['tag']}/PersonalBrowser.ipa",
        "size": r["size"], "minOSVersion": r["minimum_ios"], "sha256": r["sha256"],
    } for r in records]
    return {
        "name": "Personal Browser", "identifier": SOURCE_ID,
        "subtitle": "個人用ブラウザの配信ソース", "tintColor": "#2675D9",
        "apps": [{
            "name": config["name"], "bundleIdentifier": BUNDLE_ID,
            "developerName": config["developer_name"],
            "localizedDescription": config["description"],
            "iconURL": f"https://raw.githubusercontent.com/{config['public_repository']}/main/icon.png", "versions": versions,
            "appPermissions": records[0]["appPermissions"],
        }], "news": [],
    }


def write_assets(root, records, destination):
    root, destination = Path(root), Path(destination)
    destination.mkdir(parents=True, exist_ok=True)
    source = source_document(release_config(root), records)
    (destination / "source.json").write_text(json.dumps(source, ensure_ascii=False, indent=2) + "\n")
    (destination / "manifest.json").write_text(json.dumps({"releases": records}, ensure_ascii=False, indent=2) + "\n")
    (destination / "icon.png").write_bytes((root / "App/Assets.xcassets/AppIcon.appiconset/AppIcon.png").read_bytes())
    return source


def verify_bytes(data, record):
    if len(data) != record["size"] or hashlib.sha256(data).hexdigest() != record["sha256"]:
        raise ValueError("Release asset size/checksum differs from its immutable build record")
