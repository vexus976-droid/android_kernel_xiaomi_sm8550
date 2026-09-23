#!/usr/bin/env python3
"""Splice a custom arm64 kernel Image into the LineageOS fuxi boot.img bundle.

Layout (verified against stock boot.img):
  [0..4096)      mkbootimg header (page-aligned); kernel_size field at offset 8
  [4096..        ARM64 kernel Image (the magic "ARM\\x64" == b"ARMd" sits at +0x38 = +56)
  [kernel_end)   region of kernel_size bytes; rest is zero padding
                 (no ramdisk, no signature: ramdisk_size=0, signature_size=0)

The arm64 Linux Image header has its magic string "ARMd" at offset 0x38 (56),
NOT at offset 0. So the real kernel start = magic_pos - 56.

Size policy: the stock kernel's true in-memory size (Image header, +0x10)
defines the proven envelope - the stock file itself extends past kernel_end
(tail + BSS in zero area). A larger kernel is placed fully and kernel_size is
bumped to its exact size; total file size stays constant.
"""
import struct
import sys

KERNEL_MAGIC = b"ARM\x64"   # == b"ARMd" : arm64 Image header magic
MAGIC_OFFSET = 0x38         # offset of the magic inside the arm64 Image


def find_magic(data: bytes) -> int:
    idx = data.find(KERNEL_MAGIC, 2048, 200000)
    if idx < 0:
        raise SystemExit("ERROR: ARM64 kernel magic not found in boot.img")
    return idx


def main() -> None:
    stock_boot = sys.argv[1]
    kernel_img = sys.argv[2]
    out_boot = sys.argv[3]

    with open(stock_boot, "rb") as f:
        data = bytearray(f.read())

    magic_pos = find_magic(data)
    kernel_start = magic_pos - MAGIC_OFFSET   # e.g. 4152 - 56 = 4096
    if kernel_start < 0:
        raise SystemExit("ERROR: bad kernel_start")

    # kernel region total size from the mkbootimg header (offset 8), page-aligned start to end
    kernel_end = struct.unpack_from("<I", data, 8)[0]  # 48658944
    if kernel_end > len(data) or kernel_end <= kernel_start:
        raise SystemExit(f"ERROR: kernel_end {kernel_end} invalid (kernel_start {kernel_start})")

    with open(kernel_img, "rb") as f:
        new_kernel = f.read()

    # Envelope, self-calibrated from the stock input (no magic numbers).
    stock_true = struct.unpack_from("<Q", data, kernel_start + 0x10)[0]
    if stock_true <= 0 or stock_true > len(data) - kernel_start:
        raise SystemExit(f"ERROR: stock true size {stock_true} implausible")
    limit = max(kernel_end - kernel_start - 4096, stock_true)
    if len(new_kernel) > limit:
        raise SystemExit(f"ERROR: new kernel {len(new_kernel)} exceeds proven envelope {limit}")

    print(f"magic_pos={magic_pos} kernel_start={kernel_start} "
          f"kernel_end={kernel_end} stock_true={stock_true} limit={limit} "
          f"new_kernel={len(new_kernel)}")

    # place the new kernel in full (same-length slice: total size constant)
    data[kernel_start:kernel_start + len(new_kernel)] = new_kernel
    # zero the old tail only within the original region (smaller kernels)
    region_len = kernel_end - kernel_start
    if len(new_kernel) < region_len:
        data[kernel_start + len(new_kernel):kernel_end] = b"\x00" * (region_len - len(new_kernel))
    # the bootloader loads kernel_size bytes: bump it when the new kernel
    # is larger (ramdisk/signature are empty, so nothing shifts)
    if len(new_kernel) > region_len:
        struct.pack_into("<I", data, 8, len(new_kernel))
        print(f"kernel_size bumped to {len(new_kernel)}")

    # sanity: magic must now be at kernel_start + 0x38
    if data.find(KERNEL_MAGIC, kernel_start, kernel_start + 4096) != kernel_start + MAGIC_OFFSET:
        raise SystemExit("ERROR: post-splice magic check failed")

    with open(out_boot, "wb") as f:
        f.write(data)
    print(f"OK: wrote {out_boot} ({len(data)} bytes)")


if __name__ == "__main__":
    main()