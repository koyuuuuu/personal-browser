#!/usr/bin/env python3
"""Read-only checks for this project's thin arm64 iPhone IPA artifacts.

Uses only Python's standard library; works on Windows, Linux and macOS.
This does not validate Apple's signature or prove SideStore installation works.
"""

import argparse
import hashlib
import json
import plistlib
import re
import struct
import sys
import zipfile
from pathlib import Path, PurePosixPath


class InvalidIPA(ValueError):
    pass


def version_tuple(value):
    if not isinstance(value, str) or not re.fullmatch(r"\d+(?:\.\d+){0,2}", value):
        raise InvalidIPA(f"Invalid OS version: {value!r}")
    parts = tuple(int(part) for part in value.split("."))
    return parts + (0,) * (3 - len(parts))


def inspect_executable(data):
    if len(data) < 32 or data[:4] != b"\xcf\xfa\xed\xfe":
        raise InvalidIPA("Expected a thin, little-endian 64-bit Mach-O executable")
    _, cpu, _, file_type, count, command_bytes, _, _ = struct.unpack_from("<8I", data)
    if cpu != 0x0100000C or file_type != 2:
        raise InvalidIPA("Expected an arm64 application executable")
    end = 32 + command_bytes
    if end > len(data):
        raise InvalidIPA("Truncated Mach-O load commands")
    offset = 32
    platforms = []
    for _ in range(count):
        if offset + 8 > end:
            raise InvalidIPA("Truncated Mach-O load command")
        command, size = struct.unpack_from("<2I", data, offset)
        if size < 8 or offset + size > end:
            raise InvalidIPA("Invalid Mach-O load command size")
        if command == 0x32:  # LC_BUILD_VERSION
            if size < 24:
                raise InvalidIPA("Invalid LC_BUILD_VERSION")
            platforms.append(struct.unpack_from("<I", data, offset + 8)[0])
        offset += size
    if offset != end or platforms != [2]:  # PLATFORM_IOS; iOS Simulator is 7
        raise InvalidIPA("Expected iOS device platform 2, not a Simulator or other platform")
    return {"architecture": "arm64", "platform": "iOS device"}


def inspect_ipa(path, target_ios="18.4.1", bundle_id=None, unsigned=False):
    target_version = version_tuple(target_ios)
    path = Path(path)
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)):
            raise InvalidIPA("Duplicate ZIP entries")
        for name in names:
            parts = PurePosixPath(name).parts
            if name.startswith("/") or "\\" in name or ".." in parts:
                raise InvalidIPA("Unsafe archive path")
        roots = {
            parts[1]
            for name in names
            if len(parts := PurePosixPath(name).parts) >= 2
            and parts[0] == "Payload"
            and parts[1].endswith(".app")
        }
        if len(roots) != 1:
            raise InvalidIPA("Expected exactly one application inside Payload/")
        app = "Payload/" + roots.pop() + "/"
        if any(part.endswith(".appex") for name in names for part in PurePosixPath(name).parts):
            raise InvalidIPA("App extensions are excluded from the initial free-signing build")
        try:
            info = plistlib.loads(archive.read(app + "Info.plist"))
        except (KeyError, plistlib.InvalidFileException, ValueError) as exc:
            raise InvalidIPA("Missing or invalid application Info.plist") from exc
        if not isinstance(info, dict) or info.get("CFBundlePackageType") != "APPL":
            raise InvalidIPA("Expected an APPL bundle")
        identifier = info.get("CFBundleIdentifier")
        if not isinstance(identifier, str) or not re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", identifier):
            raise InvalidIPA("Missing or invalid bundle identifier")
        if bundle_id and identifier != bundle_id:
            raise InvalidIPA("Bundle identifier does not match the expected build")
        minimum = info.get("MinimumOSVersion")
        if version_tuple(minimum) > target_version:
            raise InvalidIPA(f"Build requires iOS {minimum}; target is {target_ios}")
        if "iPhoneOS" not in info.get("CFBundleSupportedPlatforms", []):
            raise InvalidIPA("Info.plist is not for iPhoneOS")
        if 1 not in info.get("UIDeviceFamily", []):
            raise InvalidIPA("Build does not support iPhone")
        executable = info.get("CFBundleExecutable")
        if not isinstance(executable, str) or not executable or "/" in executable or "\\" in executable or executable in {".", ".."}:
            raise InvalidIPA("Invalid application executable name")
        try:
            executable_info = archive.getinfo(app + executable)
            if not (executable_info.external_attr >> 16) & 0o111:
                raise InvalidIPA("Application executable has lost its UNIX executable permission")
            binary = archive.read(executable_info)
        except KeyError as exc:
            raise InvalidIPA("Application executable is missing") from exc
        machine = inspect_executable(binary)
        profile = app + "embedded.mobileprovision" in names
        signature = any(name.startswith(app + "_CodeSignature/") for name in names)
        if unsigned and (profile or signature):
            raise InvalidIPA("Expected unsigned CI output, but found a profile or signature resources")
        # CRC checks cover other files as well as the executable/plist read above.
        if archive.testzip() is not None:
            raise InvalidIPA("Corrupted ZIP member")
    with path.open("rb") as artifact:
        digest = hashlib.file_digest(artifact, "sha256").hexdigest()
    return {
        "file": path.name,
        "sha256": digest,
        "bundle_id": identifier,
        "version": info.get("CFBundleShortVersionString"),
        "build": info.get("CFBundleVersion"),
        "minimum_ios": minimum,
        "target_ios": target_ios,
        **machine,
        "embedded_profile": profile,
        "signature_resources": signature,
        "installation_verified": False,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ipa", type=Path)
    parser.add_argument("--target-ios", default="18.4.1")
    parser.add_argument("--bundle-id")
    parser.add_argument("--unsigned", action="store_true")
    args = parser.parse_args()
    try:
        result = inspect_ipa(args.ipa, args.target_ios, args.bundle_id, args.unsigned)
    except (InvalidIPA, OSError, zipfile.BadZipFile, RuntimeError, struct.error) as exc:
        print(f"IPA check failed: {exc}", file=sys.stderr)
        return 1
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
