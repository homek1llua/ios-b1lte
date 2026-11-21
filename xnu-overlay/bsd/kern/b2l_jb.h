/* SPDX-License-Identifier: BSD-2-Clause
 * S10 build 0020: a jailbreak environment, put on the root once from SYSTEM before launchd.
 *
 * SYSTEM:/b2l-jb/jb.part0, jb.part1, ... are one GNU tar cut in pieces under 64 MB (the limit of
 * b2l_system_file_copy), made by build-system-image.yml: palera1n's rootless Procursus bootstrap
 * (var/jb/...) and Sileo, whose app sits at Applications/Sileo.app so that LaunchServices finds it as a
 * system app. Only members under var/jb/ or Applications/Sileo.app/ are written: "var/" goes to
 * /private/var/. Regular files, directories, symbolic and hard links, with their modes (setuid kept) and
 * owners. A file that exists is rewritten; a directory or link that exists is left.
 *
 * When every piece is in, LaunchServices' stores are set aside (as b2l_apps_layout does) so that lsd
 * registers Sileo at its next start, and /private/var/db/b2l-jb-v1 is written. Until then each boot tries
 * again. Kill switch: boot-arg b2l_jb=0.
 */
#ifndef B2L_JB_H
#define B2L_JB_H

#define B2L_JB_MARKER "/private/var/db/b2l-jb-v1"

extern int b2l_system_file_copy(const char *, int (*)(void *, uint64_t, const void *, size_t), void *, uint64_t *);

struct b2l_jb_tar {
	vfs_context_t ctx;
	uint8_t hdr[512];
	unsigned hdr_fill;
	uint64_t left;          /* bytes of the current member's data still to come */
	uint64_t pad;           /* bytes of padding after it */
	vnode_t vp;             /* the file being written, or NULL to skip the data */
	uint64_t woff;
	char longname[1024];    /* GNU 'L': the next member's name */
	char longlink[1024];    /* GNU 'K': the next member's link target */
	unsigned long_fill;
	char kind;              /* 'L' or 'K' while gathering a long name, else 0 */
	unsigned files, dirs, links, skipped, errors;
	int first_error;
	char path[MAXPATHLEN];
	char target[MAXPATHLEN];
	unsigned mode, uid, gid;
};

static uint64_t
b2l_jb_octal(const uint8_t *p, size_t n)
{
	uint64_t v = 0;
	if (n && (p[0] & 0x80)) {               /* base-256 */
		for (size_t i = 1; i < n; i++) {
			v = (v << 8) | p[i];
		}
		return v;
	}
	for (size_t i = 0; i < n && p[i]; i++) {
		if (p[i] >= '0' && p[i] <= '7') {
			v = (v << 3) | (uint64_t)(p[i] - '0');
		}
	}
	return v;
}

static void
b2l_jb_fail(struct b2l_jb_tar *t, int e, const char *what)
{
	t->errors++;
	if (!t->first_error) {
		t->first_error = e;
	}
	if (t->errors <= 12) {
		printf("B2L JB: %s %s error=%d\n", what, t->path, e);
	}
}

/* tar name -> absolute path on the root, or 0 if outside what this payload may write */
static int
b2l_jb_map(const char *name, char *out, size_t cap)
{
	while (name[0] == '.' && name[1] == '/') {
		name += 2;
	}
	if (strstr(name, "..")) {
		return 0;
	}
	if (!strncmp(name, "var/jb", 6) && (name[6] == 0 || name[6] == '/')) {
		return (size_t)snprintf(out, cap, "/private/%s", name) < cap;
	}
	if (!strncmp(name, "Applications/Sileo.app", 22) && (name[22] == 0 || name[22] == '/')) {
		return (size_t)snprintf(out, cap, "/%s", name) < cap;
	}
	return 0;
}

static void
b2l_jb_strip_slash(char *p)
{
	size_t n = strlen(p);
	while (n > 1 && p[n - 1] == '/') {
		p[--n] = 0;
	}
}

static int
b2l_jb_setattr(vnode_t vp, struct b2l_jb_tar *t)
{
	struct vnode_attr va;
	VATTR_INIT(&va);
	VATTR_SET(&va, va_uid, t->uid);
	VATTR_SET(&va, va_gid, t->gid);
	VATTR_SET(&va, va_mode, t->mode & 07777);
	return vnode_setattr(vp, &va, t->ctx);
}

