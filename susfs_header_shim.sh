#!/usr/bin/env bash
# susfs_header_shim.sh
# Creates include/linux/susfs.h with correct typed signatures for pershoot's core_hook.c

KERNEL_ROOT="${1:-$(pwd)}"
INCLUDE_DIR="${KERNEL_ROOT}/include/linux"

echo "[SHIM] Creating ${INCLUDE_DIR}/susfs.h..."

cat > "${INCLUDE_DIR}/susfs.h" << 'SUSFS_H'
/* SPDX-License-Identifier: GPL-2.0-only */
/* susfs.h - kernel-side SUSFS API for KernelSU-Next (pershoot/next-susfs) */
#ifndef _LINUX_SUSFS_H
#define _LINUX_SUSFS_H

#include <linux/types.h>
#include <linux/uaccess.h>

#ifdef CONFIG_KSU_SUSFS

/* uname spoofing - typed struct pointer (pershoot expects this, not void**) */
struct st_susfs_uname {
    char    sysname[65];
    char    nodename[65];
    char    release[65];
    char    version[65];
    char    machine[65];
};

struct st_susfs_sus_path {
    char           target_pathname[256];
    unsigned long  target_ino;
};

struct st_susfs_try_umount {
    char           target_pathname[256];
    int            mnt_mode;
};

struct st_susfs_sus_kstat {
    unsigned long  target_ino;
    char           target_pathname[256];
    char           spoofed_pathname[256];
    unsigned long  spoofed_ino;
    unsigned long  spoofed_dev;
    unsigned long  spoofed_nlink;
    long long      spoofed_size;
    long           spoofed_atime_tv_sec;
    long           spoofed_mtime_tv_sec;
    long           spoofed_ctime_tv_sec;
    long           spoofed_blksize;
    long long      spoofed_blocks;
};

struct st_susfs_open_redirect {
    unsigned long  target_ino;
    char           target_pathname[256];
    char           redirected_pathname[256];
};

/* Function declarations matching pershoot's core_hook.c call sites */
#ifdef CONFIG_KSU_SUSFS_SUS_PATH
extern int  susfs_add_sus_path(struct st_susfs_sus_path __user *user_info);
extern int  susfs_sus_ino_for_filldir64(unsigned long *ino);
#endif

#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT
extern int  susfs_add_sus_mount(void *user_info);
#endif

#ifdef CONFIG_KSU_SUSFS_SUS_KSTAT
extern int  susfs_add_sus_kstat(struct st_susfs_sus_kstat __user *user_info);
extern int  susfs_sus_kstat(unsigned long ino, struct kstat *stat);
#endif

#ifdef CONFIG_KSU_SUSFS_TRY_UMOUNT
extern int  susfs_add_try_umount(struct st_susfs_try_umount __user *user_info);
extern void susfs_try_umount(int flags);
#endif

#ifdef CONFIG_KSU_SUSFS_SPOOF_UNAME
extern int  susfs_set_uname(struct st_susfs_uname __user *uname);
#endif

#ifdef CONFIG_KSU_SUSFS_ENABLE_LOG
extern void susfs_set_log(int enabled);
#endif

#ifdef CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG
extern int  susfs_set_cmdline_or_bootconfig(char __user *cmdline);
#endif

#ifdef CONFIG_KSU_SUSFS_OPEN_REDIRECT
extern int  susfs_add_open_redirect(struct st_susfs_open_redirect __user *user_info);
#endif

extern bool susfs_is_current_ksu_domain(void);

#endif /* CONFIG_KSU_SUSFS */
#endif /* _LINUX_SUSFS_H */
SUSFS_H

echo "[SHIM] ${INCLUDE_DIR}/susfs.h written"
if grep -q "susfs_set_uname" "${INCLUDE_DIR}/susfs.h"; then
    echo "[SHIM] susfs_set_uname declaration present OK"
else
    echo "[SHIM] WARNING: susfs_set_uname not found"
fi