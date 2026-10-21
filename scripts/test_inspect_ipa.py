"""Synthetic artifact tests, not an actual iOS build or installation test."""

import plistlib
import struct
import tempfile
import unittest
import zipfile
from pathlib import Path

from inspect_ipa import InvalidIPA, inspect_executable, inspect_ipa


def macho(cpu=0x0100000C, platform=2):
    command = struct.pack("<6I", 0x32, 24, platform, 0x00120000, 0x00120000, 0)
    return struct.pack("<8I", 0xFEEDFACF, cpu, 0, 2, 1, len(command), 0, 0) + command


class ArtifactTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / "test.ipa"

    def fixture(self, binary=None, updates=None, extras=None, executable_mode=0o100755):
        info = {
            "CFBundleIdentifier": "local.example.browser",
            "CFBundleExecutable": "Browser",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "0.1.0",
            "CFBundleVersion": "1",
            "MinimumOSVersion": "18.0",
            "CFBundleSupportedPlatforms": ["iPhoneOS"],
            "UIDeviceFamily": [1, 2],
        }
        info.update(updates or {})
        with zipfile.ZipFile(self.path, "w") as archive:
            archive.writestr("Payload/Browser.app/Info.plist", plistlib.dumps(info))
            member = zipfile.ZipInfo("Payload/Browser.app/Browser")
            member.create_system = 3
            member.external_attr = executable_mode << 16
            archive.writestr(member, binary if binary is not None else macho())
            for name, content in (extras or {}).items():
                archive.writestr(name, content)

    def test_device_artifact_reports_hash_and_not_installation(self):
        self.fixture()
        result = inspect_ipa(self.path, bundle_id="local.example.browser", unsigned=True)
        self.assertEqual(result["architecture"], "arm64")
        self.assertEqual(len(result["sha256"]), 64)
        self.assertFalse(result["installation_verified"])

    def test_arm64_simulator_is_not_a_device_build(self):
        self.fixture(binary=macho(platform=7))
        with self.assertRaisesRegex(InvalidIPA, "platform"):
            inspect_ipa(self.path)

    def test_x86_simulator_is_rejected(self):
        self.fixture(binary=macho(cpu=0x01000007))
        with self.assertRaisesRegex(InvalidIPA, "arm64"):
            inspect_ipa(self.path)

    def test_newer_minimum_os_is_rejected(self):
        self.fixture(updates={"MinimumOSVersion": "18.5"})
        with self.assertRaisesRegex(InvalidIPA, "requires iOS"):
            inspect_ipa(self.path)

    def test_three_component_os_comparison(self):
        self.fixture(updates={"MinimumOSVersion": "18.4.1"})
        inspect_ipa(self.path)
        with self.assertRaisesRegex(InvalidIPA, "requires iOS"):
            inspect_ipa(self.path, target_ios="18.4")

    def test_app_extension_is_rejected(self):
        self.fixture(extras={"Payload/Browser.app/PlugIns/Widget.appex/Info.plist": b""})
        with self.assertRaisesRegex(InvalidIPA, "extensions"):
            inspect_ipa(self.path)

    def test_multiple_apps_are_rejected(self):
        self.fixture(extras={"Payload/Other.app/Info.plist": b""})
        with self.assertRaisesRegex(InvalidIPA, "exactly one"):
            inspect_ipa(self.path)

    def test_signed_output_is_rejected_only_in_unsigned_mode(self):
        self.fixture(extras={"Payload/Browser.app/embedded.mobileprovision": b"fixture"})
        inspect_ipa(self.path)
        with self.assertRaisesRegex(InvalidIPA, "unsigned"):
            inspect_ipa(self.path, unsigned=True)

    def test_executable_permissions_are_checked(self):
        self.fixture(executable_mode=0o100644)
        with self.assertRaisesRegex(InvalidIPA, "permission"):
            inspect_ipa(self.path)

    def test_wrong_bundle_identifier_is_rejected(self):
        self.fixture()
        with self.assertRaisesRegex(InvalidIPA, "identifier"):
            inspect_ipa(self.path, bundle_id="local.other.browser")

    def test_path_traversal_is_rejected_without_extracting(self):
        self.fixture(extras={"Payload/../escape": b"fixture"})
        with self.assertRaisesRegex(InvalidIPA, "Unsafe"):
            inspect_ipa(self.path)

    def test_missing_minimum_os_is_rejected(self):
        self.fixture(updates={"MinimumOSVersion": "unknown"})
        with self.assertRaisesRegex(InvalidIPA, "OS version"):
            inspect_ipa(self.path)

    def test_corrupt_macho_command_is_rejected(self):
        with self.assertRaisesRegex(InvalidIPA, "Truncated"):
            inspect_executable(macho()[:-1])


if __name__ == "__main__":
    unittest.main()
