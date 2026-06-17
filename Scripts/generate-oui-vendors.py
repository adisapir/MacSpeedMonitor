#!/usr/bin/env python3
"""Generate the compact OUI vendor resource from Wireshark's manuf file."""

from __future__ import annotations

import argparse
from pathlib import Path
from urllib.request import urlopen


DEFAULT_SOURCE_URL = "https://www.wireshark.org/download/automated/data/manuf"
DEFAULT_TARGET = Path("Sources/SpeedMonitorCore/Resources/oui-vendors.tsv")


def normalized_prefix(value: str) -> str | None:
    value = value.strip()
    if not value:
        return None

    if "/" in value:
        raw, bits_text = value.split("/", 1)
        try:
            bits = int(bits_text.strip())
        except ValueError:
            return None
    else:
        raw = value
        bits = 24

    hex_value = "".join(ch for ch in raw.upper() if ch in "0123456789ABCDEF")
    nibbles = (bits + 3) // 4
    if nibbles < 6 or nibbles > 12 or len(hex_value) < nibbles:
        return None

    return hex_value[:nibbles]


def read_source(source: str) -> str:
    if source.startswith(("http://", "https://")):
        with urlopen(source, timeout=30) as response:
            return response.read().decode("utf-8")

    return Path(source).read_text(encoding="utf-8")


def generate_resource(source_text: str) -> tuple[str, int, int]:
    vendor_ids: dict[str, int] = {}
    vendors: list[str] = []
    prefix_vendor: dict[str, int] = {}

    for line in source_text.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue

        parts = [part.strip() for part in line.split("\t")]
        if len(parts) < 2:
            continue

        prefix = normalized_prefix(parts[0])
        if prefix is None:
            continue

        vendor = parts[2] if len(parts) >= 3 and parts[2] else parts[1]
        if not vendor:
            continue

        vendor_id = vendor_ids.get(vendor)
        if vendor_id is None:
            vendor_id = len(vendors)
            vendor_ids[vendor] = vendor_id
            vendors.append(vendor)

        prefix_vendor[prefix] = vendor_id

    lines = [
        f"# Generated from {DEFAULT_SOURCE_URL}",
        "# Format: @vendors lines are vendor names by zero-based index; "
        "@prefixes lines are hex nibble prefix<TAB>vendor index.",
        "# Prefixes preserve Wireshark MAC blocks including 24-bit, 28-bit, "
        "and 36-bit assignments.",
        "@vendors",
        *vendors,
        "@prefixes",
    ]

    for prefix in sorted(prefix_vendor, key=lambda item: (len(item), item)):
        lines.append(f"{prefix}\t{prefix_vendor[prefix]}")

    return "\n".join(lines) + "\n", len(vendors), len(prefix_vendor)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--source",
        default=DEFAULT_SOURCE_URL,
        help="Wireshark manuf URL or local manuf file path",
    )
    parser.add_argument(
        "--target",
        default=DEFAULT_TARGET,
        type=Path,
        help="Resource file to write",
    )
    args = parser.parse_args()

    source_text = read_source(args.source)
    resource_text, vendor_count, prefix_count = generate_resource(source_text)
    args.target.parent.mkdir(parents=True, exist_ok=True)
    args.target.write_text(resource_text, encoding="utf-8")

    print(
        f"Wrote {args.target} with {vendor_count} vendors and "
        f"{prefix_count} prefixes."
    )


if __name__ == "__main__":
    main()
