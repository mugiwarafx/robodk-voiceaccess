"""Shared source metadata for local builds and release packages."""

import configparser
from pathlib import Path
import platform
import os

ROOT = Path(__file__).resolve().parents[1]
ADDIN = ROOT / "VoiceAccess"
config = configparser.ConfigParser()
config.read(ADDIN / "AppConfig.ini")
VERSION = config["General"]["Version"]
BUILD_TAG = VERSION.replace(".", "")
DOCK_LIBRARY = f"libVoiceAccessDock{BUILD_TAG}.dylib"
NATIVE_LIBRARY = f"libVoiceAccessNative{BUILD_TAG}.dylib"
ARCHITECTURE = os.environ.get("VOICEACCESS_ARCH", platform.machine())
MACOS_TARGET = "13.0"
QT_VERSION = "6.10.1"


def require_macos():
    if platform.system() != "Darwin":
        raise SystemExit("The current native build requires macOS. NVDA and Orca support is planned.")
    if ARCHITECTURE not in ("x86_64", "arm64"):
        raise SystemExit(f"Unsupported macOS architecture: {ARCHITECTURE}")
