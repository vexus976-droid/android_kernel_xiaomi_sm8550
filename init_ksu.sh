#!/bin/bash
# KernelSU-Next + SUSFS setup for LineageOS kernel
set -eu

KERNEL_ROOT=$(pwd)
echo "[*] KernelSU-Next + SUSFS init"

# KernelSU-Next (stable-susfs line, legacy-susfs for 5.15)
curl -LSs "https://raw.githubusercontent.com/Gamesmes90/KernelSU-Next/refs/heads/stable-susfs/kernel/setup.sh" | bash -s legacy-susfs

# Spoof KSU Next version
sed -i 's|KSU_GIT_TAG := $(shell cd $(GIT_ROOT) && $(LPATH) git describe --tags --abbrev=0 2>/dev/null)|KSU_GIT_TAG := v3.3.0|g' KernelSU-Next/kernel/Kbuild
sed -i 's|KSU_GIT_VERSION := $(shell cd $(GIT_ROOT) && $(LPATH) git rev-list --count HEAD 2>/dev/null)|KSU_GIT_VERSION := 3014|g' KernelSU-Next/kernel/Kbuild

# SUSFS kernel patches (gki-android13-5.15)
echo "[*] Applying SUSFS patches"
git clone --depth=1 -b gki-android13-5.15 https://gitlab.com/simonpunk/susfs4ksu.git /tmp/susfs
cp -r /tmp/susfs/kernel_patches/fs/* fs/
cp -r /tmp/susfs/kernel_patches/include/linux/* include/linux/
patch -p1 < /tmp/susfs/kernel_patches/50_add_susfs_in_gki-android13-5.15.patch
cp /tmp/susfs/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch KernelSU-Next/
cd KernelSU-Next
patch -p1 --forward < 10_enable_susfs_for_ksu.patch || true
cd "$KERNEL_ROOT"

# Force exact kernel release string to keep module compat: 5.15.211-g093e3da978e7
echo "[*] Pinning kernel version string"
touch .scmversion
cat >> arch/arm64/configs/gki_defconfig <<'EOF'

# SUSFS custom
CONFIG_LOCALVERSION="-g093e3da978e7"
CONFIG_LOCALVERSION_AUTO=n
EOF

echo "[*] Done. KernelSU-Next + SUSFS applied."