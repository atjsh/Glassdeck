#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import NoReturn


LOCAL_PACKAGE_SECTION = re.compile(
    r'(?P<uuid>[A-F0-9]{24}) /\* XCLocalSwiftPackageReference "(?P<label>[^"]+)" \*/ = \{\n'
    r"\s*isa = XCLocalSwiftPackageReference;\n"
    r'\s*relativePath = "(?P<relative_path>[^"]+)";\n'
    r"\s*\};",
    re.MULTILINE,
)

PRODUCT_DEPENDENCY_SECTION = re.compile(
    r"(?P<uuid>[A-F0-9]{24}) /\* (?P<label>[^*]+?) \*/ = \{\n"
    r"\s*isa = XCSwiftPackageProductDependency;\n"
    r"(?P<body>(?:\s*.*\n)*?)"
    r"\s*productName = (?P<product_name>[^;]+);\n"
    r"\s*\};",
    re.MULTILINE,
)

PBX_BUILD_FILE_SECTION = re.compile(
    r"/\* Begin PBXBuildFile section \*/\n(?P<body>.*?)/\* End PBXBuildFile section \*/",
    re.DOTALL,
)

PBX_FILE_REFERENCE_SECTION = re.compile(
    r"/\* Begin PBXFileReference section \*/\n(?P<body>.*?)/\* End PBXFileReference section \*/",
    re.DOTALL,
)

PBX_RESOURCES_SECTION = re.compile(
    r"/\* Begin PBXResourcesBuildPhase section \*/\n(?P<body>.*?)/\* End PBXResourcesBuildPhase section \*/",
    re.DOTALL,
)

RESOURCES_GROUP = re.compile(
    r"(?P<uuid>[A-F0-9]{24}) /\* Resources \*/ = \{\n"
    r"\s*isa = PBXGroup;\n"
    r"\s*children = \(\n"
    r"(?P<body>.*?)"
    r"\s*\);\n"
    r"\s*path = Resources;\n"
    r'\s*sourceTree = "<group>";\n'
    r"\s*\};",
    re.DOTALL,
)

APP_TARGET = re.compile(
    r"(?P<uuid>[A-F0-9]{24}) /\* GlassdeckApp \*/ = \{\n"
    r"\s*isa = PBXNativeTarget;\n"
    r"(?P<body>.*?)"
    r"\s*productType = \"com\.apple\.product-type\.application\";\n"
    r"\s*\};",
    re.DOTALL,
)


@dataclass(frozen=True)
class ResourceSpec:
    label: str
    file_type: str
    path: str

    @property
    def file_ref_uuid(self) -> str:
        return stable_uuid(f"file-ref:{self.path}")

    @property
    def build_file_uuid(self) -> str:
        return stable_uuid(f"build-file:{self.path}")


RESOURCE_PHASE_UUID = "A112B0F00C0DEBEEF0011001"
RESOURCE_PHASE_LABEL = "Resources"

APP_RESOURCES = (
    ResourceSpec(
        "Assets.xcassets", "folder.assetcatalog", "Glassdeck/Resources/Assets.xcassets"
    ),
    ResourceSpec(
        "AppIcon.icon", "folder.iconcomposer.icon", "Glassdeck/Resources/AppIcon.icon"
    ),
)


def stable_uuid(key: str) -> str:
    return hashlib.sha1(key.encode("utf-8")).hexdigest().upper()[:24]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Patch a generated Xcode project so local package products and app resources are wired correctly."
    )
    parser.add_argument(
        "project_file",
        type=Path,
        help="Path to the generated project.pbxproj file.",
    )
    parser.add_argument(
        "--relative-path",
        default="Vendor/swift-ssh-client",
        help='Expected XCLocalSwiftPackageReference relativePath. Default: "Vendor/swift-ssh-client".',
    )
    parser.add_argument(
        "--product-name",
        default="SSHClient",
        help='Expected XCSwiftPackageProductDependency productName. Default: "SSHClient".',
    )
    return parser.parse_args()


def fail(message: str) -> NoReturn:
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


def local_package_matches(text: str, relative_path: str) -> list[re.Match[str]]:
    return [
        match
        for match in LOCAL_PACKAGE_SECTION.finditer(text)
        if match.group("relative_path") == relative_path
    ]


