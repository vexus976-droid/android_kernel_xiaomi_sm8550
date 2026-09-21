#!/bin/bash
# KernelSU-Next + SUSFS setup for LineageOS kernel (fuxi 5.15.211)
set -eu

KERNEL_ROOT=$(pwd)
echo "[*] KernelSU-Next + SUSFS init"

# KernelSU-Next (stable-susfs line, legacy-susfs ref for 5.15)
curl -LSs "https://raw.githubusercontent.com/Gamesmes90/KernelSU-Next/refs/heads/stable-susfs/kernel/setup.sh" | bash -s legacy-susfs

# Spoof KSU Next version
sed -i 's|KSU_GIT_TAG := $(shell cd $(GIT_ROOT) && $(LPATH) git describe --tags --abbrev=0 2>/dev/null)|KSU_GIT_TAG := v3.3.0|g' KernelSU-Next/kernel/Kbuild
sed -i 's|KSU_GIT_VERSION := $(shell cd $(GIT_ROOT) && $(LPATH) git rev-list --count HEAD 2>/dev/null)|KSU_GIT_VERSION := 3014|g' KernelSU-Next/kernel/Kbuild

# SUSFS kernel patches (gki-android13-5.15)
echo "[*] Applying SUSFS patches"
git clone --depth=1 -b gki-android13-5.15 https://gitlab.com/simonpunk/susfs4ksu.git /tmp/susfs
cp -r /tmp/susfs/kernel_patches/fs/* fs/
cp -r /tmp/susfs/kernel_patches/include/linux/* include/linux/

# LOS 5.15.211 has extra trace/hooks includes -> run patch with fuzz;
# hunk 1 of fs/namespace.c (include insertion) is expected to be rejected and is
# applied manually below.
patch -p1 --fuzz=4 --forward < /tmp/susfs/kernel_patches/50_add_susfs_in_gki-android13-5.15.patch || true
echo "--- new rejects (ignoring pre-existing): ---"
find . -name "*.rej" -newer /tmp/susfs -print | head

echo "[*] Applying fs/namespace.c SUSFS changes manually"
python3 - <<'PYEOF'
p = 'fs/namespace.c'
src = open(p).read()

inc_old = '#include <linux/mnt_idmapping.h>\n'
inc_new = inc_old + '''#ifdef CONFIG_KSU_SUSFS
#include <linux/susfs_def.h>
#endif // #ifdef CONFIG_KSU_SUSFS
'''
if 'susfs_def.h' not in src:
    src = src.replace(inc_old, inc_new, 1)

ext_old = '#include "internal.h"\n'
ext_new = ext_old + '''#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT
extern bool susfs_is_current_ksu_domain(void);
extern struct static_key_true susfs_is_sdcard_android_data_not_decrypted;

#define CL_COPY_MNT_NS BIT(25) /* used by copy_mnt_ns() */
#endif // #ifdef CONFIG_KSU_SUSFS_SUS_MOUNT
'''
if 'extern bool susfs_is_current_ksu_domain' not in src:
    src = src.replace(ext_old, ext_new, 1)

open(p, 'w').write(src)
print('namespace.c patched')
PYEOF

# make sure the rejected namespace.c hunk is gone from disk
rm -f fs/namespace.c.rej

cp /tmp/susfs/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch KernelSU-Next/
cd KernelSU-Next
patch -p1 --forward < 10_enable_susfs_for_ksu.patch || true
cd "$KERNEL_ROOT"

# Force exact kernel release string to keep module compat: 5.15.211-g093e3da978e7
echo "[*] Pinning kernel version string"
touch .scmversion
cat >> arch/arm64/configs/gki_defconfig <<'EOF'

# KernelSU-Next + SUSFS
CONFIG_KSU=y
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_SUS_PATH=y
CONFIG_KSU_SUSFS_SUS_MOUNT=y
CONFIG_KSU_SUSFS_SUS_KSTAT=y
CONFIG_KSU_SUSFS_SUS_MAP=y
CONFIG_KSU_SUSFS_SUS_OVERLAYFS=y
CONFIG_KSU_SUSFS_SUS_MMAP_RWX=y
CONFIG_KSU_SUSFS_TRY_UMOUNT=y
CONFIG_KSU_SUSFS_AUTO_ADD_SUS_KSU_DEFAULT_MNT=y
CONFIG_KSU_SUSFS_SUS_SU=y
CONFIG_KSU_SUSFS_SUS_BIND_MOUNT=y
CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
CONFIG_KSU_SUSFS_SUS_KMODULES=y

# SUSFS custom
CONFIG_LOCALVERSION="-g093e3da978e7"
CONFIG_LOCALVERSION_AUTO=n
EOF

echo "[*] Done. KernelSU-Next + SUSFS applied."