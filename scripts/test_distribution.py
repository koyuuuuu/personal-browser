import copy
import hashlib
import json
import tempfile
import unittest
import urllib.request
from unittest.mock import patch
from pathlib import Path

from distribution import BUNDLE_ID, release_config, release_tag, source_document, verify_bytes
from publish_release import SafeRedirect, publish, publish_public_mirror, store_public_source


class DistributionTests(unittest.TestCase):
    def setUp(self):
        self.config = release_config(Path(__file__).resolve().parents[1])

    def record(self, version="0.2.0", build="7"):
        return {"bundle_id": BUNDLE_ID, "version": version, "build": build,
                "tag": release_tag({"version": version, "build": build}),
                "date": "2026-10-24T00:00:00Z", "size": 3,
                "sha256": hashlib.sha256(b"ipa").hexdigest(), "minimum_ios": "17.0",
                "data_schema": 1, "source_commit": "a" * 40,
                "appPermissions": {"entitlements": [], "privacy": {}}}

    def test_source_orders_versions_and_builds_numerically(self):
        records = [self.record("0.2.0", "7"), self.record("0.10.0", "8"), self.record("0.10.0", "10")]
        app = source_document(self.config, records)["apps"][0]
        self.assertEqual([(v["version"], v["buildVersion"]) for v in app["versions"]],
                         [("0.10.0", "10"), ("0.10.0", "8"), ("0.2.0", "7")])
        self.assertEqual(app["bundleIdentifier"], BUNDLE_ID)
        self.assertTrue(app["versions"][0]["downloadURL"].startswith("https://github.com/" + self.config["public_repository"] + "/releases/download/"))

    def test_duplicate_versions_and_identity_or_schema_changes_are_rejected(self):
        with self.assertRaises(ValueError):
            source_document(self.config, [self.record(), self.record()])
        for key, value in [("bundle_id", "other.browser"), ("data_schema", 2), ("tag", "../../app"), ("sha256", "bad")]:
            record = self.record(); record[key] = value
            with self.assertRaises(ValueError):
                source_document(self.config, [record])

    def test_asset_hash_and_size_must_both_match(self):
        verify_bytes(b"ipa", self.record())
        for data in [b"bad", b"ipaa"]:
            with self.assertRaises(ValueError):
                verify_bytes(data, self.record())

    def test_release_tags_reject_non_numeric_versions(self):
        for version in ["beta", "0.2", "01.2.0", "0.2.0/other"]:
            with self.assertRaises(ValueError):
                release_tag({"version": version, "build": "7"})

    def test_existing_published_release_is_not_overwritten(self):
        info = self.record()
        release = {"draft": False}

        class ExistingRelease:
            def request(self, path, **kwargs):
                self_kwargs = kwargs
                if self_kwargs.get("method", "GET") != "GET":
                    raise AssertionError("Published releases must not be mutated")
                return release

            def asset(self, release, name):
                return json.dumps(info).encode() if name == "build-info.json" else b"ipa"

        self.assertEqual(publish(ExistingRelease(), info, "unused"), info)
        changed = copy.deepcopy(info); changed["source_commit"] = "b" * 40
        with self.assertRaises(ValueError):
            publish(ExistingRelease(), changed, "unused")

    def test_redirect_does_not_forward_github_credentials_to_asset_cdn(self):
        request = urllib.request.Request("https://api.github.com/asset", headers={"Authorization": "Bearer test-only"})
        redirect = SafeRedirect().redirect_request(request, None, 302, "Found", {}, "https://cdn.example/file")
        self.assertIsNone(redirect.get_header("Authorization"))
        same_origin = SafeRedirect().redirect_request(request, None, 302, "Found", {}, "https://api.github.com/other")
        self.assertEqual(same_origin.get_header("Authorization"), "Bearer test-only")

    def test_public_mirror_refuses_private_repository(self):
        class PrivateRepository:
            repo = "koyuuuuu/personal-browser-distribution"
            def request(self, path, **kwargs):
                return {"private": True}
        with self.assertRaises(ValueError):
            publish_public_mirror(PrivateRepository(), [], "unused")

    def test_public_git_tree_contains_only_distribution_files(self):
        calls = []
        class PublicRepository:
            def request(self, path, **kwargs):
                calls.append((path, kwargs))
                if path == "/git/ref/heads/main": return None
                if path == "/git/blobs": return {"sha": "b" * 40}
                if path == "/git/trees": return {"sha": "c" * 40}
                if path == "/git/commits": return {"sha": "d" * 40}
                if path == "/git/refs": return {}
                raise AssertionError(path)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "source.json").write_text(json.dumps(source_document(self.config, [self.record()])))
            (root / "icon.png").write_bytes(b"png")
            store_public_source(PublicRepository(), root)
        tree = next(kwargs["body"]["tree"] for path, kwargs in calls if path == "/git/trees")
        self.assertEqual({entry["path"] for entry in tree}, {"source.json", "icon.png", "README.md"})
        self.assertNotIn("source_commit", json.dumps(tree))

    def test_new_public_source_is_advertised_only_after_release_asset_upload(self):
        events = []
        record = self.record()
        class PublicRepository:
            repo = "koyuuuuu/personal-browser-distribution"
            def request(self, path, **kwargs):
                if path == "": return {"private": False}
                if path == "/git/ref/heads/main": return {"object": {"sha": "e" * 40}}
                if path.startswith("/releases?"): return []
                if path == "/releases":
                    events.append("draft")
                    return {"id": 1, "assets": [], "upload_url": "https://uploads.github.com/example{?name}"}
                if path.startswith("https://uploads.github.com/"):
                    events.append("upload")
                    self_test = kwargs["body"]
                    if self_test != b"ipa": raise AssertionError("Unexpected public asset")
                    return {}
                if path == "/releases/1": events.append("publish"); return {}
                raise AssertionError(path)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); (root / "versions").mkdir()
            (root / "versions" / f"{record['tag']}.ipa").write_bytes(b"ipa")
            with patch("publish_release.store_public_source", side_effect=lambda *args, **kwargs: events.append("source")):
                publish_public_mirror(PublicRepository(), [record], root)
        self.assertEqual(events, ["draft", "upload", "publish", "source"])


if __name__ == "__main__":
    unittest.main()
