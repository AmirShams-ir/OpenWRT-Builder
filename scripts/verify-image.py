#!/usr/bin/env python3
"""Validate the MBR table and fixed partition sizes in a gzipped x86 image."""

from __future__ import annotations

import argparse
import gzip
import struct
from pathlib import Path

SECTOR_SIZE = 512
SECTORS_PER_MIB = 2048


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    parser.add_argument("--kernel-mib", type=int, required=True)
    parser.add_argument("--root-mib", type=int, required=True)
    args = parser.parse_args()

    if not args.image.is_file():
        raise SystemExit(f"Image not found: {args.image}")

    try:
        with gzip.open(args.image, "rb") as stream:
            mbr = stream.read(SECTOR_SIZE)
    except (OSError, EOFError) as exc:
        raise SystemExit(f"Could not read image MBR: {exc}") from exc

    if len(mbr) != SECTOR_SIZE or mbr[510:512] != b"\x55\xaa":
        raise SystemExit("Invalid or missing MBR signature.")

    partitions = []
    for index in range(4):
        entry = mbr[446 + index * 16 : 462 + index * 16]
        _boot, _chs_start, ptype, _chs_end, start, sectors = struct.unpack(
            "<B3sB3sII", entry
        )
        if ptype and sectors:
            partitions.append((ptype, start, sectors))

    if len(partitions) != 2:
        raise SystemExit(f"Expected exactly 2 base partitions; found {len(partitions)}.")

    expected_sizes = (
        args.kernel_mib * SECTORS_PER_MIB,
        args.root_mib * SECTORS_PER_MIB,
    )
    for number, (part, expected) in enumerate(zip(partitions, expected_sizes), 1):
        ptype, start, sectors = part
        if ptype != 0x83:
            raise SystemExit(f"Partition {number}: unexpected type 0x{ptype:02x}.")
        if sectors != expected:
            raise SystemExit(
                f"Partition {number}: got {sectors / SECTORS_PER_MIB:.2f} MiB; "
                f"expected {expected / SECTORS_PER_MIB:.2f} MiB."
            )
        print(
            f"Partition {number}: start={start}, size={sectors} sectors "
            f"({sectors / SECTORS_PER_MIB:.0f} MiB), type=0x{ptype:02x}"
        )

    print("MBR: valid")
    print("Boot and Root partition sizes: verified")
    print("Home: not included in this base-build milestone")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
