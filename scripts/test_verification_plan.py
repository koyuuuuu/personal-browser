import re
import unittest

from verification_plan import AREAS, ROOT, changed_methods, plan


class VerificationPolicyTests(unittest.TestCase):
    def test_ci_only_changes_never_boot_simulator_or_republish_app(self):
        result = plan(["scripts/verification_plan.py", ".github/workflows/ios.yml", "README.md"])
        self.assertEqual(result["ui_tests"], [])
        self.assertFalse(result["compatibility"])
        self.assertFalse(result["publish"])

    def test_tab_layout_change_selects_tab_checks_without_storage_roundtrip(self):
        result = plan(["App/TabGridView.swift"])
        self.assertEqual(result["ui_tests"], sorted(AREAS["tabs"]))
        self.assertFalse(result["compatibility"])
        self.assertFalse(result["verify_archives"])
        self.assertTrue(result["publish"])

    def test_store_scroll_change_does_not_trigger_storage_or_external_url_tests(self):
        before = "class Store {\n    func scrollChrome() { old() }\n    func flush() { save() }\n}\n"
        after = before.replace("old()", "new()")
        changed = changed_methods(before, after)
        self.assertEqual(changed, {"scrollChrome"})
        result = plan(["App/BrowserStore.swift"], changed)
        self.assertFalse(result["compatibility"])
        self.assertEqual(result["ui_tests"], sorted(AREAS["chrome"]))

    def test_storage_changes_require_rollback_compatibility(self):
        for path in ["Sources/BrowserCore/Models.swift", "Sources/BrowserCore/LibraryExtras.swift"]:
            self.assertTrue(plan([path])["compatibility"])
        self.assertTrue(plan(["App/BrowserStore.swift"], ["flush"])["compatibility"])
        self.assertTrue(plan(["App/BrowserStore.swift"], ["preamble"])["compatibility"])

    def test_media_only_change_does_not_run_misleading_audio_or_external_url_test(self):
        result = plan(["App/BrowserStore.swift"], ["applicationBackgrounded"])
        self.assertEqual(result["ui_tests"], [])
        self.assertFalse(result["compatibility"])

    def test_archive_audit_is_conditional_on_delivery_or_archive_changes(self):
        self.assertTrue(plan(["scripts/publish_release.py"])["verify_archives"])
        self.assertTrue(plan(["distribution/history-rewrite.json"])["verify_archives"])
        self.assertFalse(plan(["App/HomePageView.swift"])["verify_archives"])

    def test_external_os_delivery_only_selected_for_link_related_changes(self):
        external = "test00ExternalURLColdLaunchBackgroundAndInvalidInput"
        self.assertIn(external, plan(["App/PersonalBrowserApp.swift"])["ui_tests"])
        self.assertNotIn(external, plan(["App/HomePageView.swift"])["ui_tests"])

    def test_removed_and_overlapping_ui_checks_are_not_in_automatic_policy(self):
        selected = {name for group in AREAS.values() for name in group}
        actual = set(re.findall(r"func (test\w+)\(", (ROOT / "UITests/BrowserUITests.swift").read_text()))
        self.assertTrue(selected <= actual)
        self.assertNotIn("testAudioCanContinueInBackgroundWithoutPiP", selected)
        self.assertNotIn("testTabTileCanBeSwipedClosed", selected)
        self.assertNotIn("testAddressSwipeReturnsToPreviousTab", selected)

    def test_changed_ui_helpers_only_exercise_launch_instead_of_full_suite(self):
        result = plan(["UITests/BrowserUITests.swift"], ui_changes=["navigate"])
        self.assertEqual(result["ui_tests"], AREAS["launch"])


if __name__ == "__main__":
    unittest.main()
