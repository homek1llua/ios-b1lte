/* SPDX-License-Identifier: BSD-2-Clause
 * B2L root is journaled HFS+, not APFS. iOS 26 installd/installcoordinationd
 * refuse every install with MIInstallerErrorDomain 166 "Expected install path
 * file:///private/var/ to be located on an APFS formatted volume; got hfs"
 * (-[MIStagingManager stagingLocationForURL:...]). Report "apfs" for the root
 * mount to the installer daemons and their XPC helper only (statfs/getattrlist type name);
 * every other process and the kernel still see "hfs". Kill switch:
 * boot-arg b2l_apfs_fstype=0. copyfile(COPYFILE_CLONE) falls back to a copy
 * when clonefile is not supported by HFS. */
#ifndef B2L_FSTYPE_H
#define B2L_FSTYPE_H
#include <sys/proc.h>
#include <pexpert/pexpert.h>
static const char b2l_apfs_name[] = "apfs";
static inline bool
b2l_fstype_spoof_apfs(mount_t mp)
{
	static int enabled = -1;
	if (enabled < 0) {
		int v = 1;
		PE_parse_boot_argn("b2l_apfs_fstype", &v, sizeof(v));
		enabled = v ? 1 : 0;
	}
	if (!enabled || mp == NULL || !(mp->mnt_flag & MNT_ROOTFS) ||
	    strncmp(mp->mnt_vfsstat.f_fstypename, "hfs", sizeof("hfs")) != 0) {
		return false;
	}
	/* p_name keeps 2 * MAXCOMLEN (32) bytes. The APFS check itself runs in
	 * MobileInstallation's XPC helper (B1L-0021 logs: 166 still raised;
	 * the format string lives only in com.apple.MobileInstallationHelperService),
	 * whose p_name reads "com.apple.MobileInstallationHelp". */
	char name[2 * MAXCOMLEN + 1];
	proc_selfname(name, sizeof(name));
	/* S10 build 0041: and fileproviderd -- FPVolumeFPFSSupported() wants an APFS home volume; refused, -[FPDDomain
	 * volume] stayed nil and fileproviderd asserted (FPDDomain.m:218), so Files and Safari's downloads had no storage */
	return strcmp(name, "installd") == 0 || strcmp(name, "fileproviderd") == 0 ||
	    strcmp(name, "installcoordinationd") == 0 ||
	    strncmp(name, "com.apple.MobileInstallationHelperService", 2 * MAXCOMLEN) == 0;
}
#endif
