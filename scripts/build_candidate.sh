#!/bin/bash
# Build a local candidate only; never upload or publish it.
set -euo pipefail
cd "$(dirname "$0")/.."
test "$(uname -s)" = Darwin || { echo "A macOS build host is required." >&2; exit 1; }
test "$(uname -m)" = x86_64 || { echo "This candidate procedure targets an Intel build host." >&2; exit 1; }
test -z "$(git status --porcelain)" || { echo "Use a clean checkout." >&2; exit 1; }
: "${VOICEACCESS_QT:?Set VOICEACCESS_QT to the Qt 6.10.1 SDK}"
export VOICEACCESS_ARCH=x86_64
PYTHON="${PYTHON:-python3}"
mkdir -p build/reports
{
  git rev-parse HEAD
  sw_vers
  xcode-select -p
  xcodebuild -version
  xcrun swiftc --version
  xcrun clang --version
  "$PYTHON" --version
  "$VOICEACCESS_QT/bin/qmake" -query
} > build/reports/candidate-toolchain.txt 2>&1
make unit PYTHON="$PYTHON"
make package PYTHON="$PYTHON"
"$PYTHON" - <<'PY'
from pathlib import Path
import subprocess
import sys
sys.path.insert(0, "scripts")
from build_common import ADDIN, DOCK_LIBRARY, NATIVE_LIBRARY, VERSION
binaries = [ADDIN / "_dock" / DOCK_LIBRARY, ADDIN / "_dock" / NATIVE_LIBRARY,
            ADDIN / "_native/VoiceAccess.app/Contents/MacOS/VoiceAccess"]
with Path("build/reports/candidate-binaries.txt").open("w") as report:
    for binary in binaries:
        for command in (["lipo", "-archs", str(binary)],
                        ["otool", "-L", str(binary)], ["otool", "-l", str(binary)],
                        ["codesign", "--verify", "--strict", "--verbose=2", str(binary)]):
            result = subprocess.run(command, check=True, text=True, stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT)
            report.write(repr(command) + "\n" + result.stdout + "\n")
            if command[0] == "lipo" and result.stdout.strip() != "x86_64":
                raise SystemExit("Unexpected binary architecture")
    subprocess.run(["codesign", "--verify", "--strict", "--verbose=2",
                    str(ADDIN / "_native/VoiceAccess.app")], check=True)
package = Path("dist") / f"VoiceAccess-{VERSION}.rdkp"
with package.with_suffix(".rdkp.sha256").open("w") as checksum:
    subprocess.run(["shasum", "-a", "256", package.name], cwd=package.parent,
                   stdout=checksum, check=True)
PY
echo "Local candidate only. Review load commands and complete docs/distribution.md gates."
