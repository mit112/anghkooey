#!/usr/bin/env python3
"""Re-applies PrivacyInfo.xcprivacy entries to project.pbxproj after every make generate.

Run from repo root: python3 scripts/patch_privacy_info.py
"""
import sys

PBXPROJ = "App/Anghkooey.xcodeproj/project.pbxproj"

# Stable UUIDs used across all regenerations
BUILD_FILE_APP    = "AA000001000000000000BB01"
BUILD_FILE_SHARE  = "AA000001000000000000BB02"
BUILD_FILE_WIDGET = "AA000001000000000000BB03"
FILE_REF_APP      = "AA000001000000000000AA01"
FILE_REF_SHARE    = "AA000001000000000000AA02"
FILE_REF_WIDGET   = "AA000001000000000000AA03"
PHASE_APP         = "AA000001000000000000CC01"
PHASE_SHARE       = "AA000001000000000000CC02"
PHASE_WIDGET      = "AA000001000000000000CC03"

with open(PBXPROJ) as f:
    lines = f.readlines()

if "AA000001000000000000AA01" in "".join(lines):
    print("PrivacyInfo patch already applied — nothing to do.")
    sys.exit(0)

out = []
for i, line in enumerate(lines):
    # 1. Insert PBXBuildFile entries before end of that section
    if "/* End PBXBuildFile section */" in line:
        out.append(f'\t\t{BUILD_FILE_APP} /* PrivacyInfo.xcprivacy in Resources */ = {{isa = PBXBuildFile; fileRef = {FILE_REF_APP} /* PrivacyInfo.xcprivacy */; }};\n')
        out.append(f'\t\t{BUILD_FILE_SHARE} /* PrivacyInfo.xcprivacy in Resources */ = {{isa = PBXBuildFile; fileRef = {FILE_REF_SHARE} /* PrivacyInfo.xcprivacy */; }};\n')
        out.append(f'\t\t{BUILD_FILE_WIDGET} /* PrivacyInfo.xcprivacy in Resources */ = {{isa = PBXBuildFile; fileRef = {FILE_REF_WIDGET} /* PrivacyInfo.xcprivacy */; }};\n')

    # 2. Insert PBXFileReference entries before end of that section
    if "/* End PBXFileReference section */" in line:
        out.append(f'\t\t{FILE_REF_APP} /* PrivacyInfo.xcprivacy */ = {{isa = PBXFileReference; lastKnownFileType = text.xml; path = PrivacyInfo.xcprivacy; sourceTree = "<group>"; }};\n')
        out.append(f'\t\t{FILE_REF_SHARE} /* PrivacyInfo.xcprivacy */ = {{isa = PBXFileReference; lastKnownFileType = text.xml; path = PrivacyInfo.xcprivacy; sourceTree = "<group>"; }};\n')
        out.append(f'\t\t{FILE_REF_WIDGET} /* PrivacyInfo.xcprivacy */ = {{isa = PBXFileReference; lastKnownFileType = text.xml; path = PrivacyInfo.xcprivacy; sourceTree = "<group>"; }};\n')

    # 3. Insert AA01 into Anghkooey group (detect by next line being 'path = Anghkooey;')
    if i + 1 < len(lines) and "path = Anghkooey;" in lines[i + 1] and ");" in line:
        # line is the closing "); of the Anghkooey group children array
        out.append(f'\t\t\t\t{FILE_REF_APP} /* PrivacyInfo.xcprivacy */,\n')

    # 4. Insert AA03 into AnghkooeyWidget group
    if i + 1 < len(lines) and "path = AnghkooeyWidget;" in lines[i + 1] and ");" in line:
        out.append(f'\t\t\t\t{FILE_REF_WIDGET} /* PrivacyInfo.xcprivacy */,\n')

    # 5. Insert AA02 into AnghkooeyShare group
    if i + 1 < len(lines) and "path = AnghkooeyShare;" in lines[i + 1] and ");" in line:
        out.append(f'\t\t\t\t{FILE_REF_SHARE} /* PrivacyInfo.xcprivacy */,\n')

    out.append(line)

    # 6. Insert PBXResourcesBuildPhase section after End PBXProject section
    if "/* End PBXProject section */" in line:
        resources_section = f"""
/* Begin PBXResourcesBuildPhase section */
\t\t{PHASE_APP} /* Resources */ = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\t{BUILD_FILE_APP} /* PrivacyInfo.xcprivacy in Resources */,
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{PHASE_SHARE} /* Resources */ = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\t{BUILD_FILE_SHARE} /* PrivacyInfo.xcprivacy in Resources */,
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{PHASE_WIDGET} /* Resources */ = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\t{BUILD_FILE_WIDGET} /* PrivacyInfo.xcprivacy in Resources */,
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXResourcesBuildPhase section */
"""
        out.append(resources_section)

# 7. Insert Resources phase IDs into each target's buildPhases array
# We need to do a second pass to insert into the correct targets
final = []
lines2 = out
i = 0
while i < len(lines2):
    line = lines2[i]
    final.append(line)
    # After "86F48F1F.../* Sources */" in Anghkooey target, insert Resources before closing
    # Instead, look for the target buildPhases arrays by surrounding context.
    # Pattern: find "02F92088487C152845F92C84 /* Anghkooey */ = {" then find buildPhases
    i += 1

# Do targeted insertion for buildPhases — simpler approach: find each target block
content = "".join(out)

# Insert PHASE_APP into Anghkooey target buildPhases
content = content.replace(
    "02F92088487C152845F92C84 /* Anghkooey */ = {\n\t\t\tisa = PBXNativeTarget;\n\t\t\tbuildConfigurationList",
    "02F92088487C152845F92C84 /* Anghkooey */ = {\n\t\t\tisa = PBXNativeTarget;\n\t\t\tbuildConfigurationList"
)

# Simpler: inject into the buildPhases list for each target
def inject_phase(text, target_uuid, phase_uuid, phase_name):
    """Find 'target_uuid /* name */ = { ... buildPhases = ( ... );' and add phase_uuid."""
    import re
    # Find the target block
    start = text.find(f"{target_uuid} /* ")
    if start == -1:
        return text
    # Find buildPhases = ( in this target block
    bp_start = text.find("buildPhases = (", start)
    if bp_start == -1:
        return text
    bp_end = text.find(");", bp_start)
    if bp_end == -1:
        return text
    # Already there?
    if phase_uuid in text[bp_start:bp_end]:
        return text
    # Insert before the closing );
    insert_line = f"\n\t\t\t\t{phase_uuid} /* Resources */,"
    return text[:bp_end] + insert_line + "\n\t\t\t" + text[bp_end:]

content = inject_phase(content, "02F92088487C152845F92C84", PHASE_APP, "Anghkooey")
content = inject_phase(content, "7F720F6F21CF5127D7884289", PHASE_SHARE, "AnghkooeyShare")
content = inject_phase(content, "5590F6898AB2844890005CC7", PHASE_WIDGET, "AnghkooeyWidget")

with open(PBXPROJ, "w") as f:
    f.write(content)

count = content.count("PrivacyInfo")
print(f"Patch applied. PrivacyInfo references in pbxproj: {count}")
if count < 12:
    print(f"WARNING: expected ≥12 but got {count}")
    sys.exit(1)
