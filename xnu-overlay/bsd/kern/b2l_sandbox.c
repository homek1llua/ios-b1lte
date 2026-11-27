/* SPDX-License-Identifier: BSD-2-Clause */
/* Built-in development policy for the explicitly unsigned B2L port.
 * This registers the name queried by libsystem_sandbox; it does not implement
 * production profile enforcement or container paths. Private development
 * extension capabilities have separate bounded lifetime bookkeeping. */
#if defined(ARM64_BOARD_CONFIG_B2L) && CONFIG_MACF
#include <sys/types.h>
#include <sys/systm.h>
#include <sys/errno.h>
#include <sys/kauth.h>
#include <sys/proc.h>
#include <sys/proc_private.h>
#include <sys/random.h>
#include <kern/locks.h>
#include <sys/priv.h>
#include <sys/codesign.h>
#include <sys/vnode.h>
#include <security/mac_policy.h>
struct componentname;
extern vnode_t proc_getexecutablevnode(proc_t);
#include <os/atomic_private.h>
#include <os/refcnt.h>
#include <kern/kalloc.h>
#include <kern/mach_filter.h>
#include <arm64/b2l_arm64e_compat.h>
#include <arm64/b2l_diag.h>

void b2l_sandbox_register(void);

static _Atomic uint64_t b2l_sandbox_seen[2];
static _Atomic uint32_t b2l_sandbox_other_seen;
static _Atomic uint64_t b2l_sandbox_priv_seen;
static _Atomic uint32_t b2l_sandbox_other_priv_seen;
static bool b2l_sandbox_registered; /* only written by the BSD init thread */
static mac_policy_handle_t b2l_sandbox_handle;

static bool
b2l_sandbox_development_enabled(void)
{
    return b2l_arm64e_compat_enabled() && !cs_process_global_enforcement();
}

#include "b2l_sandbox_extensions.h"
#include "b2l_mach_filter.h"

/* At most129 operation and65 privilege lines per boot, regardless of callers.
 * Only numeric API identifiers are logged; no task names, IDs or user data. */
static void
b2l_sandbox_log_operation(int operation)
{
    if (operation >= 0 && operation < 128) {
        unsigned index = (unsigned)operation / 64u;
        uint64_t bit = UINT64_C(1) << ((unsigned)operation % 64u);
        if (!(os_atomic_or_orig(&b2l_sandbox_seen[index], bit, relaxed) & bit)) {
            printf("B2L Sandbox: operation %d\n", operation);
        }
    } else if (!os_atomic_xchg(&b2l_sandbox_other_seen, 1u, relaxed)) {
        printf("B2L Sandbox: unrecognized operation range\n");
    }
}

/* Verified iOS26 op0x43 is two pointers to64-bit outputs. Keep the successful
 * zero-output contract, rather than the older A5 ENOENT behavior for this op.
 * A later copyout failure may follow an already completed earlier copyout,
 * matching normal copyio semantics; no fabricated nonzero outputs are used. */
static int
b2l_sandbox_container_expected(user_addr_t argument)
{
    struct { user64_addr_t expected; user64_addr_t restricted; } outputs;
    const uint64_t none = 0;
    int error = copyin(argument, &outputs, sizeof(outputs));
    if (error) return error;
    if (outputs.expected) {
        error = copyout(&none, outputs.expected, sizeof(none));
        if (error) return error;
    }
    if (outputs.restricted) {
        error = copyout(&none, outputs.restricted, sizeof(none));
    }
    return error;
}

/*
 * S10 build 0043: container paths. A process launched into a container (xpcproxy, POSIX_SPAWN_SETEXEC) carries the
 * path in its "Sandbox" spawn attributes (libsystem_sandbox's sandbox_spawnattrs: path at 0x50, length at 0xc). It is
 * kept per pid at exec and answered to the container-path query (op 4: pid, pid version, buffer, size, by-token flag).
 * Before, op 4 always failed with ENOENT, and extensions such as PhotosPicker stopped themselves:
 * "plugin has invalid sandbox or container: error 2 path ?".
 */
#define B2L_CONTAINERS 128
#define B2L_CONTAINER_PATH 192
static struct { pid_t pid; char path[B2L_CONTAINER_PATH]; } b2l_containers[B2L_CONTAINERS];
static LCK_GRP_DECLARE(b2l_container_grp, "b2l_container");
static LCK_SPIN_DECLARE(b2l_container_lock, &b2l_container_grp);
static unsigned b2l_container_said;

static int
b2l_sandbox_check_exec(kauth_cred_t cred __unused, struct vnode *vp __unused, struct vnode *scriptvp __unused,
    struct label *vnodelabel __unused, struct label *scriptlabel __unused, struct label *execlabel __unused,
    struct componentname *cnp __unused, u_int *csflags __unused, void *attr, size_t attrlen)
{
    pid_t pid = proc_selfpid();
    char path[B2L_CONTAINER_PATH] = { 0 };
    if (!b2l_sandbox_development_enabled()) return 0;
    if (attr && attrlen > 0x50 + 1) {
        size_t max = attrlen - 0x50 < sizeof(path) ? attrlen - 0x50 : sizeof(path);
        strlcpy(path, (const char *)attr + 0x50, max);
    }
    lck_spin_lock(&b2l_container_lock);
    int slot = -1, empty = -1;
    for (int i = 0; i < B2L_CONTAINERS; i++) {
        if (b2l_containers[i].pid == pid) { slot = i; break; }
        if (empty < 0 && b2l_containers[i].pid == 0) empty = i;
    }
    if (path[0]) {
        if (slot < 0) slot = empty >= 0 ? empty : (int)(pid % B2L_CONTAINERS);
        b2l_containers[slot].pid = pid;
        strlcpy(b2l_containers[slot].path, path, sizeof(b2l_containers[slot].path));
    } else if (slot >= 0) {
        b2l_containers[slot].pid = 0;
    }
    lck_spin_unlock(&b2l_container_lock);
    if (path[0] && b2l_container_said++ < 48) {
        char name[32];
        proc_selfname(name, sizeof(name));
        printf("B2L SB CONTAINER: %s[%d] %s\n", name, pid, path);
    }
    return 0;
}

