import json
import unittest
from pathlib import Path
from distribution import BUNDLE_ID, build_number, release_config, release_tag
from publish_release import canonical_source_commit

ROOT = Path(__file__).resolve().parents[1]

class PublicMigrationTests(unittest.TestCase):
    def test_new_workflow_counter_cannot_reset_delivered_build_numbers(self):
        self.assertEqual(build_number(ROOT, '1'), '1001')
        self.assertEqual(build_number(ROOT, '2'), '1002')
        for value in ['0', '-1', 'bad']:
            with self.assertRaises(ValueError): build_number(ROOT, value)
        self.assertEqual(release_config(ROOT)['source_repository'], 'koyuuuuu/personal-browser-clean')

    def test_inherited_releases_match_the_verified_identity_migration(self):
        inherited = json.loads((ROOT/'distribution/inherited-releases.json').read_text())
        verified = json.loads((ROOT/'distribution/history-rewrite.json').read_text())['delivered_releases']
        self.assertEqual({r['tag'] for r in inherited}, {r['tag'] for r in verified})
        for info in inherited:
            original = next(r for r in verified if r['tag'] == info['tag'])
            self.assertEqual(info['bundle_id'], BUNDLE_ID)
            self.assertEqual(info['sha256'], original['ipa_sha256'])
            self.assertEqual(info['source_commit'], canonical_source_commit(original['original_source_commit']))
            self.assertEqual(release_tag(info), info['tag'])
