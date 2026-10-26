#!/usr/bin/env python3
"""Publish source-repository releases using the workflow's ephemeral GITHUB_TOKEN.

Run only inside the contents:write CI job. Source-repository publishing uses the job token;
the optional public mirror uses DISTRIBUTION_TOKEN scoped only to its public repo.
"""
import argparse
import base64
import hashlib
import json
import os
import re
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

from distribution import BUNDLE_ID, inspect_release, release_config, release_tag, verify_bytes, version_key, write_assets

ROOT = Path(__file__).resolve().parents[1]
LEGACY_IPA_BLOB = "146a48247f1e95119ff40332f46aa369635266dc"
LEGACY_SOURCE = "12f15dbe922d7d6f7a5de86345b2d5ee2d2b346f"


class SafeRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, newurl):
        redirected = super().redirect_request(request, fp, code, message, headers, newurl)
        if redirected and urllib.parse.urlparse(request.full_url).netloc != urllib.parse.urlparse(newurl).netloc:
            redirected.remove_header("Authorization")
        return redirected


class GitHub:
    def __init__(self, repo=None, token=None):
        self.repo = repo or os.environ["GITHUB_REPOSITORY"]
        if not self.repo.startswith("koyuuuuu/"):
            raise ValueError("Publication is restricted to the established owner")
        self.token = token or os.environ["GITHUB_TOKEN"]
        self.opener = urllib.request.build_opener(SafeRedirect())

    def request(self, path, *, method="GET", body=None, binary=False, allow_missing=False):
        url = path if path.startswith("https://") else f"https://api.github.com/repos/{self.repo}{path}"
        if urllib.parse.urlparse(url).hostname not in {"api.github.com", "uploads.github.com"}:
            raise ValueError("Unsupported GitHub endpoint")
        headers = {"Authorization": f"Bearer {self.token}", "User-Agent": "PersonalBrowser-CI",
                   "Accept": "application/octet-stream" if binary else "application/vnd.github+json",
                   "X-GitHub-Api-Version": "2022-11-28"}
        if isinstance(body, bytes):
            headers["Content-Type"] = "application/octet-stream"
            encoded = body
        elif body is not None:
            headers["Content-Type"] = "application/json"
            encoded = json.dumps(body).encode()
        else:
            encoded = None
        try:
            with self.opener.open(urllib.request.Request(url, data=encoded, headers=headers, method=method), timeout=90) as response:
                data = response.read()
                return data if binary else (json.loads(data) if data else None)
        except urllib.error.HTTPError as exc:
            if exc.code == 404 and allow_missing:
                return None
            # Do not print request headers, credentials, or signed redirect URLs.
            raise RuntimeError(f"GitHub request failed (HTTP {exc.code})") from None

    def asset(self, release, name):
        asset = next((a for a in release["assets"] if a["name"] == name), None)
        if asset is None:
            raise ValueError(f"Missing immutable release asset: {name}")
        return self.request(f"/releases/assets/{asset['id']}", binary=True)


def canonical_source_commit(commit):
    # Original build-info/IPA assets remain immutable. Only explicitly recorded
    # identity-only rewrites are equivalent when verifying an old release.
    path = ROOT / "distribution/history-rewrite.json"
    if not path.exists():
        return commit
    mapping = json.loads(path.read_text())["commits"]
    return mapping.get(commit, commit)


def publish(github, info, ipa):
    tag = info["tag"]
    existing = github.request(f"/releases/tags/{tag}", allow_missing=True)
    if existing is None:
        existing = next((release for release in all_releases(github) if release["tag_name"] == tag), None)
    if existing and not existing["draft"]:
        previous = json.loads(github.asset(existing, "build-info.json"))
        if canonical_source_commit(previous["source_commit"]) != canonical_source_commit(info["source_commit"]):
            raise ValueError("A published version already points to different source; never overwrite it")
        original = github.asset(existing, "PersonalBrowser.ipa")
        verify_bytes(original, previous)
        if Path(ipa).is_file():
            Path(ipa).write_bytes(original)
        return previous
    release = existing or github.request("/releases", method="POST", body={
        "tag_name": tag, "target_commitish": info["source_commit"],
        "name": f"PersonalBrowser {info['version']} (build {info['build']})",
        "body": info["description"] + f"\n\nSource: `{info['source_commit']}`\nData schema: 1\nUnsigned arm64 IPA; keep the existing app and update via SideStore.",
        "draft": True, "prerelease": False,
    })
    if release["target_commitish"] != info["source_commit"]:
        raise ValueError("Draft source commit mismatch")
    # Partial drafts are not distributed; resuming the same build is safe.
    for asset in release["assets"]:
        github.request(f"/releases/assets/{asset['id']}", method="DELETE")
    metadata = (json.dumps(info, ensure_ascii=False, indent=2) + "\n").encode()
    checksums = (f"{info['sha256']}  PersonalBrowser.ipa\n"
                 f"{hashlib.sha256(metadata).hexdigest()}  build-info.json\n").encode()
    for name, data in [("PersonalBrowser.ipa", Path(ipa).read_bytes()), ("build-info.json", metadata), ("SHA256SUMS.txt", checksums)]:
        url = release["upload_url"].split("{")[0] + "?" + urllib.parse.urlencode({"name": name})
        github.request(url, method="POST", body=data)
    github.request(f"/releases/{release['id']}", method="PATCH", body={"draft": False})
    return info