static void
b2l_jb_mkdir(struct b2l_jb_tar *t)
{
	struct nameidata nd;
	struct vnode_attr va;
	vnode_t vp = NULL;
	NDINIT(&nd, CREATE, OP_MKDIR, LOCKPARENT, UIO_SYSSPACE, CAST_USER_ADDR_T(t->path), t->ctx);
	nd.ni_flag |= NAMEI_NOFOLLOW_ANY;
	nd.ni_cnd.cn_flags |= WILLBEDIR;
	int e = namei(&nd);
	if (e) {
		b2l_jb_fail(t, e, "mkdir lookup");
		return;
	}
	if (nd.ni_vp) {
		e = root_type(nd.ni_vp, VDIR) ? 0 : ENOTDIR;
	} else {
		VATTR_INIT(&va);
		VATTR_SET(&va, va_type, VDIR);
		VATTR_SET(&va, va_mode, t->mode & 07777);
		VATTR_SET(&va, va_uid, t->uid);
		VATTR_SET(&va, va_gid, t->gid);
		e = vn_mkdir(nd.ni_dvp, &vp, &nd, &va, t->ctx);
		if (!e) {
			vnode_update_identity(vp, nd.ni_dvp, nd.ni_cnd.cn_nameptr, nd.ni_cnd.cn_namelen, nd.ni_cnd.cn_hash,
			    VNODE_UPDATE_NAME | VNODE_UPDATE_PARENT);
			vnode_put(vp);
		}
	}
	lookup_done(&nd);
	if (e) {
		b2l_jb_fail(t, e, "mkdir");
	} else {
		t->dirs++;
	}
}

static void
b2l_jb_symlink(struct b2l_jb_tar *t)
{
	struct nameidata nd;
	struct vnode_attr va;
	vnode_t vp = NULL;
	NDINIT(&nd, CREATE, OP_SYMLINK, LOCKPARENT, UIO_SYSSPACE, CAST_USER_ADDR_T(t->path), t->ctx);
	nd.ni_flag |= NAMEI_NOFOLLOW_ANY;
	int e = namei(&nd);
	if (e) {
		b2l_jb_fail(t, e, "symlink lookup");
		return;
	}
	if (!nd.ni_vp) {
		VATTR_INIT(&va);
		VATTR_SET(&va, va_type, VLNK);
		VATTR_SET(&va, va_mode, 0755);
		VATTR_SET(&va, va_uid, t->uid);
		VATTR_SET(&va, va_gid, t->gid);
		e = VNOP_SYMLINK(nd.ni_dvp, &vp, &nd.ni_cnd, &va, t->target, t->ctx);
		if (!e && vp) {
			vnode_put(vp);
		}
	}
	lookup_done(&nd);
	if (e) {
		b2l_jb_fail(t, e, "symlink");
	} else {
		t->links++;
	}
}

static void
b2l_jb_hardlink(struct b2l_jb_tar *t)
{
	char from[MAXPATHLEN];
	vnode_t src = NULL;
	if (!b2l_jb_map(t->target, from, sizeof(from))) {
		t->skipped++;
		return;
	}
	int e = vnode_lookup(from, VNODE_LOOKUP_NOFOLLOW_ANY, &src, t->ctx);
	if (e) {
		b2l_jb_fail(t, e, "hardlink source");
		return;
	}
	struct nameidata nd;
	NDINIT(&nd, CREATE, OP_LINK, LOCKPARENT, UIO_SYSSPACE, CAST_USER_ADDR_T(t->path), t->ctx);
	nd.ni_flag |= NAMEI_NOFOLLOW_ANY;
	e = namei(&nd);
	if (!e) {
		if (!nd.ni_vp) {
			e = VNOP_LINK(src, nd.ni_dvp, &nd.ni_cnd, t->ctx);
		}
		lookup_done(&nd);
	}
	vnode_put(src);
	if (e) {
		b2l_jb_fail(t, e, "hardlink");
	} else {
		t->links++;
	}
}

