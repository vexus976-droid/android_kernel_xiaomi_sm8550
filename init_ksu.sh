#!/usr/bin/env bash
set -euo pipefail
# init_ksu.sh – Classic KernelSU + simonpunk SUSFS (gki-android13-5.15)
# This is the "battle-tested" pairing that susfs4ksu was originally designed for.
# NO pershoot forks, NO version mixing — one coherent API generation.

KERNEL_ROOT="$(pwd)"
KSU_DIR="${KERNEL_ROOT}/KernelSU"
SUSFS_DIR="${KERNEL_ROOT}/susfs4ksu"
DEFCONFIG="${KERNEL_ROOT}/arch/arm64/configs/gki_defconfig"
SUSFS_BRANCH="gki-android13-5.15"

# ── 1. Clone classic KernelSU (tiann) – 10_enable_susfs_for_ksu.patch is FOR this layout ─
echo "[KSU] Cloning tiann/KernelSU (classic)..."
rm -rf "${KSU_DIR}"
git clone --depth=1 https://github.com/tiann/KernelSU.git "${KSU_DIR}"
echo "[KSU] Version: $(git -C "${KSU_DIR}" describe --tags --always 2>/dev/null || echo unknown)"

rm -f "${KERNEL_ROOT}/drivers/kernelsu"
ln -sf "${KSU_DIR}/kernel" "${KERNEL_ROOT}/drivers/kernelsu"
grep -q "kernelsu" "${KERNEL_ROOT}/drivers/Makefile" || \
    printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> "${KERNEL_ROOT}/drivers/Makefile"
grep -q "kernelsu" "${KERNEL_ROOT}/drivers/Kconfig" || \
    sed -i '/^endmenu/i source "drivers/kernelsu/Kconfig"' "${KERNEL_ROOT}/drivers/Kconfig"

# ── 2. Clone simonpunk/susfs4ksu (gki-android13-5.15) – ALL SUSFS from here ─
echo "[SUSFS] Cloning simonpunk/susfs4ksu ${SUSFS_BRANCH}..."
rm -rf "${SUSFS_DIR}"
git clone --depth=1 --branch "${SUSFS_BRANCH}" https://gitlab.com/simonpunk/susfs4ksu.git "${SUSFS_DIR}"

# ── 3. Apply 50_add kernel fs patch (susfs hooks into kernel source) ─
SUSFS_PATCH="${SUSFS_DIR}/kernel_patches/50_add_susfs_in_gki-android13-5.15.patch"
echo "[SUSFS] Applying $(basename "${SUSFS_PATCH}") (fuzz=4)"
patch -p1 --fuzz=4 --forward < "${SUSFS_PATCH}" || true
echo "--- rejects: ---"
find . -name "*.rej" -newer "${SUSFS_DIR}" -print | head

# ── 4. Copy fs/susfs + include/linux/susfs*.h ─
echo "[SUSFS] Copying fs/ + include/"
cp -r "${SUSFS_DIR}/kernel_patches/fs/"* "${KERNEL_ROOT}/fs/"
cp -r "${SUSFS_DIR}/kernel_patches/include/"* "${KERNEL_ROOT}/include/"

# ── 5. Apply 10_enable_susfs_for_ksu.patch INTO classic KernelSU ─
echo "[SUSFS] Applying 10_enable_susfs_for_ksu.patch into KernelSU"
cp "${SUSFS_DIR}/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch" "${KSU_DIR}/kernel/"
( cd "${KSU_DIR}/kernel" && patch -p1 --forward < 10_enable_susfs_for_ksu.patch ) || true

# ── 6. Manual namespace.c extern fix (hunk 1 rejects on LOS extra trace/hooks includes) ─
NS_FILE="${KERNEL_ROOT}/fs/namespace.c"
if ! grep -q "susfs_is_current_ksu_domain" "${NS_FILE}"; then
    echo "[SUSFS] namespace.c: injecting externs manually"
    python3 - <<'PYEOF'
p = 'fs/namespace.c'; src = open(p).read()
inc_old = '#include <linux/mnt_idmapping.h>\n'
if 'susfs_def.h' not in src:
    src = src.replace(inc_old, inc_old + '#ifdef CONFIG_KSU_SUSFS\n#include <linux/susfs_def.h>\n#endif // #ifdef CONFIG_KSU_SUSFS\n', 1)
ext_old = '#include "internal.h"\n'
if 'susfs_is_current_ksu_domain' not in src:
    src = src.replace(ext_old, ext_old + '#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\nextern bool susfs_is_current_ksu_domain(void);\nextern struct static_key_true susfs_is_sdcard_android_data_not_decrypted;\n\n#define CL_COPY_MNT_NS BIT(25)\n#endif // #ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n', 1)
open(p, 'w').write(src); print('patched')
PYEOF
fi
rm -f fs/namespace.c.rej

# ── 7. Pin kernel release string (module compat) ─
echo "[VER] 5.15.211-g093e3da978e7"
touch "${KERNEL_ROOT}/.scmversion"

# ── 8. Append KSU + SUSFS config symbols ─
sed -i '/# KernelSU + SUSFS BEGIN/,/# KernelSU + SUSFS END/d' "${DEFCONFIG}" 2>/dev/null || true
cat >> "${DEFCONFIG}" << 'CONFEOF'
# KernelSU + SUSFS BEGIN
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
# KernelSU + SUSFS END
CONFEOF

echo "============================================================="
echo " Classic KSU + simonpunk SUSFS ${SUSFS_BRANCH} – ready"
echo "============================================================="