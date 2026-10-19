"""Build the in-process macOS dock with a Qt SDK matching the RoboDK host."""

import os
from pathlib import Path
import shutil
import subprocess
from build_common import (
    ROOT, ADDIN, VERSION, BUILD_TAG, DOCK_LIBRARY, NATIVE_LIBRARY,
    ARCHITECTURE, MACOS_TARGET, QT_VERSION, require_macos,
)

require_macos()
qt = os.environ.get("VOICEACCESS_QT")
qmake = str(Path(qt) / "bin/qmake") if qt else shutil.which("qmake")
if not qmake:
    raise SystemExit("Set VOICEACCESS_QT to the matching Qt SDK directory (containing bin/qmake).")
qt_version = subprocess.check_output([qmake, "-query", "QT_VERSION"], text=True).strip()
if qt_version != QT_VERSION:
    raise SystemExit(f"This build targets Qt {QT_VERSION}; qmake reports {qt_version}. Set VOICEACCESS_QT.")
output = ADDIN / "_dock"
output.mkdir(parents=True, exist_ok=True)
build = ROOT / "build/native-dock"
build.mkdir(parents=True, exist_ok=True)
(build / "VoiceAccessBuild.h").write_text(
    f'#define VOICEACCESS_VERSION "{VERSION}"\n'
    f'#define VOICEACCESS_NATIVE_LIBRARY "{NATIVE_LIBRARY}"\n'
)
native_output = build / NATIVE_LIBRARY
subprocess.run([
    "xcrun", "swiftc", "-O", "-swift-version", "5", "-DVOICEACCESS_DOCK",
    "-target", f"{ARCHITECTURE}-apple-macosx{MACOS_TARGET}",
    "-emit-library", "-module-name", f"VoiceAccessDockNative{BUILD_TAG}", "-framework", "AppKit",
    "-Xlinker", "-install_name", "-Xlinker", f"@rpath/{NATIVE_LIBRARY}",
    *[str(ROOT / "native" / name) for name in (
        "Speech.swift", "Integration.swift", "StationOutline.swift", "VoiceAccess.swift", "dock/DockExports.swift")],
    "-o", str(native_output),
], check=True)
subprocess.run(["codesign", "--force", "--sign", "-", str(native_output)], check=True)
native_output.replace(output / NATIVE_LIBRARY)
subprocess.run([
    qmake, str(ROOT / "native/dock/voiceaccessdock.pro"), f"DESTDIR={output}",
    f"VOICEACCESS_BUILD_TAG={BUILD_TAG}", f"QMAKE_APPLE_DEVICE_ARCHS={ARCHITECTURE}",
], cwd=build, check=True)
subprocess.run(["make", "-j4"], cwd=build, check=True)
# The host already supplies Qt. Do not publish the developer's Qt install path.
qt_lib = subprocess.check_output([qmake, "-query", "QT_INSTALL_LIBS"], text=True).strip()
commands = subprocess.check_output(["otool", "-l", str(output / DOCK_LIBRARY)], text=True)
if f"path {qt_lib} (offset" in commands:
    subprocess.run(["install_name_tool", "-delete_rpath", qt_lib, str(output / DOCK_LIBRARY)], check=True)
subprocess.run(["install_name_tool", "-id", f"@rpath/{DOCK_LIBRARY}", str(output / DOCK_LIBRARY)], check=True)
subprocess.run(["codesign", "--force", "--sign", "-", str(output / DOCK_LIBRARY)], check=True)
(output / "ENABLED").write_text(f"VoiceAccess {VERSION}: macOS {ARCHITECTURE}, Qt {QT_VERSION}\n")
print(output)