static int
b2l_sandbox_container_path(user_addr_t argument)
{
    struct { uint64_t pid, version; user64_addr_t buffer; uint64_t size, by_token; } a;
    char path[B2L_CONTAINER_PATH] = { 0 };
    static unsigned said;
    int error = copyin(argument, &a, sizeof(a));
    if (error) return error;
    pid_t pid = a.pid ? (pid_t)a.pid : proc_selfpid();
    lck_spin_lock(&b2l_container_lock);
    for (int i = 0; i < B2L_CONTAINERS; i++) {
        if (b2l_containers[i].pid == pid) { strlcpy(path, b2l_containers[i].path, sizeof(path)); break; }
    }
    lck_spin_unlock(&b2l_container_lock);
    /* S10 build 0044: no process is launched with a container here (0043's log), so an app extension (.appex) --
     * which refuses to run without one -- gets the mobile home, where an unsandboxed process keeps its data anyway */
    bool appex = false;
    if (!path[0]) {
        proc_t target = proc_find(pid);
        if (target != NULL) {
            vnode_t vp = proc_getexecutablevnode(target);
            if (vp != NULLVP) {
                char *exe = kalloc_data(MAXPATHLEN, Z_WAITOK);
                int len = MAXPATHLEN;
                if (exe && !vn_getpath(vp, exe, &len)) {
                    for (const char *q = exe; *q && !appex; q++) appex = !strncmp(q, ".appex/", 7);
                }
                if (exe) kfree_data(exe, MAXPATHLEN);
                vnode_put(vp);
            }
            proc_rele(target);
        }
        if (appex) strlcpy(path, "/private/var/mobile", sizeof(path));
    }
    if (appex && said++ < 48) {
        char name[32];
        proc_selfname(name, sizeof(name));
        printf("B2L SB CONTAINER: query by %s for app extension pid %d: %s\n", name, pid, path);
    }
    if (!path[0]) return ENOENT;
    size_t n = strlen(path) + 1;
    if (!a.buffer || a.size < n) return ERANGE;
    return copyout(path, a.buffer, n);
}

static int
b2l_sandbox_syscall(struct proc *process, int operation, user_addr_t argument)
{
    /* Also gate callbacks, so an enforcement transition cannot leave this
     * provider permissive after its boot-time registration decision. */
    if (!b2l_sandbox_development_enabled() || !proc_is64bit(process)) {
        return ENOPOLICY;
    }
    b2l_sandbox_log_operation(operation);
    switch (operation) {
    case 4: /* container-path query: the path the process was launched with (S10 build 0043) */
        return b2l_sandbox_container_path(argument);
    case 5: case 6: case 7: case 0x50:
        return b2l_extension_syscall(process, operation, argument);
    case 0x43:
        return b2l_sandbox_container_expected(argument);
    default:
        /* Explicit unconfined development behavior, matching the A5 port. */
        return 0;
    }
}

static int
b2l_sandbox_priv_grant(kauth_cred_t credential __unused, int privilege)
{
    if (!b2l_sandbox_development_enabled()) return EPERM;
    if (privilege >= 1000 && privilege < 1064) {
        uint64_t bit = UINT64_C(1) << ((unsigned)privilege - 1000u);
        if (!(os_atomic_or_orig(&b2l_sandbox_priv_seen, bit, relaxed) & bit)) {
            printf("B2L Sandbox: privilege %d %s\n", privilege,
                privilege == PRIV_WORK_INTERVAL ? "granted" : "not granted");
        }
    } else if (!os_atomic_xchg(&b2l_sandbox_other_priv_seen, 1u, relaxed)) {
        printf("B2L Sandbox: other privilege not granted\n");
    }
    return privilege == PRIV_WORK_INTERVAL ? 0 : EPERM;
}

static const struct mac_policy_ops b2l_sandbox_ops = {
    .mpo_policy_syscall = b2l_sandbox_syscall,
    .mpo_priv_grant = b2l_sandbox_priv_grant,
    .mpo_proc_notify_exit = b2l_extension_process_exit,
    .mpo_vnode_check_exec = b2l_sandbox_check_exec,
};

static struct mac_policy_conf b2l_sandbox_conf = {
    .mpc_name = "Sandbox",
    .mpc_fullname = "B2L unsigned development Sandbox policy",
    .mpc_ops = &b2l_sandbox_ops,
};

/* Invoked by mac_policy_init(), before machine_lockdown and userspace exec.
 * No NOTLATE/UNLOADOK flag: it is a permanent built-in development provider.
 * A real preexisting Sandbox policy wins through mac_policy_register EEXIST. */
void
b2l_sandbox_register(void)
{
    if (!b2l_sandbox_development_enabled() || b2l_sandbox_registered) return;
    int error = mac_policy_register(&b2l_sandbox_conf, &b2l_sandbox_handle, NULL);
    if (!error) {
        b2l_sandbox_registered = true;
        kern_return_t filter_error = b2l_mach_filter_register();
        printf("B2L Sandbox: Mach filter v1 provider %s (%d)\n",
            filter_error ? "not registered" : "registered", filter_error);
    }
    printf("B2L Sandbox: development provider %s (%d)\n",
        error ? "not registered" : "registered", error);
}
#endif /* ARM64_BOARD_CONFIG_B2L && CONFIG_MACF */
