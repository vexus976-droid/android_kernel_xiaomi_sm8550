#!/usr/bin/env bash
set -euo pipefail
# init_ksu.sh - KernelSU-Next (pershoot next-susfs) + SUSFS for LOS 5.15 kernel
#
# 1. Clone pershoot/KernelSU-Next (next-susfs) via simonpunk SUSFS kernel patches.
# 2. Symlink drivers/kernelsu -> KernelSU-Next/kernel/
# 3. Inject obj-y into drivers/Makefile and source into drivers/Kconfig
# 4. Apply SUSFS kernel-side fs patch (50_add_susfs_in_gki-android13-5.15.patch)
#    We do NOT apply 10_enable_susfs_for_ksu.patch (classic tiann KernelSU only).
# 5. Force exact kernel release string "5.15.211-g093e3da978e7" for module compat.
# 6. Append KSU/SUSFS config symbols to gki_defconfig.

KERNEL_ROOT="$(pwd)"
KSU_DIR="${KERNEL_ROOT}/KernelSU-Next"
SUSFS_DIR="${KERNEL_ROOT}/susfs4ksu"

# ---- 1. Clone pershoot/KernelSU-Next next-susfs ----
echo "[KSU] Cloning pershoot/KernelSU-Next next-susfs..."
if [[ -d "${KSU_DIR}/.git" ]]; then
    echo "[KSU] Already cloned, fetching..."
    git -C "${KSU_DIR}" fetch origin next-susfs
    git -C "${KSU_DIR}" checkout -B next-susfs origin/next-susfs
else
    git clone --depth=1 --branch next-susfs \
        https://github.com/pershoot/KernelSU-Next.git "${KSU_DIR}"
fi
KSU_VERSION="$(git -C "${KSU_DIR}" describe --tags --always 2>/dev/null || echo unknown)"
echo "[KSU] Version: ${KSU_VERSION}"

# ---- 2. Wire drivers/kernelsu symlink ----
echo "[KSU] Symlink drivers/kernelsu -> KernelSU-Next/kernel/"
rm -f "${KERNEL_ROOT}/drivers/kernelsu"
ln -sf "${KSU_DIR}/kernel" "${KERNEL_ROOT}/drivers/kernelsu"

# ---- 3. drivers/Makefile ----
if ! grep -q "kernelsu" "${KERNEL_ROOT}/drivers/Makefile"; then
    printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> "${KERNEL_ROOT}/drivers/Makefile"
fi

# ---- 4. drivers/Kconfig ----
if ! grep -q "kernelsu" "${KERNEL_ROOT}/drivers/Kconfig"; then
    sed -i '/^endmenu/i source "drivers/kernelsu/Kconfig"' "${KERNEL_ROOT}/drivers/Kconfig"
fi

# ---- 5. Clone SUSFS patches (simonpunk gki-android13-5.15-dev = matches pershoot's newer API) ----
SUSFS_BRANCH="gki-android13-5.15-dev"
echo "[SUSFS] Cloning susfs4ksu ${SUSFS_BRANCH}..."
if [[ -d "${SUSFS_DIR}/.git" ]]; then
    git -C "${SUSFS_DIR}" fetch origin "${SUSFS_BRANCH}"
    git -C "${SUSFS_DIR}" checkout -B "${SUSFS_BRANCH}" "origin/${SUSFS_BRANCH}"
else
    git clone --depth=1 --branch "${SUSFS_BRANCH}" \
        https://gitlab.com/simonpunk/susfs4ksu.git "${SUSFS_DIR}"
fi

echo "[SUSFS] Copying fs/ and include/linux/ sources into kernel tree..."
cp -r "${SUSFS_DIR}/kernel_patches/fs/"* "${KERNEL_ROOT}/fs/"
cp -r "${SUSFS_DIR}/kernel_patches/include/"* "${KERNEL_ROOT}/include/"

PATCH="${SUSFS_DIR}/kernel_patches/50_add_susfs_in_gki-android13-5.15.patch"

# ---- 6. Apply SUSFS kernel fs patch (fuzz for LOS extra includes) ----
echo "[SUSFS] Applying 50_add_susfs_in_gki-android13-5.15.patch (fuzz=4)..."
patch -p1 --fuzz=4 --forward < "${PATCH}" || true
echo "--- new rejects (ignoring pre-existing): ---"
find . -name "*.rej" -newer "${SUSFS_DIR}" -print | head

# fs/namespace.c hunk 1 (include + extern block) rejected on LOS -> apply manually
echo "[SUSFS] Applying fs/namespace.c hunk 1 manually"
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
rm -f fs/namespace.c.rej

# ---- 7. Verify SUSFS config in pershoot Kconfig ----
if [[ -f "${KSU_DIR}/kernel/Kconfig" ]] && grep -q "KSU_SUSFS" "${KSU_DIR}/kernel/Kconfig"; then
    echo "[KSU] CONFIG_KSU_SUSFS present in KernelSU-Next Kconfig OK"
else
    echo "[KSU] WARNING: KSU_SUSFS not found in KernelSU-Next Kconfig"
fi

# ---- 8. Force kernel release string + append config symbols ----
echo "[KSU] Pinning kernel release string + SUSFS config symbols"
touch .scmversion
cat >> arch/arm64/configs/gki_defconfig <<'CONFEOF'

# KernelSU + SUSFS
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
CONFEOF

echo "================================================================"
echo " KernelSU-Next (pershoot/next-susfs ${KSU_VERSION}) + SUSFS OK"
echo "================================================================"