def product_matches(text: str, product_name: str) -> list[re.Match[str]]:
    return [
        match
        for match in PRODUCT_DEPENDENCY_SECTION.finditer(text)
        if match.group("product_name") == product_name
    ]


def patch_product_dependency(
    text: str, package_match: re.Match[str], product_match: re.Match[str]
) -> str:
    product_block = product_match.group(0)
    package_uuid = package_match.group("uuid")
    package_label = package_match.group("label")
    package_line = f'\t\t\tpackage = {package_uuid} /* XCLocalSwiftPackageReference "{package_label}" */;\n'

    if re.search(
        r"\n\s*package = [A-F0-9]{24} /\* XCLocalSwiftPackageReference ", product_block
    ):
        patched_block = re.sub(
            r'\n\s*package = [A-F0-9]{24} /\* XCLocalSwiftPackageReference "[^"]+" \*/;\n',
            "\n" + package_line,
            product_block,
            count=1,
        )
    else:
        insertion_marker = "\t\t\tproductName = "
        if insertion_marker not in product_block:
            fail("product dependency block does not contain a productName line.")
        patched_block = product_block.replace(
            insertion_marker, package_line + insertion_marker, 1
        )

    return text.replace(product_block, patched_block, 1)


def ensure_build_file_entries(text: str) -> str:
    match = PBX_BUILD_FILE_SECTION.search(text)
    if not match:
        fail("PBXBuildFile section not found.")

    body = match.group("body")
    additions: list[str] = []
    for resource in APP_RESOURCES:
        marker = f"{resource.build_file_uuid} /* {resource.label} in Resources */"
        if marker in body:
            continue
        additions.append(
            f"\t\t{resource.build_file_uuid} /* {resource.label} in Resources */ = "
            f"{{isa = PBXBuildFile; fileRef = {resource.file_ref_uuid} /* {resource.label} */; }};\n"
        )

    if not additions:
        return text

    new_body = body + "".join(additions)
    return text[: match.start("body")] + new_body + text[match.end("body") :]


def ensure_file_reference_entries(text: str) -> str:
    match = PBX_FILE_REFERENCE_SECTION.search(text)
    if not match:
        fail("PBXFileReference section not found.")

    body = match.group("body")
    additions: list[str] = []
    for resource in APP_RESOURCES:
        marker = f"{resource.file_ref_uuid} /* {resource.label} */"
        if marker in body:
            continue
        additions.append(
            f"\t\t{resource.file_ref_uuid} /* {resource.label} */ = "
            f"{{isa = PBXFileReference; lastKnownFileType = {resource.file_type}; "
            f'name = {resource.label}; path = "{resource.path}"; sourceTree = SOURCE_ROOT; }};\n'
        )

    if not additions:
        return text

    new_body = body + "".join(additions)
    return text[: match.start("body")] + new_body + text[match.end("body") :]


def ensure_resources_group_children(text: str) -> str:
    match = RESOURCES_GROUP.search(text)
    if not match:
        fail("Resources group not found.")

    group_block = match.group(0)
    body = match.group("body")
    additions = ""
    for resource in APP_RESOURCES:
        child_line = f"\t\t\t\t{resource.file_ref_uuid} /* {resource.label} */,\n"
        if child_line not in body and child_line not in additions:
            additions += child_line

    if not additions:
        return text

    if body:
        patched_block = group_block.replace(body, body + additions, 1)
    else:
        marker = "\t\t\tchildren = (\n"
        patched_block = group_block.replace(marker, marker + additions, 1)
    return text.replace(group_block, patched_block, 1)


def ensure_resources_build_phase(text: str) -> str:
    files_lines = "".join(
        f"\t\t\t\t{resource.build_file_uuid} /* {resource.label} in Resources */,\n"
        for resource in APP_RESOURCES
    )
    desired_block = (
        "/* Begin PBXResourcesBuildPhase section */\n"
        f"\t\t{RESOURCE_PHASE_UUID} /* {RESOURCE_PHASE_LABEL} */ = {{\n"
        "\t\t\tisa = PBXResourcesBuildPhase;\n"
        "\t\t\tbuildActionMask = 2147483647;\n"
        "\t\t\tfiles = (\n"
        f"{files_lines}"
        "\t\t\t);\n"
        "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
        "\t\t};\n"
        "/* End PBXResourcesBuildPhase section */"
    )

    match = PBX_RESOURCES_SECTION.search(text)
    if match:
        return text[: match.start()] + desired_block + text[match.end() :]

    marker = "/* Begin PBXSourcesBuildPhase section */"
    if marker not in text:
        fail("PBXSourcesBuildPhase section not found.")
    return text.replace(marker, desired_block + "\n\n" + marker, 1)