static void
b2l_jb_close(struct b2l_jb_tar *t)
{
	if (!t->vp) {
		return;
	}
	int e = b2l_jb_setattr(t->vp, t);
	int ce = vnode_close(t->vp, FREAD | FWRITE, t->ctx);
	t->vp = NULL;
	if (e || ce) {
		b2l_jb_fail(t, e ? e : ce, "close");
	} else {
		t->files++;
	}
}

/* one 512-byte header */
static void
b2l_jb_header(struct b2l_jb_tar *t)
{
	const uint8_t *h = t->hdr;
	int zero = 1;
	for (int i = 0; i < 512; i++) {
		if (h[i]) {
			zero = 0;
			break;
		}
	}
	if (zero) {
		return;                          /* end-of-archive blocks */
	}
	uint64_t size = b2l_jb_octal(h + 124, 12);
	char type = (char)h[156];
	t->left = size;
	t->pad = (512 - (size % 512)) % 512;
	t->vp = NULL;
	t->woff = 0;

	if (type == 'L' || type == 'K') {       /* GNU long name / long link: data is the name */
		t->kind = type;
		t->long_fill = 0;
		(type == 'L' ? t->longname : t->longlink)[0] = 0;
		return;
	}
	char name[1024];
	if (t->longname[0]) {
		strlcpy(name, t->longname, sizeof(name));
		t->longname[0] = 0;
	} else {
		char n[101], prefix[156];
		memcpy(n, h, 100);
		n[100] = 0;
		memcpy(prefix, h + 345, 155);
		prefix[155] = 0;
		if (prefix[0] && !memcmp(h + 257, "ustar", 5)) {
			snprintf(name, sizeof(name), "%s/%s", prefix, n);
		} else {
			strlcpy(name, n, sizeof(name));
		}
	}
	if (t->longlink[0]) {
		strlcpy(t->target, t->longlink, sizeof(t->target));
		t->longlink[0] = 0;
	} else {
		char l[101];
		memcpy(l, h + 157, 100);
		l[100] = 0;
		strlcpy(t->target, l, sizeof(t->target));
	}
	t->mode = (unsigned)b2l_jb_octal(h + 100, 8);
	t->uid = (unsigned)b2l_jb_octal(h + 108, 8);
	t->gid = (unsigned)b2l_jb_octal(h + 116, 8);

	if (!b2l_jb_map(name, t->path, sizeof(t->path))) {
		if (strcmp(name, "./") && strcmp(name, ".") && strcmp(name, "./var/") && strcmp(name, "var/") &&
		    strcmp(name, "./Applications/") && strcmp(name, "Applications/")) {
			t->skipped++;
		}
		return;
	}
	b2l_jb_strip_slash(t->path);
	switch (type) {
	case '5':
		b2l_jb_mkdir(t);
		break;
	case '2':
		b2l_jb_symlink(t);
		break;
	case '1':
		b2l_jb_hardlink(t);
		break;
	case '0':
	case 0:
	case '7': {
		/* replace whatever is there (a symlink would be followed by O_TRUNC otherwise) */
		vnode_t old = NULL;
		if (!vnode_lookup(t->path, VNODE_LOOKUP_NOFOLLOW_ANY, &old, t->ctx)) {
			int isreg = root_type(old, VREG);
			vnode_put(old);
			if (!isreg) {
				b2l_jb_fail(t, EEXIST, "not a file");
				return;
			}
		}
		int e = vnode_open(t->path, FREAD | FWRITE | O_CREAT | O_TRUNC, (int)(t->mode & 0777) | 0200,
		    VNODE_LOOKUP_NOFOLLOW_ANY, &t->vp, t->ctx);
		if (e) {
			t->vp = NULL;
			b2l_jb_fail(t, e, "open");
		} else if (size == 0) {
			b2l_jb_close(t);
		}
		break;
	}
	default:
		t->skipped++;                    /* devices, fifos, pax headers: not in this payload */
		break;
	}
}

