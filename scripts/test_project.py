import plistlib
import unittest
import xml.etree.ElementTree as ET

from generate_project import ROOT, generate
from select_simulator import select_device


class ProjectTests(unittest.TestCase):
    def test_generated_files_match_checkout(self):
        for path, content in generate().items():
            self.assertEqual(path.read_text(encoding="utf-8"), content, str(path))

    def test_scheme_targets_ui_tests_and_application(self):
        scheme = next(content for path, content in generate().items() if path.suffix == ".xcscheme")
        root = ET.fromstring(scheme)
        tested = root.find("TestAction/Testables/TestableReference/BuildableReference")
        self.assertEqual(tested.attrib["BlueprintName"], "PersonalBrowserUITests")
        launched = root.find("LaunchAction/BuildableProductRunnable/BuildableReference")
        self.assertEqual(launched.attrib["BlueprintName"], "PersonalBrowser")

    def test_plist_has_no_browser_or_shared_container_entitlements(self):
        with (ROOT / "App/Info.plist").open("rb") as file:
            info = plistlib.load(file)
        self.assertNotIn("WKAppBoundDomains", info)
        self.assertEqual([scheme for item in info["CFBundleURLTypes"] for scheme in item["CFBundleURLSchemes"]], ["mybrowser"])
        self.assertEqual(info["CFBundlePackageType"], "APPL")
        self.assertTrue(info["NSAppTransportSecurity"]["NSAllowsArbitraryLoadsInWebContent"])
        self.assertNotIn("NSAllowsArbitraryLoads", info["NSAppTransportSecurity"])

    def test_available_iphone_is_selected_without_hardcoded_model(self):
        data = {"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-18-4": [
            {"name": "iPhone 12", "isAvailable": False, "udid": "old"},
            {"name": "iPad Pro", "isAvailable": True, "udid": "tablet"},
            {"name": "iPhone 16", "isAvailable": True, "udid": "phone"}
        ]}}
        self.assertEqual(select_device(data), "phone")

    def test_no_available_device_is_reported(self):
        with self.assertRaises(ValueError):
            select_device({"devices": {}})

    def test_newer_runtime_than_xcode_sdk_is_excluded(self):
        def device(udid):
            return [{"name": "iPhone", "isAvailable": True, "udid": udid}]
        data = {"devices": {
            "com.apple.CoreSimulator.SimRuntime.iOS-26-2": device("unsupported"),
            "com.apple.CoreSimulator.SimRuntime.iOS-18-5": device("supported"),
            "com.apple.CoreSimulator.SimRuntime.iOS-18-4": device("older"),
        }}
        self.assertEqual(select_device(data, "18.5"), "supported")
        with self.assertRaises(ValueError):
            select_device(data, "17.0")

    def test_runtime_versions_sort_numerically(self):
        data = {"devices": {
            f"com.apple.CoreSimulator.SimRuntime.iOS-{version}": [
                {"name": "iPhone", "isAvailable": True, "udid": version}
            ] for version in ["9-3", "18-5", "18-10"]
        }}
        self.assertEqual(select_device(data, "18.10"), "18-10")


if __name__ == "__main__":
    unittest.main()
