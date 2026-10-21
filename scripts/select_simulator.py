#!/usr/bin/env python3
"""Select an available iPhone Simulator from `simctl list devices -j`."""
import json
import argparse
import re
import sys


def select_device(data, sdk_version=None):
    sdk = tuple(map(int, sdk_version.split("."))) if sdk_version else None
    runtimes = []
    for runtime, devices in data.get("devices", {}).items():
        match = re.search(r"\.iOS-(\d+)-(\d+)(?:-(\d+))?$", runtime)
        if match is None:
            continue
        version = tuple(int(part or 0) for part in match.groups())
        if sdk is not None and version > (sdk + (0, 0))[:3]:
            continue
        runtimes.append((version, devices))
    for _, devices in sorted(runtimes, key=lambda item: item[0], reverse=True):
        for device in devices:
            if device.get("isAvailable") and device.get("name", "").startswith("iPhone"):
                return device["udid"]
    raise ValueError("No available iPhone Simulator compatible with the selected Xcode SDK.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--sdk-version", required=True)
    args = parser.parse_args()
    try:
        print(select_device(json.load(sys.stdin), args.sdk_version))
    except (ValueError, KeyError) as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)
