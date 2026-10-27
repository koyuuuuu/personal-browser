import hashlib
import json
import unittest
from pathlib import Path

from build_filters import ROOT, split_rules
from verification_plan import AREAS, plan


class FilterTests(unittest.TestCase):
    def test_exceptions_repeat_after_each_chunk(self):
        block = {"trigger": {"url-filter": "ads"}, "action": {"type": "block"}}
        exception = {"trigger": {"url-filter": "allowed"}, "action": {"type": "ignore-previous-rules"}}
        chunks = split_rules([block] * 5 + [exception], kind="network", chunk_size=3)
        self.assertEqual(len(chunks), 3)
        self.assertTrue(all(chunk[-1] == exception and len(chunk) <= 3 for chunk in chunks))

    def test_standard_limits_only_network_and_keeps_cosmetics(self):
        block = {"trigger": {"url-filter": "ads"}, "action": {"type": "block"}}
        hide = {"trigger": {"url-filter": ".*"}, "action": {"type": "css-display-none", "selector": ".ad"}}
        first_party_document = {"trigger": {"url-filter": ".*", "resource-type": ["document"], "load-type": ["first-party"]}, "action": {"type": "ignore-previous-rules"}}
        rules = [block, hide, first_party_document]
        self.assertEqual(split_rules(rules, kind="network", standard=True)[0][0]["trigger"]["load-type"], ["third-party"])
        self.assertEqual(split_rules(rules, kind="cosmetic")[0], [hide])
        self.assertNotIn("load-type", block["trigger"])

    def test_bundled_filters_have_exact_hashes_bounds_and_corresponding_source(self):
        root = ROOT / "App/FilterResources"
        manifest = json.loads((root / "manifest.json").read_text())
        self.assertEqual(manifest["schema"], 1)
        self.assertGreater(manifest["convertedFilters"], 1000)
        self.assertTrue((root / manifest["sourceArchive"]).is_file())
        self.assertTrue((root / "GPL-3.0.txt").is_file())
        seen = set()
        for files in manifest["profiles"].values():
            self.assertLessEqual(sum(f["size"] for f in files), 40 * 1024 * 1024)
            for file in files:
                if file["name"] in seen: continue
                seen.add(file["name"])
                data = (root / file["name"]).read_bytes()
                self.assertEqual(len(data), file["size"])
                self.assertEqual(hashlib.sha256(data).hexdigest(), file["sha256"])
                rules = json.loads(data)
                self.assertEqual(len(rules), file["count"])
                self.assertLessEqual(len(rules), 50000)

    def test_blocking_changes_do_not_run_unrelated_tls_or_external_url_cases(self):
        result = plan(["App/BrowserTab.swift"], tab_changes=["configureBlocking", "init"])
        self.assertEqual(result["ui_tests"], sorted(AREAS["blocking"] + AREAS["launch"]))
        self.assertFalse(result["compatibility"])


if __name__ == "__main__":
    unittest.main()
