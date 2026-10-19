"""Launch or address the same accessible panel from RoboDK actions."""

from pathlib import Path
import configparser
import json
import subprocess
import sys

ADDIN = Path(__file__).resolve().parents[1]
_config = configparser.ConfigParser()
_config.read(ADDIN / "AppConfig.ini")
DOCK_LIBRARY = "libVoiceAccessDock" + _config["General"]["Version"].replace(".", "") + ".dylib"


def invoke(rdk, command="show"):
    if sys.platform != "darwin":
        raise RuntimeError("This VoiceAccess prototype requires macOS.")
    if command not in ("show", "hide", "read-selection", "silence"):
        raise ValueError("Unknown VoiceAccess integration command.")
    items = [str(item.item) for item in rdk.Selection()] if command in ("show", "read-selection") else []
    library = ADDIN / "_dock" / DOCK_LIBRARY
    if library.is_file() and (library.parent / "ENABLED").is_file():
        try:
            status = json.loads(rdk.PluginCommand("VoiceAccess Dock", "status"))
        except (ValueError, TypeError):
            status = {}
        if not status.get("available") and command in ("show", "read-selection"):
            if rdk.PluginLoad(str(library)):
                status = json.loads(rdk.PluginCommand("VoiceAccess Dock", "status"))
        if status.get("available"):
            if not status.get("embedded"):
                if command in ("hide", "silence"):
                    return {"embedded": True, "command": command, "items": []}
                configuration = {"--python": sys.executable, "--bridge": str(ADDIN / "_voiceaccess/bridge.py"), "--port": str(rdk.PORT)}
                configured = json.loads(rdk.PluginCommand("VoiceAccess Dock", "configure", json.dumps(configuration)))
                if not configured.get("configured"):
                    raise RuntimeError(f"Could not create the internal VoiceAccess panel: {configured}")
            result = json.loads(rdk.PluginCommand("VoiceAccess Dock", command, json.dumps({"items": items})))
            if result.get("error"):
                raise RuntimeError(result["error"])
            return {"embedded": True, "command": command, "items": items}
    app = ADDIN / "_native/VoiceAccess.app"
    executable = app / "Contents/MacOS/VoiceAccess"
    if not executable.is_file():
        raise FileNotFoundError("The native panel is missing. Install the compiled VoiceAccess RDKP package.")
    arguments = ["--request", command, "--port", str(rdk.PORT)]
    if items:
        arguments += ["--items", ",".join(items)]
    result = subprocess.run([str(executable), *arguments], timeout=5, check=False)
    if result.returncode == 0:
        return {"reused_panel": True, "command": command, "items": items}
    if result.returncode != 69:
        raise RuntimeError("Could not send the action to VoiceAccess.")
    if command in ("silence", "hide"):
        return {"reused_panel": False, "command": command, "items": []}
    initial = [
        "/usr/bin/open", "-n", "-a", str(app), "--args",
        "--python", sys.executable, "--bridge", str(ADDIN / "_voiceaccess/bridge.py"),
        "--port", str(rdk.PORT), "--rdk-pid", rdk.Command("MainProcess_ID"),
        "--initial-command", command,
    ]
    if items:
        initial += ["--items", ",".join(items)]
    subprocess.run(initial, check=True, timeout=10)
    return {"reused_panel": False, "command": command, "items": items}
