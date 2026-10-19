"""Validate the public add-in artifact without installing it into RoboDK."""

import argparse
import configparser
from pathlib import Path, PurePosixPath
import sys
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from build_common import DOCK_LIBRARY, NATIVE_LIBRARY, VERSION


def verify(package):
    with zipfile.ZipFile(package) as archive:
        assert archive.testzip() is None, "The archive has corrupt entries"
        names = archive.namelist()
        assert len(names) == len(set(names)), "The archive has duplicate entries"
        for name in names:
            path = PurePosixPath(name)
            assert not path.is_absolute() and ".." not in path.parts, name
            assert "__pycache__" not in path.parts and not name.endswith((".pyc", ".pyo")), name
            assert path.suffix not in (".rdk", ".robot"), name
            assert ".DS_Store" not in path.parts, name

        manifest = ET.fromstring(archive.read("VoiceAccess/manifest.xml"))
        manifest_ns = {"m": "http://schemas.robodk.com/package/2022/manifest"}
        for asset in manifest.findall("m:assets/m:asset", manifest_ns):
            assert asset.text.lstrip("/") in names, asset.text
        icon = manifest.find("m:extraProperties/m:icon", manifest_ns).text
        assert icon.lstrip("/") in names
        core = ET.fromstring(archive.read("VoiceAccess/core_properties.xml"))
        namespaces = {
            "cp": "http://schemas.openxmlformats.org/package/2006/metadata/core-properties",
            "dc": "http://purl.org/dc/elements/1.1/",
        }
        assert "unofficial" in core.findtext("dc:title", namespaces=namespaces).lower()
        assert core.findtext("dc:creator", namespaces=namespaces) == "VoiceAccess contributors"
        assert core.findtext("cp:version", namespaces=namespaces) == VERSION
        config = configparser.ConfigParser()
        config.read_string(archive.read("VoiceAccess/AppConfig.ini").decode())
        assert config["General"]["Version"] == VERSION

        relationships = ET.fromstring(archive.read("_rels/.rels"))
        for relationship in relationships:
            assert relationship.attrib["Target"].lstrip("/") in names
        ET.fromstring(archive.read("[Content_Types].xml"))
        for notice in ("LICENSE.txt", "LICENSE-ROBODK.txt", "LICENSE-ROBODK-PLUGIN.txt", "THIRD_PARTY.txt"):
            assert archive.read("VoiceAccess/" + notice).strip(), notice
        for binary in (
            "VoiceAccess/_dock/" + DOCK_LIBRARY,
            "VoiceAccess/_dock/" + NATIVE_LIBRARY,
            "VoiceAccess/_native/VoiceAccess.app/Contents/MacOS/VoiceAccess",
        ):
            assert archive.getinfo(binary).external_attr >> 16 & 0o111, binary
    print("PACKAGE_CHECKS_PASSED")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("package", nargs="?", type=Path, default=ROOT / "dist" / f"VoiceAccess-{VERSION}.rdkp")
    verify(parser.parse_args().package)