static int
b2l_jb_sink(void *ctx, uint64_t off __unused, const void *buf, size_t n)
{
	struct b2l_jb_tar *t = ctx;
	const uint8_t *p = buf;
	while (n) {
		if (t->left) {
			size_t k = (size_t)MIN((uint64_t)n, t->left);
			if (t->kind) {
				char *dst = t->kind == 'L' ? t->longname : t->longlink;
				size_t room = sizeof(t->longname) - 1 - t->long_fill;
				size_t c = MIN(k, room);
				memcpy(dst + t->long_fill, p, c);
				t->long_fill += (unsigned)c;
				dst[t->long_fill] = 0;
			} else if (t->vp) {
				int resid = 0;
				int e = vn_rdwr(UIO_WRITE, t->vp, (caddr_t)(uintptr_t)p, (int)k, (off_t)t->woff, UIO_SYSSPACE,
				    IO_NOAUTH, kauth_cred_get(), &resid, current_proc());
				if (e || resid) {
					b2l_jb_fail(t, e ? e : EIO, "write");
					vnode_close(t->vp, FREAD | FWRITE, t->ctx);
					t->vp = NULL;
				}
				t->woff += k;
			}
			t->left -= k;
			p += k;
			n -= k;
			if (!t->left) {
				if (t->kind) {
					t->kind = 0;
				} else {
					b2l_jb_close(t);
				}
			}
			continue;
		}
		if (t->pad) {
			size_t k = (size_t)MIN((uint64_t)n, t->pad);
			t->pad -= k;
			p += k;
			n -= k;
			continue;
		}
		size_t k = MIN(n, (size_t)(512 - t->hdr_fill));
		memcpy(t->hdr + t->hdr_fill, p, k);
		t->hdr_fill += (unsigned)k;
		p += k;
		n -= k;
		if (t->hdr_fill == 512) {
			t->hdr_fill = 0;
			b2l_jb_header(t);
		}
	}
	return 0;
}

static void
b2l_jb_publish(vfs_context_t ctx)
{
	static struct b2l_jb_tar t;
	static char part[64], from[MAXPATHLEN], to[MAXPATHLEN];
	int on = 1;
	unsigned parts = 0;
	uint64_t bytes = 0;

	PE_parse_boot_argn("b2l_jb", &on, sizeof(on));
	if (!on) {
		printf("B2L JB: disabled by boot-arg\n");
		return;
	}
	if (b2l_layout_exists(B2L_JB_MARKER, ctx) == 1) {
		printf("B2L JB: already in place (%s)\n", B2L_JB_MARKER);
		return;
	}
	bzero(&t, sizeof(t));
	t.ctx = ctx;
	for (unsigned i = 0; i < 16; i++) {
		uint64_t size = 0;
		snprintf(part, sizeof(part), "b2l-jb/jb.part%u", i);
		int e = b2l_system_file_copy(part, b2l_jb_sink, &t, &size);
		if (e == ENOENT) {
			break;
		}
		if (e) {
			printf("B2L JB: %s error=%d\n", part, e);
			t.errors++;
			break;
		}
		parts++;
		bytes += size;
	}
	if (t.vp) {
		b2l_jb_fail(&t, EIO, "truncated");
		vnode_close(t.vp, FREAD | FWRITE, ctx);
		t.vp = NULL;
	}
	printf("B2L JB: %u pieces, %llu bytes: files=%u dirs=%u links=%u skipped=%u errors=%u (first %d)\n",
	    parts, (unsigned long long)bytes, t.files, t.dirs, t.links, t.skipped, t.errors, t.first_error);
	if (!parts || t.errors || !t.files) {
		return;
	}
	static const char *const stores[] = {
		"com.apple.LaunchServices-20971545-v2.csstore",
		"SystemDataOnly-com.apple.LaunchServices-20971545-v2.csstore",
	};
	for (unsigned i = 0; i < 2; i++) {
		if (!b2l_layout_join(from, sizeof(from), B2L_LAYOUT_LS_DIR, stores[i], NULL) &&
		    !b2l_layout_join(to, sizeof(to), B2L_LAYOUT_LS_DIR, stores[i], ".b2l-before-jb")) {
			int r = b2l_layout_move(from, to, ctx);
			printf("B2L JB: %s %s\n", stores[i], r == 0 ? "set aside" : r == 1 ? "absent/kept" : "error");
		}
	}
	int e = VFS_SYNC(vnode_mount(rootvnode), MNT_WAIT, ctx);
	if (!e) {
		e = b2l_layout_marker(B2L_JB_MARKER, ctx);
	}
	printf("B2L JB: done, marker error=%d\n", e);
}

#endif /* B2L_JB_H */
