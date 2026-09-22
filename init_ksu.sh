#!/usr/bin/env bash
set -euo pipefail
# init_ksu.sh - KernelSU-Next (pershoot) + SUSFS v1.5.12 (OLD API) for LOS 5.15 kernel
#
# Three sources (all cloned here):
#   1. github.com/pershoot/KernelSU-Next            @ next-susfs              -> KSU driver
#   2. gitlab.com/pershoot/susfs4ksu                @ aosp-android14-6.1-dev_122425 -> SUSFS v1.5.12 OLD API source
#                                                                              (fs/susfs.c, include/linux/susfs*.h)
#   3. gitlab.com/simonpunk/susfs4ksu               @ master                  -> OLD API kernel fs patch
#                                                                              (50_add_susfs_in_kernel-5.4.patch)
#
# No shim needed: the pershoot 122425 branch natively provides all the symbols
# (CMD_SUSFS_*, DATA_ADB_*, SUSFS_VERSION, SUSFS_VARIANT, typed susfs_set_uname).

KERNEL_ROOT="$(pwd)"
KSU_DIR="${KERNEL_ROOT}/KernelSU-Next"
SUSFS_PER="${KERNEL_ROOT}/susfs4ksu-pershoot"   # v1.5.12 OLD API
SUSFS_SIM="${KERNEL_ROOT}/susfs4ksu-simonpunk"  # master (kernel fs patch only)
DEFCONFIG="${KERNEL_ROOT}/arch/arm64/configs/gki_defconfig"

# ---- 1. pershoot/KernelSU-Next @ next-susfs (KSU driver) ----
echo "[KSU] Cloning pershoot/KernelSU-Next next-susfs..."
rm -rf "${KSU_DIR}"
git clone --depth=1 --branch next-susfs \
    https://github.com/pershoot/KernelSU-Next.git "${KSU_DIR}"
# shallow clone has no origin/HEAD -> make git resolve it (avoids build-time git errors)
git -C "${KSU_DIR}" remote set-head origin --auto || true
KSU_VERSION="$(git -C "${KSU_DIR}" describe --tags --always 2>/dev/null || echo unknown)"
echo "[KSU] Version: ${KSU_VERSION}"

# symlink + inject
rm -f "${KERNEL_ROOT}/drivers/kernelsu"
ln -sf "${KSU_DIR}/kernel" "${KERNEL_ROOT}/drivers/kernelsu"
grep -q "kernelsu" "${KERNEL_ROOT}/drivers/Makefile" || \
    printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> "${KERNEL_ROOT}/drivers/Makefile"
grep -q "kernelsu" "${KERNEL_ROOT}/drivers/Kconfig" || \
    sed -i '/^endmenu/i source "drivers/kernelsu/Kconfig"' "${KERNEL_ROOT}/drivers/Kconfig"

# ---- 2. pershoot/susfs4ksu @ aosp-android14-6.1-dev_122425 (SUSFS v1.5.12 OLD API) ----
SUSFS_PER_BRANCH="aosp-android14-6.1-dev_122425"
echo "[SUSFS] Cloning pershoot/susfs4ksu ${SUSFS_PER_BRANCH} (v1.5.12 OLD API)..."
rm -rf "${SUSFS_PER}"
git clone --depth=1 --branch "${SUSFS_PER_BRANCH}" \
    https://gitlab.com/pershoot/susfs4ksu.git "${SUSFS_PER}"

# copy the SUSFS v1.5.12 kernel sources into the tree
echo "[SUSFS] Installing fs/susfs + include/linux/susfs*.h from pershoot 122425..."
if [[ -d "${SUSFS_PER}/kernel_patches/fs" ]]; then
    cp -r "${SUSFS_PER}/kernel_patches/fs/"* "${KERNEL_ROOT}/fs/"
fi
if [[ -d "${SUSFS_PER}/kernel_patches/include" ]]; then
    cp -r "${SUSFS_PER}/kernel_patches/include/"* "${KERNEL_ROOT}/include/"
fi

# ---- 3. simonpunk/susfs4ksu @ gki-android13-5.15 (OLD API kernel fs patch for 5.15) ----
SUSFS_SIM_BRANCH="gki-android13-5.15"
echo "[SUSFS] Cloning simonpunk/susfs4ksu ${SUSFS_SIM_BRANCH}..."
rm -rf "${SUSFS_SIM}"
git clone --depth=1 --branch "${SUSFS_SIM_BRANCH}" \
    https://gitlab.com/simonpunk/susfs4ksu.git "${SUSFS_SIM}"

SUSFS_PATCH="${SUSFS_SIM}/kernel_patches/50_add_susfs_in_gki-android13-5.15.patch"
if [[ ! -f "${SUSFS_PATCH}" ]]; then
    echo "[SUSFS] ERROR: patch not found at ${SUSFS_PATCH}"
    ls "${SUSFS_SIM}/kernel_patches/" 2>/dev/null || true
    exit 1
fi

echo "[SUSFS] Applying $(basename "${SUSFS_PATCH}") (fuzz=4)..."
patch -p1 --fuzz=4 --forward < "${SUSFS_PATCH}" || true
echo "--- rejects: ---"
find . -name "*.rej" -newer "${SUSFS_SIM}" -print | head

# fs/namespace.c hunk 1 (include + extern block) rejects on LOS -> apply manually
NS_FILE="${KERNEL_ROOT}/fs/namespace.c"
if ! grep -q "susfs_is_current_ksu_domain" "${NS_FILE}"; then
    echo "[SUSFS] Injecting fs/namespace.c extern declarations manually..."
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

# strip git-based KSU version generation so a shallow clone (no origin/HEAD) won't fail the build
sed -i 's|KSU_GIT_TAG := $(shell cd $(GIT_ROOT) && $(LPATH) git describe --tags --abbrev=0 2>/dev/null)|KSU_GIT_TAG := v3.3.0|g' "${KSU_DIR}/kernel/Kbuild"
sed -i 's|KSU_GIT_VERSION := $(shell cd $(GIT_ROOT) && $(LPATH) git rev-list --count HEAD 2>/dev/null)|KSU_GIT_VERSION := 3014|g' "${KSU_DIR}/kernel/Kbuild"

# ---- 4. Pin EXACT kernel release string (module compat) ----
echo "[VER] Pinning kernel release: 5.15.211-g093e3da978e7"
touch "${KERNEL_ROOT}/.scmversion"

# ---- 5. Append KSU + SUSFS symbols to gki_defconfig ----
echo "[CFG] Appending KSU + SUSFS symbols to gki_defconfig..."
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
CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
CONFIG_KSU_SUSFS_SUS_KMODULES=y
CONFIG_KSU_SUSFS_SUS_SU=y
CONFIG_KSU_SUSFS_SUS_BIND_MOUNT=y
CONFIG_KSU_SUSFS_SPOOF_UNAME=y
CONFIG_KSU_SUSFS_ENABLE_LOG=y
CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y
CONFIG_LOCKDEP=n
CONFIG_LOCALVERSION="-g093e3da978e7"
CONFIG_LOCALVERSION_AUTO=n
# KernelSU + SUSFS END
CONFEOF

echo "============================================================="
echo " KernelSU-Next ${KSU_VERSION} + SUSFS v1.5.12 configured"
echo "============================================================="