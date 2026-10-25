import json
import unittest
from pathlib import Path
from publish_release import canonical_source_commit

class HistoryRewriteTests(unittest.TestCase):
    def test_delivered_sources_have_explicit_id_mapping_and_immutable_digests(self):
        data=json.loads((Path(__file__).resolve().parents[1]/'distribution/history-rewrite.json').read_text())
        for release in data['delivered_releases']:
            self.assertEqual(canonical_source_commit(release['original_source_commit']),release['source_commit'])
            self.assertEqual(canonical_source_commit(release['source_commit']),release['source_commit'])
            self.assertRegex(release['ipa_sha256'],r'^[0-9a-f]{64}$')
            self.assertRegex(release['build_info_sha256'],r'^[0-9a-f]{64}$')
        self.assertEqual(canonical_source_commit('f'*40),'f'*40)
