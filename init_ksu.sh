#!/usr/bin/env bash
set -euo pipefail
# init_ksu.sh - KernelSU-Next (pershoot/next-susfs) + SUSFS for LOS 5.15 kernel
# 1. Clone pershoot/KernelSU-Next next-susfs
# 2. Symlink drivers/kernelsu -> KernelSU-Next/kernel
# 3. Inject drivers/Makefile + drivers/Kconfig entries
# 4. Clone simonpunk/susfs4ksu (gitlab, gki-android13-5.15)
# 5. Apply 50_add_susfs_in_gki-android13-5.15.patch (fuzz) + fs/ include/ copies
# 6. Manual namespace.c extern fix (hunk 1 rejects on LOS extra includes)
# 7. Create include/linux/susfs.h shim (pershoot's core_hook.c expects it)
# 8. Pin EXACT kernel release 5.15.211-g093e3da978e7 (module compat)
# 9. Append KSU + SUSFS symbols to gki_defconfig

KERNEL_ROOT="$(pwd)"
KSU_DIR="${KERNEL_ROOT}/KernelSU-Next"
SUSFS_DIR="${KERNEL_ROOT}/susfs4ksu"
DEFCONFIG="${KERNEL_ROOT}/arch/arm64/configs/gki_defconfig"

# ---- 1. Clone pershoot/KernelSU-Next next-susfs ----
echo "[KSU] Cloning pershoot/KernelSU-Next next-susfs..."
if [[ -d "${KSU_DIR}/.git" ]]; then
    git -C "${KSU_DIR}" fetch origin next-susfs
    git -C "${KSU_DIR}" checkout -B next-susfs origin/next-susfs
else
    git clone --depth=1 --branch next-susfs \
        https://github.com/pershoot/KernelSU-Next.git "${KSU_DIR}"
fi
KSU_VERSION="$(git -C "${KSU_DIR}" describe --tags --always 2>/dev/null || echo unknown)"
echo "[KSU] Version: ${KSU_VERSION}"

# ---- 2. Symlink drivers/kernelsu ----
echo "[KSU] Symlink drivers/kernelsu -> KernelSU-Next/kernel/"
rm -f "${KERNEL_ROOT}/drivers/kernelsu"
ln -sf "${KSU_DIR}/kernel" "${KERNEL_ROOT}/drivers/kernelsu"

# ---- 3. drivers/Makefile ----
grep -q "kernelsu" "${KERNEL_ROOT}/drivers/Makefile" || \
    printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> "${KERNEL_ROOT}/drivers/Makefile"

# ---- 4. drivers/Kconfig ----
grep -q "kernelsu" "${KERNEL_ROOT}/drivers/Kconfig" || \
    sed -i '/^endmenu/i source "drivers/kernelsu/Kconfig"' "${KERNEL_ROOT}/drivers/Kconfig"

# ---- 5. Clone susfs4ksu (gitlab - the github mirror is unreliable) ----
SUSFS_BRANCH="gki-android13-5.15"
echo "[SUSFS] Cloning susfs4ksu ${SUSFS_BRANCH} (gitlab)..."
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

SUSFS_PATCH="${SUSFS_DIR}/kernel_patches/50_add_susfs_in_gki-android13-5.15.patch"
if [[ ! -f "${SUSFS_PATCH}" ]]; then
    echo "[SUSFS] ERROR: patch not found at ${SUSFS_PATCH}"
    ls "${SUSFS_DIR}/kernel_patches/" 2>/dev/null || true
    exit 1
fi

# ---- 6. Apply the kernel fs patch (fuzz) ----
echo "[SUSFS] Applying $(basename "${SUSFS_PATCH}") (fuzz=4)..."
patch -p1 --fuzz=4 --forward < "${SUSFS_PATCH}" || true
echo "--- new rejects: ---"
find . -name "*.rej" -newer "${SUSFS_DIR}" -print | head

# namespace.c hunk 1 (include + extern block) rejects on LOS -> apply manually
NS_FILE="${KERNEL_ROOT}/fs/namespace.c"
if grep -q "susfs_is_current_ksu_domain" "${NS_FILE}"; then
    echo "[SUSFS] namespace.c extern already present, skipping"
else
    echo "[SUSFS] Injecting namespace.c extern declarations manually..."
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
fi
rm -f fs/namespace.c.rej

# ---- 7. Create include/linux/susfs.h shim (pershoot expects susfs.h) ----
echo "[SHIM] Creating include/linux/susfs.h shim..."
bash "$(dirname "$0")/susfs_header_shim.sh" "${KERNEL_ROOT}"

# ---- 8. Pin EXACT kernel release string for module compat ----
echo "[VER] Pinning kernel release: 5.15.211-g093e3da978e7"
touch "${KERNEL_ROOT}/.scmversion"

# ---- 9. Append KSU + SUSFS symbols to gki_defconfig ----
echo "[CFG] Appending KSU + SUSFS symbols to gki_defconfig..."
sed -i '/# KernelSU-Next + SUSFS BEGIN/,/# KernelSU-Next + SUSFS END/d' "${DEFCONFIG}" 2>/dev/null || true
cat >> "${DEFCONFIG}" << 'CONFEOF'
# KernelSU-Next + SUSFS BEGIN
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
CONFIG_LOCALVERSION="-g093e3da978e7"
CONFIG_LOCALVERSION_AUTO=n
# KernelSU-Next + SUSFS END
CONFEOF

echo "============================================================="
echo " KernelSU-Next ${KSU_VERSION} + SUSFS configured"
echo "============================================================="