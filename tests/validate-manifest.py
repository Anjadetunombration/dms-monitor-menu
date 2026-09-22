#!/usr/bin/env python3
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
REQUIRED_FILES = (
    "CHANGELOG.md",
    "LICENSE",
    "MonitorMenu.qml",
    "MonitorMenuSettings.qml",
    "README.md",
    "components/DisplayModes.qml",
    "components/MonitorBarPill.qml",
    "components/MonitorMenuPopout.qml",
    "components/NetworkMode.qml",
    "components/PhysicalDisplays.qml",
    "components/PrivateLan.qml",
    "components/VirtualMonitor.qml",
    "docs/RELEASE_CHECKLIST.md",
    "docs/screenshot.png",
    "install.sh",
    "mirror-helper.sh",
    "network-helper.sh",
    "plugin.json",
    "setup-network.sh",
    "setup-vkms.sh",
    "virtual-monitor-helper.sh",
    "vkms-helper.sh",
    "tests/test-helpers.sh",
)


missing = [name for name in REQUIRED_FILES if not (ROOT / name).is_file()]
if missing:
    raise SystemExit("missing required files: " + ", ".join(missing))

with (ROOT / "plugin.json").open(encoding="utf-8") as handle:
    manifest = json.load(handle)

expected = {
    "id": "monitorMenu",
    "type": "widget",
    "component": "./MonitorMenu.qml",
    "settings": "./MonitorMenuSettings.qml",
}
for key, value in expected.items():
    if manifest.get(key) != value:
        raise SystemExit(
            f"plugin.json: expected {key}={value!r}, got {manifest.get(key)!r}"
        )

for key in ("component", "settings"):
    if not (ROOT / manifest[key]).is_file():
        raise SystemExit(f"plugin.json: {key} does not exist: {manifest[key]}")

if "dankbar-widget" not in manifest.get("capabilities", []):
    raise SystemExit("plugin.json: missing dankbar-widget capability")
if "process" not in manifest.get("permissions", []):
    raise SystemExit("plugin.json: missing process permission")

print("manifest validation passed")
