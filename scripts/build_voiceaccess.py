"""Build and ad-hoc sign the standalone macOS companion fallback."""

import plistlib
import subprocess
from build_common import ADDIN, ROOT, VERSION, BUILD_TAG, ARCHITECTURE, MACOS_TARGET, require_macos

require_macos()
app = ADDIN / "_native/VoiceAccess.app/Contents"
(app / "MacOS").mkdir(parents=True, exist_ok=True)
(app / "Info.plist").write_bytes(plistlib.dumps({
    "CFBundleExecutable": "VoiceAccess", "CFBundleName": "VoiceAccess",
    "CFBundleDisplayName": "VoiceAccess", "CFBundleIdentifier": "com.robodk.voiceaccess.reader",
    "CFBundlePackageType": "APPL", "CFBundleShortVersionString": VERSION,
    "CFBundleVersion": BUILD_TAG, "LSMinimumSystemVersion": MACOS_TARGET,
    "NSHighResolutionCapable": True, "LSUIElement": True,
}))
build = ROOT / "build/standalone"
build.mkdir(parents=True, exist_ok=True)
output = build / "VoiceAccess"
subprocess.run([
    "xcrun", "swiftc", "-O", "-swift-version", "5",
    "-target", f"{ARCHITECTURE}-apple-macosx{MACOS_TARGET}", "-framework", "AppKit",
    *[str(ROOT / "native" / name) for name in (
        "Speech.swift", "Integration.swift", "StationOutline.swift", "VoiceAccess.swift")],
    "-o", str(output),
], check=True)
output.replace(app / "MacOS/VoiceAccess")
subprocess.run(["codesign", "--force", "--sign", "-", str(app.parent)], check=True)
print(app.parent)
