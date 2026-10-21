#!/usr/bin/env python3
"""Select an available iPhone Simulator from `simctl list devices -j`."""
import json
import sys


def select_device(data):
    for runtime, devices in sorted(data.get("devices", {}).items(), reverse=True):
        if ".iOS-" not in runtime:
            continue
        for device in devices:
            if device.get("isAvailable") and device.get("name", "").startswith("iPhone"):
                return device["udid"]
    raise ValueError("No available iPhone Simulator; inspect the runner's installed runtimes.")


if __name__ == "__main__":
    try:
        print(select_device(json.load(sys.stdin)))
    except (ValueError, KeyError) as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)