def ensure_app_target_resources_phase(text: str) -> str:
    match = APP_TARGET.search(text)
    if not match:
        fail('PBXNativeTarget "GlassdeckApp" not found.')

    target_block = match.group(0)
    build_phases_match = re.search(
        r"\s*buildPhases = \(\n(?P<body>.*?)\s*\);\n",
        target_block,
        re.DOTALL,
    )
    if not build_phases_match:
        fail("GlassdeckApp target buildPhases list not found.")

    body = build_phases_match.group("body")
    entry = f"\t\t\t\t{RESOURCE_PHASE_UUID} /* {RESOURCE_PHASE_LABEL} */,\n"
    if entry in body:
        return text

    sources_entry = re.search(r"\t\t\t\t[A-F0-9]{24} /\* Sources \*/,\n", body)
    if sources_entry:
        insert_at = sources_entry.end()
        new_body = body[:insert_at] + entry + body[insert_at:]
    else:
        new_body = body + entry

    patched_block = target_block.replace(body, new_body, 1)
    return text.replace(target_block, patched_block, 1)


def verify_local_package(text: str, relative_path: str, product_name: str) -> None:
    package_match_list = local_package_matches(text, relative_path)
    if len(package_match_list) != 1:
        fail(
            f'expected exactly one local package reference for "{relative_path}", found {len(package_match_list)}.'
        )

    product_match_list = product_matches(text, product_name)
    if len(product_match_list) != 1:
        fail(
            f'expected exactly one package product dependency for "{product_name}", found {len(product_match_list)}.'
        )

    package_uuid = package_match_list[0].group("uuid")
    expected_package_line = f"package = {package_uuid} /* XCLocalSwiftPackageReference"
    if expected_package_line not in product_match_list[0].group(0):
        fail(
            f'package product dependency "{product_name}" is not linked to local package "{relative_path}".'
        )


def verify_resources(text: str) -> None:
    if RESOURCE_PHASE_UUID not in text:
        fail("Resources build phase was not added to the project.")

    target_match = APP_TARGET.search(text)
    if not target_match or RESOURCE_PHASE_UUID not in target_match.group(0):
        fail("GlassdeckApp target does not reference the Resources build phase.")

    for resource in APP_RESOURCES:
        if resource.file_ref_uuid not in text:
            fail(f"{resource.label} file reference is missing from the project.")
        if resource.build_file_uuid not in text:
            fail(f"{resource.label} build file entry is missing from the project.")

    if not RESOURCES_GROUP.search(text):
        fail("Resources group missing after patch.")


def main() -> None:
    args = parse_args()
    text = args.project_file.read_text()

    package_match_list = local_package_matches(text, args.relative_path)
    if len(package_match_list) != 1:
        fail(
            f'expected exactly one local package reference for "{args.relative_path}", found {len(package_match_list)}.'
        )

    product_match_list = product_matches(text, args.product_name)
    if len(product_match_list) != 1:
        fail(
            f'expected exactly one package product dependency for "{args.product_name}", found {len(product_match_list)}.'
        )

    patched_text = patch_product_dependency(
        text, package_match_list[0], product_match_list[0]
    )
    patched_text = ensure_build_file_entries(patched_text)
    patched_text = ensure_file_reference_entries(patched_text)
    patched_text = ensure_resources_group_children(patched_text)
    patched_text = ensure_resources_build_phase(patched_text)
    patched_text = ensure_app_target_resources_phase(patched_text)

    verify_local_package(patched_text, args.relative_path, args.product_name)
    verify_resources(patched_text)

    if patched_text != text:
        args.project_file.write_text(patched_text)

    print(
        f'Patched {args.project_file} so product "{args.product_name}" points to local package '
        f'"{args.relative_path}" and app resources are bundled.'
    )


if __name__ == "__main__":
    main()
