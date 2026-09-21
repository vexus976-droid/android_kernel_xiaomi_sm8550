#!/usr/bin/env python3
"""Splice a custom kernel Image into the LineageOS fuxi boot.img bundle.

Layout (verified against stock boot.img):
  [0..2048)    ANDROID! header (kernel_size field at offset 8 = kernel region size incl. padding)
  [4152..      ARM64 kernel Image (magic "ARM\x64" at 4152)
  [kernel_end) second bootloader region (size in 'second_size' field)
  rest         zero padding
"""
import struct
import sys

KERNEL_END_DEFAULT = 48658944  # from stock header kernel_size field (offset 8)
KERNEL_MAGIC = b"ARM\x64"


def find_kernel_start(data: bytes) -> int:
    idx = data.find(KERNEL_MAGIC, 2048, 100000)
    if idx < 0:
        raise SystemExit("ERROR: ARM64 kernel magic not found in boot.img")
    return idx


def main() -> None:
    stock_boot = sys.argv[1]
    kernel_img = sys.argv[2]
    out_boot = sys.argv[3]

    with open(stock_boot, "rb") as f:
        data = bytearray(f.read())

    kernel_start = find_kernel_start(data)
    kernel_end = struct.unpack_from("<I", data, 8)[0]  # kernel region size from header
    if kernel_end > len(data):
        raise SystemExit(f"ERROR: kernel_end {kernel_end} beyond file size {len(data)}")
    region_len = kernel_end - kernel_start

    with open(kernel_img, "rb") as f:
        new_kernel = f.read()

    if len(new_kernel) > region_len:
        raise SystemExit(
            f"ERROR: new kernel {len(new_kernel)} larger than region {region_len}. "
            "Cannot splice without resizing."
        )

    print(f"kernel_start={kernel_start} region_len={region_len} new_kernel={len(new_kernel)}")
    data[kernel_start:kernel_end] = new_kernel + b"\x00" * (region_len - len(new_kernel))

    # sanity check
    if data.find(KERNEL_MAGIC, 2048, 100000) != kernel_start:
        raise SystemExit("ERROR: post-splice magic check failed")

    with open(out_boot, "wb") as f:
        f.write(data)
    print(f"OK: wrote {out_boot} ({len(data)} bytes)")


if __name__ == "__main__":
    main()