def all_releases(github):
    releases = []
    for page in range(1, 11):
        batch = github.request(f"/releases?per_page=100&page={page}")
        releases.extend(batch)
        if len(batch) < 100:
            return releases
    raise ValueError("Release pagination limit exceeded; review retention before continuing")


def download_record(github, record):
    """Fetch a retained IPA only for new delivery, latest verification, or an archive audit."""
    if record["tag"] == "v0.1.0":
        blob = github.request(f"/git/blobs/{LEGACY_IPA_BLOB}")
        return base64.b64decode(blob["content"])
    release = github.request(f"/releases/tags/{record['tag']}")
    return github.asset(release, "PersonalBrowser.ipa")


def prepare_delivery(github, releases, destination, *, verify_archives=False):
    destination = Path(destination)
    ipa_dir = destination / "versions"
    ipa_dir.mkdir(parents=True, exist_ok=True)
    records = []
    for release in releases:
        if release["draft"] or release["prerelease"] or not re.fullmatch(r"v\d+\.\d+\.\d+-build\.[1-9]\d*", release["tag_name"]):
            continue
        info = json.loads(github.asset(release, "build-info.json"))
        if info["bundle_id"] != BUNDLE_ID or info.get("data_schema") != 1:
            raise ValueError("A release changed the app identity or persistence format")
        if info.get("tag") != release["tag_name"] or release_tag(info) != info["tag"]:
            raise ValueError("A release asset does not match its version tag")
        records.append(info)
    # Retain the already installed initial version as an explicit rollback entry.
    legacy = json.loads((ROOT / "docs/validation-2026-10-22.json").read_text())["artifact"]
    legacy.update(tag="v0.1.0", data_schema=1, size=legacy["ipa_bytes"],
                  date="2026-10-22T01:17:49Z", source_commit=LEGACY_SOURCE,
                  description="初期版。最新のschema 1の履歴・ブックマークをそのまま使用します。",
                  appPermissions=records[0]["appPermissions"] if records else {"entitlements": [], "privacy": {}})
    records.append(legacy)
    if len(records) > 100:
        raise ValueError("More than 100 retained releases: review free distribution limits")
    latest = max(records, key=lambda r: (version_key(r["version"]), int(r["build"])))
    for info in records:
        if verify_archives or info["tag"] == latest["tag"]:
            data = download_record(github, info)
            verify_bytes(data, info)
            (ipa_dir / f"{info['tag']}.ipa").write_bytes(data)
    write_assets(ROOT, records, destination)
    return records


def store_private_source(github, destination):
    # Only derived, non-secret source metadata is committed. IPA files live in
    # private Release assets and the approved public binary mirror, not in main.
    ref = github.request("/git/ref/heads/distribution", allow_missing=True)
    previous = github.request(f"/git/commits/{ref['object']['sha']}") if ref else None
    entries = [{"path": name, "mode": "100644", "type": "blob", "content": (Path(destination) / name).read_text()}
               for name in ["source.json", "manifest.json"]]
    tree = github.request("/git/trees", method="POST", body={"tree": entries})
    commit = github.request("/git/commits", method="POST", body={
        "message": "Update private SideStore source from verified releases",
        "tree": tree["sha"], "parents": [previous["sha"]] if previous else [],
        "author": {"name": "koyuuuuu", "email": "266257694+koyuuuuu@users.noreply.github.com"},
        "committer": {"name": "koyuuuuu", "email": "266257694+koyuuuuu@users.noreply.github.com"},
    })
    if ref:
        github.request("/git/refs/heads/distribution", method="PATCH", body={"sha": commit["sha"], "force": False})
    else:
        github.request("/git/refs", method="POST", body={"ref": "refs/heads/distribution", "sha": commit["sha"]})


