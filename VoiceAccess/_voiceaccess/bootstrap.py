"""Load the bundled SDK so the add-in works without extra Python packages."""

from pathlib import Path
import sys


def load_api():
    vendor = Path(__file__).resolve().parent / "vendor"
    if not (vendor / "robodk" / "robolink.py").is_file():
        raise RuntimeError("The bundled RoboDK SDK is missing. Reinstall VoiceAccess.")
    if str(vendor) not in sys.path:
        sys.path.insert(0, str(vendor))
    from robodk import robolink, robomath

    return robolink, robomath
