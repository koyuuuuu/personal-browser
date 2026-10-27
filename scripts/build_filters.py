#!/usr/bin/env python3
"""Convert licensed upstream lists with pinned Brave code; preserve exceptions across chunks."""
import argparse
import copy
import hashlib
import json
import subprocess
import urllib.request
import zipfile
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = "https://github.com/koyuuuuu/personal-browser-distribution/releases/download/filter-data-v1/"


def encode(value):
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True).encode()


def canonical_rules(rules):
    # Rust serializes trigger sets in hash order. Their values are unordered OR
    # conditions; normalize them so unchanged inputs do not cause daily updates.
    unique = {}
    for source in rules:
        rule = copy.deepcopy(source)
        for name, value in rule["trigger"].items():
            if isinstance(value, list): rule["trigger"][name] = sorted(set(value))
        unique[encode(rule)] = rule
    # split_rules places all exceptions after ordinary rules in every chunk.
    return [unique[key] for key in sorted(unique)]


def download(url):
    request = urllib.request.Request(url, headers={"User-Agent": "PersonalBrowser-filter-builder"})
    with urllib.request.urlopen(request, timeout=90) as response:
        data = response.read(20 * 1024 * 1024 + 1)
    if not data or len(data) > 20 * 1024 * 1024:
        raise ValueError("Upstream list is empty or too large")
    return data


def split_rules(rules, *, kind, standard=False, chunk_size=40000):
    exceptions = [r for r in rules if r["action"]["type"] == "ignore-previous-rules"]
    if kind == "cosmetic":
        # The converter's first-party document exception is for network rules;
        # applying it to cosmetics would cancel hiding on the top-level page.
        exceptions = [r for r in exceptions if r["trigger"].get("resource-type") != ["document"] or r["trigger"].get("load-type") != ["first-party"]]
    actions = []
    for original in rules:
        action = original["action"]["type"]
        if (kind == "cosmetic" and action != "css-display-none") or (kind == "network" and action not in {"block", "block-cookies"}):
            continue
        rule = copy.deepcopy(original)
        if standard and kind == "network":
            load = rule["trigger"].get("load-type")
            if load and "third-party" not in load:
                continue
            rule["trigger"]["load-type"] = ["third-party"]
        actions.append(rule)
    # Exceptions are list-local in WebKit. Repeat them in EACH chunk, in their
    # original order after blocking/hiding rules, rather than slicing blindly.
    if len(exceptions) >= chunk_size:
        raise ValueError("Too many exceptions for a content rule list")
    capacity = chunk_size - len(exceptions)
    return [actions[i:i + capacity] + exceptions for i in range(0, len(actions), capacity)]


def build(destination, converter, source_dir=None):
    destination = Path(destination); destination.mkdir(parents=True, exist_ok=True)
    config = json.loads((ROOT / "filters/sources.json").read_text())
    originals = destination / "originals"; originals.mkdir(exist_ok=True)
    sources = []
    for source in config["sources"]:
        data = (Path(source_dir) / (source["id"] + ".txt")).read_bytes() if source_dir else download(source["url"])
        data.decode("utf-8-sig")
        (originals / (source["id"] + ".txt")).write_bytes(data)
        sources.append({**source, "sha256": hashlib.sha256(data).hexdigest(), "size": len(data)})
    conversion = subprocess.run([str(converter), *[str(originals / (s["id"] + ".txt")) for s in sources]], capture_output=True, check=True)
    converted = json.loads(conversion.stdout)
    rules = canonical_rules(converted["rules"])
    if len(rules) < 1000:
        raise ValueError("Unexpectedly small converted filter set")
    payloads = {}
    def files(kind, standard=False):
        output = []
        for part in split_rules(rules, kind=kind, standard=standard):
            data = encode(part); sha = hashlib.sha256(data).hexdigest()
            name = kind + "-" + sha + ".json"
            payloads[name] = data
            output.append({"name": name, "sha256": sha, "size": len(data), "count": len(part), "kind": kind})
        return output
    cosmetic = files("cosmetic")
    profiles = {"standard": files("network", True) + cosmetic, "strong": files("network") + cosmetic}
    revision = hashlib.sha256(encode({"profiles": profiles, "sources": sources, "converter": config["converter"]})).hexdigest()
    for name, data in payloads.items():
        if len(data) > 12 * 1024 * 1024:
            raise ValueError("Rule chunk exceeds the supported client size")
        (destination / name).write_bytes(data)
    manifest = {"schema": 1, "revision": revision, "generatedAt": datetime.now(timezone.utc).isoformat(),
                "converter": config["converter"], "sources": sources, "profiles": profiles,
                "inputLines": converted["inputLines"], "convertedFilters": converted["convertedFilters"],
                "sourceArchive": "filter-sources-" + revision + ".zip"}
    notices = "Personal Browser filter data\n\nConverted/modified into WebKit network and cosmetic rule lists.\nConversion: Brave adblock-rust 0.13.3 (MPL-2.0). No Brave engine is linked into the app.\nSome advanced/scriptlet rules cannot be represented in WebKit and are omitted.\nEasyList/EasyPrivacy: GPL v3 option selected from their dual licence. Japanese filter: GPL v3.\nThis combined, separately distributed filter-data collection is GPL v3.\nNo warranty. See the bundled licence texts and original lists.\n\n"
    for s in sources:
        notices += f"{s['name']}\n{s['attribution']}\nSource: {s['url']}\nLicence: {s['license']}\n{s['licenseURL']}\n\n"
    notices += "Corresponding original lists, conversion script and licences:\n" + BASE + manifest["sourceArchive"] + "\n"
    (destination / "FilterNotices.txt").write_text(notices)
    licenses = ROOT / "filters/licenses"
    for path in licenses.glob("*.txt"):
        (destination / path.name).write_bytes(path.read_bytes())
    with zipfile.ZipFile(destination / manifest["sourceArchive"], "w", zipfile.ZIP_DEFLATED) as archive:
        for path in originals.glob("*.txt"): archive.write(path, "originals/" + path.name)
        for path in licenses.glob("*.txt"): archive.write(path, "licenses/" + path.name)
        for name in ["filters/sources.json", "scripts/build_filters.py", "tools/filter-converter/Cargo.toml", "tools/filter-converter/Cargo.lock", "tools/filter-converter/src/main.rs"]:
            archive.write(ROOT / name, name)
        archive.writestr("NOTICE.txt", notices)
    (destination / "manifest.json").write_bytes(encode(manifest))
    print(json.dumps({"revision": revision, "rules": len(rules), "convertedFilters": converted["convertedFilters"], "files": len(payloads)}, indent=2))
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--destination", default="build/filter-data")
    parser.add_argument("--converter", default="tools/filter-converter/target/release/personal-browser-filter-converter")
    parser.add_argument("--source-dir")
    args = parser.parse_args()
    build(args.destination, Path(args.converter).resolve(), args.source_dir)
