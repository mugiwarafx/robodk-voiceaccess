"""Generate add-in metadata and an installable OPC/ZIP .rdkp package."""

import argparse
import mimetypes
from pathlib import Path
import xml.etree.ElementTree as ET
import zipfile
from build_common import ADDIN, ROOT, VERSION, DOCK_LIBRARY, NATIVE_LIBRARY

MANIFEST = "http://schemas.robodk.com/package/2022/manifest"
CORE = "http://schemas.openxmlformats.org/package/2006/metadata/core-properties"
DC = "http://purl.org/dc/elements/1.1/"
RELS = "http://schemas.openxmlformats.org/package/2006/relationships"
TYPES = "http://schemas.openxmlformats.org/package/2006/content-types"
PUBLISHER = "VoiceAccess contributors"


def xml(element):
    ET.indent(element, space="  ")
    return ET.tostring(element, encoding="utf-8", xml_declaration=True)


def files():
    return sorted(p for p in ADDIN.rglob("*") if p.is_file()
                  and "__pycache__" not in p.parts and p.suffix != ".pyc"
                  and p.name not in (".DS_Store", "manifest.xml", "core_properties.xml"))


def metadata():
    ET.register_namespace("", MANIFEST)
    manifest = ET.Element(f"{{{MANIFEST}}}packageManifest", version="1.0")
    properties = ET.SubElement(manifest, f"{{{MANIFEST}}}extraProperties")
    ET.SubElement(properties, f"{{{MANIFEST}}}company").text = PUBLISHER
    ET.SubElement(properties, f"{{{MANIFEST}}}icon").text = "/icon.svg"
    assets = ET.SubElement(manifest, f"{{{MANIFEST}}}assets")
    for path in files():
        if path.name == "icon.svg":
            continue
        ET.SubElement(assets, f"{{{MANIFEST}}}asset", cpu="any", system="any", target="$(SourcePath)").text = "/VoiceAccess/" + path.relative_to(ADDIN).as_posix()
    (ADDIN/"manifest.xml").write_bytes(xml(manifest))
    ET.register_namespace("", CORE)
    ET.register_namespace("dc", DC)
    core = ET.Element(f"{{{CORE}}}coreProperties")
    for namespace, key, value in (
        (CORE, "category", "Application"), (CORE, "contentStatus", "Draft"),
        (DC, "creator", PUBLISHER), (CORE, "lastModifiedBy", PUBLISHER),
        (DC, "title", "VoiceAccess (unofficial)"),
        (DC, "description", "Unofficial VoiceOver helper for reading RoboDK stations and simulations"),
        (DC, "identifier", "com.robodk.voiceaccess"), (DC, "language", "eng"),
        (CORE, "version", VERSION),
    ):
        ET.SubElement(core, f"{{{namespace}}}{key}").text = value
    (ADDIN/"core_properties.xml").write_bytes(xml(core))


def package(destination):
    required = [ADDIN/"_dock"/DOCK_LIBRARY, ADDIN/"_dock"/NATIVE_LIBRARY,
                ADDIN/"_native/VoiceAccess.app/Contents/MacOS/VoiceAccess"]
    missing = [p.name for p in required if not p.is_file()]
    if missing:
        raise SystemExit("Run make build first. Missing: " + ", ".join(missing))
    metadata()
    ET.register_namespace("", RELS)
    relationships = ET.Element(f"{{{RELS}}}Relationships")
    for index, kind, target in (
        (1, RELS + "/metadata/core-properties", "core_properties.xml"),
        (2, "http://schemas.robodk.com/package/2022/relationships/manifest", "manifest.xml"),
        (3, "http://schemas.robodk.com/package/2022/relationships/appconfig", "AppConfig.ini"),
    ):
        ET.SubElement(relationships, f"{{{RELS}}}Relationship", Id=f"rId{index}", Type=kind, Target="/VoiceAccess/"+target)
    entries = {"_rels/.rels": xml(relationships)}
    modes = {}
    for path in files() + [ADDIN/"manifest.xml", ADDIN/"core_properties.xml"]:
        name = "icon.svg" if path.name == "icon.svg" else "VoiceAccess/" + path.relative_to(ADDIN).as_posix()
        entries[name] = path.read_bytes()
        modes[name] = 0o100755 if path.stat().st_mode & 0o111 else 0o100644
    ET.register_namespace("", TYPES)
    types = ET.Element(f"{{{TYPES}}}Types")
    for extension in sorted({"rels"} | {Path(name).suffix.lstrip(".") for name in entries if Path(name).suffix}):
        mime = "application/vnd.openxmlformats-package.relationships+xml" if extension == "rels" else mimetypes.guess_type("file."+extension)[0] or "application/octet-stream"
        ET.SubElement(types, f"{{{TYPES}}}Default", Extension=extension, ContentType=mime)
    ET.SubElement(types, f"{{{TYPES}}}Override", PartName="/VoiceAccess/core_properties.xml", ContentType="application/vnd.openxmlformats-package.core-properties+xml")
    entries["[Content_Types].xml"] = xml(types)
    destination.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name, data in sorted(entries.items()):
            info = zipfile.ZipInfo(name)
            info.create_system = 3
            info.external_attr = modes.get(name, 0o100644) << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, data)
    print(destination)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--metadata-only", action="store_true")
    parser.add_argument("--output", type=Path, default=ROOT/"dist"/f"VoiceAccess-{VERSION}.rdkp")
    args = parser.parse_args()
    if args.metadata_only:
        metadata()
    else:
        package(args.output)
