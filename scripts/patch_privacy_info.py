#!/usr/bin/env python3
"""Re-applies PrivacyInfo.xcprivacy entries to project.pbxproj after every make generate.

Run from repo root: python3 scripts/patch_privacy_info.py

xcodegen silently drops PrivacyInfo.xcprivacy from the Copy Bundle Resources phase.
This script re-adds it. IMPORTANT: it injects PrivacyInfo into each target's EXISTING
xcodegen-generated PBXResourcesBuildPhase rather than creating a second resources phase.
A target with two Copy Bundle Resources phases builds incorrectly — Xcode executes only
one, which previously caused the asset catalog (AppIcon/AccentColor) to never reach actool.
"""
import os
import re
import sys

PBXPROJ = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "App", "Anghkooey.xcodeproj", "project.pbxproj")

# Stable UUIDs used across all regenerations
BUILD_FILE = {
    "app":    "AA000001000000000000BB01",
    "share":  "AA000001000000000000BB02",
    "widget": "AA000001000000000000BB03",
}
FILE_REF = {
    "app":    "AA000001000000000000AA01",
    "share":  "AA000001000000000000AA02",
    "widget": "AA000001000000000000AA03",
}
# Native target UUIDs (stable across regenerations — xcodegen derives them from names)
TARGET_UUID = {
    "app":    "02F92088487C152845F92C84",
    "share":  "7F720F6F21CF5127D7884289",
    "widget": "5590F6898AB2844890005CC7",
}
# Group path markers (the line that follows the group's closing "); ")
GROUP_PATH = {
    "app":    "path = Anghkooey;",
    "share":  "path = AnghkooeyShare;",
    "widget": "path = AnghkooeyWidget;",
}

with open(PBXPROJ) as f:
    content = f.read()

if FILE_REF["app"] in content:
    print("PrivacyInfo patch already applied — nothing to do.")
    sys.exit(0)

lines = content.splitlines(keepends=True)
out = []
for i, line in enumerate(lines):
    # 1. PBXBuildFile entries
    if "/* End PBXBuildFile section */" in line:
        for key in ("app", "share", "widget"):
            out.append(f'\t\t{BUILD_FILE[key]} /* PrivacyInfo.xcprivacy in Resources */ = {{isa = PBXBuildFile; fileRef = {FILE_REF[key]} /* PrivacyInfo.xcprivacy */; }};\n')
    # 2. PBXFileReference entries
    if "/* End PBXFileReference section */" in line:
        for key in ("app", "share", "widget"):
            out.append(f'\t\t{FILE_REF[key]} /* PrivacyInfo.xcprivacy */ = {{isa = PBXFileReference; lastKnownFileType = text.xml; path = PrivacyInfo.xcprivacy; sourceTree = "<group>"; }};\n')
    # 3. Add FILE_REF into each target's group children
    if i + 1 < len(lines) and ");" in line:
        for key in ("app", "share", "widget"):
            if GROUP_PATH[key] in lines[i + 1]:
                out.append(f'\t\t\t\t{FILE_REF[key]} /* PrivacyInfo.xcprivacy */,\n')
    out.append(line)

content = "".join(out)


def resources_phase_uuid_for_target(text, target_uuid):
    """Return the PBXResourcesBuildPhase UUID listed in this target's buildPhases."""
    start = text.find(f"{target_uuid} /* ")
    bp_start = text.find("buildPhases = (", start)
    bp_end = text.find(");", bp_start)
    phase_uuids = re.findall(r"([0-9A-Fa-f]{24}) /\*", text[bp_start:bp_end])
    for uuid in phase_uuids:
        # Match the DEFINITION block (uuid ... = { isa = ...), not the buildPhases reference.
        m = re.search(rf"{uuid} /\* [^*]+ \*/ = {{\s*isa = (\w+)", text)
        if m and m.group(1) == "PBXResourcesBuildPhase":
            return uuid
    return None


def inject_into_phase(text, phase_uuid, build_file_uuid):
    """Add a build-file ref into an existing resources phase's files array."""
    m = re.search(rf"{phase_uuid} /\* [^*]+ \*/ = {{", text)
    pdef = m.start()
    files_start = text.find("files = (", pdef)
    files_end = text.find(");", files_start)
    if build_file_uuid in text[files_start:files_end]:
        return text
    insert = f"\n\t\t\t\t{build_file_uuid} /* PrivacyInfo.xcprivacy in Resources */,"
    return text[:files_end] + insert + "\n\t\t\t" + text[files_end:]


# Stable phase UUIDs for targets where xcodegen produces NO resources phase
# (it drops the .xcprivacy that would have triggered one), so we create one.
NEW_PHASE = {
    "share":  "AA000001000000000000CC02",
    "widget": "AA000001000000000000CC03",
}


def create_phase_for_target(text, target_uuid, phase_uuid, build_file_uuid):
    """Create a PBXResourcesBuildPhase and add it to the target's buildPhases."""
    # Add the phase definition right after End PBXProject section.
    block = (
        f"\t\t{phase_uuid} /* Resources */ = {{\n"
        f"\t\t\tisa = PBXResourcesBuildPhase;\n"
        f"\t\t\tbuildActionMask = 2147483647;\n"
        f"\t\t\tfiles = (\n"
        f"\t\t\t\t{build_file_uuid} /* PrivacyInfo.xcprivacy in Resources */,\n"
        f"\t\t\t);\n"
        f"\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
        f"\t\t}};\n"
    )
    if "/* Begin PBXResourcesBuildPhase section */" in text:
        text = text.replace(
            "/* Begin PBXResourcesBuildPhase section */\n",
            "/* Begin PBXResourcesBuildPhase section */\n" + block, 1)
    else:
        text = text.replace(
            "/* End PBXProject section */\n",
            "/* End PBXProject section */\n\n/* Begin PBXResourcesBuildPhase section */\n"
            + block + "/* End PBXResourcesBuildPhase section */\n", 1)
    # Add phase to target buildPhases.
    s = text.find(f"{target_uuid} /* ")
    bp_start = text.find("buildPhases = (", s)
    bp_end = text.find(");", bp_start)
    if phase_uuid not in text[bp_start:bp_end]:
        insert = f"\n\t\t\t\t{phase_uuid} /* Resources */,"
        text = text[:bp_end] + insert + "\n\t\t\t" + text[bp_end:]
    return text


for key in ("app", "share", "widget"):
    phase = resources_phase_uuid_for_target(content, TARGET_UUID[key])
    if phase is not None:
        content = inject_into_phase(content, phase, BUILD_FILE[key])
    else:
        content = create_phase_for_target(content, TARGET_UUID[key], NEW_PHASE[key], BUILD_FILE[key])

with open(PBXPROJ, "w") as f:
    f.write(content)

count = content.count("PrivacyInfo")
# Guard against the regression this script exists to prevent.
n_resource_phases = content.count("isa = PBXResourcesBuildPhase;")
print(f"Patch applied. PrivacyInfo references: {count}. Resources phases: {n_resource_phases}.")
if count < 12:
    print(f"WARNING: expected ≥12 PrivacyInfo refs but got {count}")
    sys.exit(1)
