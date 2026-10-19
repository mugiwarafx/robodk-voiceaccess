"""Link this checkout as a user Add-in and enable it through RoboDK's manager.

The manager's unpacked layout embeds core properties in the root manifest and
keeps the App in a nested folder, unlike the source/OPC pair used for packaging.
"""

import argparse
import configparser
import copy
import json
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "VoiceAccess"))
from _voiceaccess.bootstrap import load_api
from _voiceaccess.toolbar import panel_visible


def install(port=20500):
    source = ROOT / "VoiceAccess"
    wrapper = ROOT / "build/development-addin"
    wrapper.mkdir(parents=True, exist_ok=True)
    app_link = wrapper / "VoiceAccess"
    if app_link.is_symlink():
        if app_link.resolve() != source:
            raise RuntimeError("Existing development Add-in points to another source.")
    elif app_link.exists():
        raise RuntimeError("Development App folder already exists and is not our link.")
    else:
        app_link.symlink_to(source, target_is_directory=True)
    for prefix, namespace in (
        ("", "http://schemas.robodk.com/package/2022/manifest"),
        ("cp", "http://schemas.openxmlformats.org/package/2006/metadata/core-properties"),
        ("dc", "http://purl.org/dc/elements/1.1/"),
        ("dcterms", "http://purl.org/dc/terms/"),
        ("xsi", "http://www.w3.org/2001/XMLSchema-instance"),
    ):
        ET.register_namespace(prefix, namespace)
    manifest = ET.parse(source / "manifest.xml")
    manifest.getroot().insert(0, copy.deepcopy(ET.parse(source / "core_properties.xml").getroot()))
    ET.indent(manifest, space="  ")
    manifest.write(wrapper / "manifest.xml", encoding="utf-8", xml_declaration=True)
    icon = wrapper / "icon.svg"
    if not icon.exists():
        icon.symlink_to(source / "icon.svg")
    stub = Path.home() / "Library/Application Support/RoboDK/Addins/com.robodk.voiceaccess"
    stub.mkdir(parents=True, exist_ok=True)
    config = stub / "AppLink.ini"
    allowed = {str(source), str(wrapper)}
    if config.exists():
        target = next((line[5:].strip().strip('"') for line in config.read_text().splitlines() if line.startswith("Path=")), "")
        if target not in allowed:
            raise RuntimeError("The installed VoiceAccess link points to a different project.")
    config.write_text(f"[General]\nPath={wrapper}\n")
    rl, _ = load_api()
    with rl.Robolink(port=port, args=["-API_NODELAY"]) as rdk:
        before = json.loads(rdk.PluginCommand("Addin Manager", "AddinListJson"))
        reload_result = rdk.PluginCommand("Addin Manager", "Reload")
        addins = json.loads(rdk.PluginCommand("Addin Manager", "AddinListJson"))
        own = next((entry for entry in addins if entry.get("identifier") == "com.robodk.voiceaccess" and entry.get("linkPath") == str(stub)), None)
        if own is None:
            raise RuntimeError("The Add-in manager did not discover the VoiceAccess manifest.")
        enabled = {"error": 0, "errorString": "already enabled"} if own["status"] == 2 else json.loads(rdk.PluginCommand("Addin Manager", "AddinControlJson", json.dumps({"path": own["path"], "operation": "enable"})))
        final = json.loads(rdk.PluginCommand("Addin Manager", "AddinListJson"))
        own = next(entry for entry in final if entry.get("identifier") == "com.robodk.voiceaccess" and entry.get("linkPath") == str(stub))
        previous = {entry["path"]: entry["status"] for entry in before}
        changed = [entry["path"] for entry in final if entry["path"] in previous and entry.get("identifier") != "com.robodk.voiceaccess" and entry["status"] != previous[entry["path"]]]
        # Manager 1.12: 1 = disabled, 2 = enabled (verified with this Add-in).
        if enabled.get("error", 0) or own["status"] != 2:
            raise RuntimeError(f"VoiceAccess could not be enabled: {enabled}; status {own['status']}")
        app_config = configparser.ConfigParser()
        app_config.read(source / "AppConfig.ini")
        action_sync = None
        if app_config.getboolean("OpenVoiceAccess", "Checkable", fallback=False):
            # Reload recreates QAction and clears its checked state, while a
            # running panel remains visible. Restore the live visibility state.
            action_sync = json.loads(rdk.PluginCommand("Addin Manager", "AddinActionJson", json.dumps({
                "path": own["path"], "actionIndex": 0,
                "operation": "check" if panel_visible(port) else "uncheck",
            })))
        report = {"scope": "user Add-in linked to this checkout", "source": str(source), "wrapper": str(wrapper),
                  "link": str(config), "reload_result": reload_result, "enable_result": enabled,
                  "addin": own, "other_addin_status_changes": changed, "panel_action_state_sync": action_sync}
        (ROOT / "build/reports").mkdir(parents=True, exist_ok=True)
        (ROOT / "build/reports/install-development.json").write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
        return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=20500)
    result = install(parser.parse_args().port)
    print(json.dumps({"identifier":result["addin"]["identifier"], "status":result["addin"]["status"], "version":result["addin"]["version"], "other_addin_status_changes":result["other_addin_status_changes"]}, indent=2))
