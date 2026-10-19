"""Synchronize the checkable VA action with the companion panel's visibility."""

import json
import os
from pathlib import Path


def state_path(port):
    return Path.home() / "Library/Caches/RoboDKVoiceAccess" / f"panel-{int(port)}.json"


def panel_visible(port):
    try:
        state = json.loads(state_path(port).read_text())
        os.kill(int(state["pid"]), 0)
        return state["visible"] is True
    except (OSError, ValueError, KeyError, TypeError):
        return False


def sync_toolbar(rdk, visible, owner_pid):
    # Publish before changing QAction: its toggled signal launches the action
    # script too. That script recognizes a synchronized state and does nothing.
    path = state_path(rdk.PORT)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(f".{os.getpid()}.tmp")
    temporary.write_text(json.dumps({"pid": owner_pid, "visible": bool(visible)}))
    temporary.replace(path)
    addins = json.loads(rdk.PluginCommand("Addin Manager", "AddinListJson") or "[]")
    own = next((item for item in addins if item.get("identifier") == "com.robodk.voiceaccess"), None)
    if own is None or own.get("status") != 2:
        return {"visible": bool(visible), "toolbar_updated": False}
    result = json.loads(rdk.PluginCommand("Addin Manager", "AddinActionJson", json.dumps({
        "path": own["path"], "actionIndex": 0, "operation": "check" if visible else "uncheck",
    })))
    return {"visible": bool(visible), "toolbar_updated": result.get("error") == 0}