def store_public_source(github, destination, *, include_source=True):
    """Only these three non-source files may enter the public repository tree."""
    destination = Path(destination)
    ref = github.request("/git/ref/heads/main", allow_missing=True)
    previous = github.request(f"/git/commits/{ref['object']['sha']}") if ref else None
    tree_entries = []
    if previous:
        old = github.request(f"/git/trees/{previous['tree']['sha']}?recursive=1")
        allowed = {"README.md", "source.json", "icon.png", "LICENSE", "LICENCE"}
        if old.get("truncated") or any(e["type"] == "blob" and e["path"] not in allowed for e in old["tree"]):
            raise ValueError("Public distribution repository contains unexpected files; do not overwrite it")
    for name in (["source.json", "icon.png"] if include_source else ["icon.png"]):
        blob = github.request("/git/blobs", method="POST", body={
            "content": base64.b64encode((destination / name).read_bytes()).decode(), "encoding": "base64"})
        tree_entries.append({"path": name, "mode": "100644", "type": "blob", "sha": blob["sha"]})
    tree_entries.append({"path": "README.md", "mode": "100644", "type": "blob", "content":
        "# Personal Browser distribution\n\nPublic unsigned IPAs, app icon, and a SideStore/AltStore Classic source. Application source code and on-device browsing data are not published here. Use the same Apple Account and app identity to update without deleting the installed app.\n"})
    body = {"tree": tree_entries}
    if previous:
        body["base_tree"] = previous["tree"]["sha"]
    tree = github.request("/git/trees", method="POST", body=body)
    commit = github.request("/git/commits", method="POST", body={
        "message": "Update SideStore distribution metadata", "tree": tree["sha"],
        "parents": [previous["sha"]] if previous else [],
        "author": {"name": "koyuuuuu", "email": "266257694+koyuuuuu@users.noreply.github.com"},
        "committer": {"name": "koyuuuuu", "email": "266257694+koyuuuuu@users.noreply.github.com"}})
    if ref:
        github.request("/git/refs/heads/main", method="PATCH", body={"sha": commit["sha"], "force": False})
    else:
        github.request("/git/refs", method="POST", body={"ref": "refs/heads/main", "sha": commit["sha"]})


def publish_public_mirror(github, records, destination, *, verify_archives=False, load_ipa=None):
    if github.repo == "koyuuuuu/personal-browser" or github.request("")["private"]:
        raise ValueError("Public binary mirror must be a separate public repository")
    ref = github.request("/git/ref/heads/main", allow_missing=True)
    if not ref:
        # Bootstrap only public metadata so Release tags can target a valid ref.
        store_public_source(github, destination, include_source=False)
    published = {r["tag_name"]: r for r in all_releases(github)}
    ordered = sorted(records, key=lambda r: (version_key(r["version"]), int(r["build"])))
    latest = ordered[-1]["tag"]
    for info in ordered:
        existing = published.get(info["tag"])
        if existing and not existing["draft"] and info["tag"] != latest and not verify_archives:
            asset = next((a for a in existing["assets"] if a["name"] == "PersonalBrowser.ipa"), None)
            if asset is None or asset["size"] != info["size"]:
                raise ValueError("Retained public IPA is missing or has changed size; archive audit required")
            continue
        path = Path(destination) / "versions" / f"{info['tag']}.ipa"
        data = path.read_bytes() if path.exists() else load_ipa(info) if load_ipa else None
        if data is None:
            raise ValueError("A missing public release requires its original IPA")
        verify_bytes(data, info)
        if existing and not existing["draft"]:
            verify_bytes(github.asset(existing, "PersonalBrowser.ipa"), info)
            continue
        release = existing or github.request("/releases", method="POST", body={
            "tag_name": info["tag"], "target_commitish": "main", "draft": True,
            "name": f"Personal Browser {info['version']} (build {info['build']})",
            "body": info.get("description", "") + "\n\nUpdate through SideStore without deleting the installed app. Unsigned arm64 IPA; personal signing required.",
        })
        # Public notes deliberately omit private commit SHAs, repository URLs,
        # build logs, source archives, and any authentication information.
        for asset in release["assets"]:
            github.request(f"/releases/assets/{asset['id']}", method="DELETE")
        url = release["upload_url"].split("{")[0] + "?name=PersonalBrowser.ipa"
        github.request(url, method="POST", body=data)
        github.request(f"/releases/{release['id']}", method="PATCH", body={
            "draft": False, "make_latest": "true" if info["tag"] == latest else "false"})
    # Advertise a version only after every referenced IPA is available.
    store_public_source(github, destination)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--ipa", default="dist/PersonalBrowser.ipa")
    parser.add_argument("--assets", default="dist/distribution")
    args = parser.parse_args()
    github = GitHub()
    if github.repo != "koyuuuuu/personal-browser":
        raise ValueError("The build must run in the established source repository")
    info = inspect_release(args.ipa, ROOT, os.environ["GITHUB_SHA"], os.environ["GITHUB_RUN_NUMBER"])
    info = publish(github, info, args.ipa)
    (ROOT / "dist/build-info.json").write_text(json.dumps(info, ensure_ascii=False, indent=2) + "\n")
    verify_archives = os.environ.get("VERIFY_ARCHIVES", "false") == "true"
    records = prepare_delivery(github, all_releases(github), args.assets, verify_archives=verify_archives)
    store_private_source(github, args.assets)
    print(f"Published release {info['tag']}; generated source with {len(records)} versions.")
    distribution_token = os.environ.get("DISTRIBUTION_TOKEN")
    if distribution_token:
        public = GitHub(repo=release_config(ROOT)["public_repository"], token=distribution_token)
        publish_public_mirror(public, records, args.assets, verify_archives=verify_archives,
                              load_ipa=lambda record: download_record(github, record))
        print(f"Public binary mirror and SideStore source updated: {public.repo}")
    else:
        print("::notice::Private Release/source are ready. Public distribution awaits one-time DISTRIBUTION_TOKEN setup.")


if __name__ == "__main__":
    main()
