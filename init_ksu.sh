#!/usr/bin/env bash
set -euo pipefail
# init_ksu.sh – Classic KernelSU ONLY (SUSFS disabled for isolation test)
# KSU-only build to determine if SUSFS patches cause the bootloop.

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

# ── 2. SUSFS KIHAGYVA (KSU-only izolációs build) ─
# Skipped: simonpunk clone, 50_add patch, fs/include copy, 10_enable patch, namespace.c fix
echo "[SUSFS] SKIPPED for KSU-only isolation build"

# ── 7. Pin kernel release string (module compat) ─
echo "[VER] 5.15.211-g093e3da978e7"
touch "${KERNEL_ROOT}/.scmversion"

# ── 8. Append KSU + SUSFS config symbols ─
sed -i '/# KernelSU + SUSFS BEGIN/,/# KernelSU + SUSFS END/d' "${DEFCONFIG}" 2>/dev/null || true
cat >> "${DEFCONFIG}" << 'CONFEOF'
# KernelSU (KSU-only, NO SUSFS) BEGIN
CONFIG_KSU=y
# CONFIG_KSU_SUSFS is not set
CONFIG_DEBUG_INFO_BTF=n
CONFIG_INITCALL_DEBUG=y
CONFIG_MODVERSIONS=n
CONFIG_PSTORE=y
CONFIG_PSTORE_CONSOLE=y
CONFIG_PSTORE_PMSG=y
CONFIG_PSTORE_RAM=y
CONFIG_LOCALVERSION="-g093e3da978e7"
CONFIG_LOCALVERSION_AUTO=n
# KernelSU (KSU-only, NO SUSFS) END
CONFEOF

echo "============================================================="
echo " Classic KSU ONLY (no SUSFS) – ready"
echo "============================================================="