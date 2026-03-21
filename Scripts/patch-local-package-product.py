#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


LOCAL_PACKAGE_SECTION = re.compile(
    r'(?P<uuid>[A-F0-9]{24}) /\* XCLocalSwiftPackageReference "(?P<label>[^"]+)" \*/ = \{\n'
    r"\s*isa = XCLocalSwiftPackageReference;\n"
    r'\s*relativePath = "(?P<relative_path>[^"]+)";\n'
    r"\s*\};",
    re.MULTILINE,
)

PRODUCT_DEPENDENCY_SECTION = re.compile(
    r'(?P<uuid>[A-F0-9]{24}) /\* (?P<label>[^*]+?) \*/ = \{\n'
    r"\s*isa = XCSwiftPackageProductDependency;\n"
    r"(?P<body>(?:\s*.*\n)*?)"
    r"\s*productName = (?P<product_name>[^;]+);\n"
    r"\s*\};",
    re.MULTILINE,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Patch a generated Xcode project so a local Swift package product points back to its package reference."
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


def fail(message: str) -> None:
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


def patch_product_dependency(text: str, package_match: re.Match[str], product_match: re.Match[str]) -> str:
    product_block = product_match.group(0)
    package_uuid = package_match.group("uuid")
    package_label = package_match.group("label")
    package_line = f'\t\t\tpackage = {package_uuid} /* XCLocalSwiftPackageReference "{package_label}" */;\n'

    if re.search(r"\n\s*package = [A-F0-9]{24} /\* XCLocalSwiftPackageReference ", product_block):
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
        patched_block = product_block.replace(insertion_marker, package_line + insertion_marker, 1)

    return text.replace(product_block, patched_block, 1)


def verify(text: str, relative_path: str, product_name: str) -> None:
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

    patched_text = patch_product_dependency(text, package_match_list[0], product_match_list[0])
    verify(patched_text, args.relative_path, args.product_name)

    if patched_text != text:
        args.project_file.write_text(patched_text)

    print(
        f'Patched {args.project_file} so product "{args.product_name}" points to local package "{args.relative_path}".'
    )


if __name__ == "__main__":
    main()
