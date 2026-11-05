#include "CKuddoBridge.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <util.h>
#include <sys/ioctl.h>
#include <libproc.h>
#include <sys/sysctl.h>

int kuddo_spawn(const char *path,
                char *const argv[],
                const char *cwd,
                char *const env[],
                unsigned short rows,
                unsigned short cols,
                pid_t *out_pid) {
    struct winsize ws;
    ws.ws_row = rows;
    ws.ws_col = cols;
    ws.ws_xpixel = 0;
    ws.ws_ypixel = 0;

    int master = -1;
    pid_t pid = forkpty(&master, NULL, NULL, &ws);
    if (pid < 0) {
        return -1;
    }
    if (pid == 0) {
        // Environment edits happen here, in the child, so a profile's
        // variables and a shell's integration hooks reach that one process
        // and nothing else in the app. "KEY=VALUE" sets, a bare "KEY" unsets.
        if (env) {
            for (char *const *e = env; *e; e++) {
                const char *eq = strchr(*e, '=');
                if (eq) {
                    size_t klen = (size_t)(eq - *e);
                    char *key = malloc(klen + 1);
                    if (!key) continue;
                    memcpy(key, *e, klen);
                    key[klen] = '\0';
                    setenv(key, eq + 1, 1);
                    free(key);
                } else {
                    unsetenv(*e);
                }
            }
        }
        if (cwd && *cwd) {
            // Best effort — if it fails we still exec from whatever CWD we
            // got, rather than refusing to spawn.
            (void)chdir(cwd);
        }
        execvp(path, argv);
        _exit(127);
    }
    if (out_pid) {
        *out_pid = pid;
    }
    return master;
}

int kuddo_set_winsize(int fd, unsigned short rows, unsigned short cols) {
    struct winsize ws;
    ws.ws_row = rows;
    ws.ws_col = cols;
    ws.ws_xpixel = 0;
    ws.ws_ypixel = 0;
    return ioctl(fd, TIOCSWINSZ, &ws);
}

// argv[0]'s last path component, without a login shell's leading '-'.
// KERN_PROCARGS2 is argc, then the exec path, NUL padding, then argv.
static int argv0_name(pid_t pid, char *buf, int len) {
    int mib[3] = { CTL_KERN, KERN_ARGMAX, 0 };
    int argmax = 0;
    size_t size = sizeof(argmax);
    if (sysctl(mib, 2, &argmax, &size, NULL, 0) != 0 || argmax <= 0) return 0;

    char *args = malloc((size_t)argmax);
    if (!args) return 0;
    mib[1] = KERN_PROCARGS2;
    mib[2] = (int)pid;
    size = (size_t)argmax;
    int n = 0;
    if (sysctl(mib, 3, args, &size, NULL, 0) == 0 && size > sizeof(int)) {
        char *end = args + size;
        char *p = args + sizeof(int);
        while (p < end && *p) p++;              // exec path
        while (p < end && !*p) p++;             // padding
        char *arg0 = p;
        while (p < end && *p) p++;
        if (arg0 < end && p < end && p > arg0) {
            char *base = strrchr(arg0, '/');
            base = base ? base + 1 : arg0;
            if (*base == '-') base++;
            size_t blen = strlen(base);
            if (blen > 0) {
                if ((int)blen >= len) blen = (size_t)len - 1;
                memcpy(buf, base, blen);
                buf[blen] = '\0';
                n = (int)blen;
            }
        }
    }
    free(args);
    return n;
}

int kuddo_proc_name(pid_t pid, char *buf, int len) {
    if (!buf || len <= 0) return 0;
    buf[0] = '\0';
    // The name it was started by first: the kernel's own name for a process
    // is its executable's after symlinks resolve, and Claude Code's
    // `~/.local/bin/claude` resolves to `versions/2.1.318` — "2.1.318".
    int a = argv0_name(pid, buf, len);
    if (a > 0) return a;
    int n = proc_name(pid, buf, (uint32_t)len);
    if (n <= 0) {
        buf[0] = '\0';
        return 0;
    }
    if (n >= len) n = len - 1;
    buf[n] = '\0';
    return n;
}

pid_t kuddo_foreground_pid(pid_t pgid) {
    if (pgid <= 0) return pgid;

    // KERN_PROC_PGRP hands back exactly the group we care about, so the walk
    // never has to look at the rest of the process table.
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PGRP, (int)pgid };
    size_t len = 0;
    if (sysctl(mib, 4, NULL, &len, NULL, 0) != 0 || len == 0) return pgid;

    // Processes can come and go between the sizing call and the read, so ask
    // for some slack and accept a short answer.
    len += 8 * sizeof(struct kinfo_proc);
    struct kinfo_proc *procs = malloc(len);
    if (!procs) return pgid;
    if (sysctl(mib, 4, procs, &len, NULL, 0) != 0) {
        free(procs);
        return pgid;
    }

    int count = (int)(len / sizeof(struct kinfo_proc));
    pid_t best = pgid;
    int best_depth = 0;

    // Depth = hops from the group leader. The deepest process is the one doing
    // the work; ties go to the youngest, which is the one a wrapper started
    // last. Capped at `count` hops so a cycle can't spin.
    for (int i = 0; i < count; i++) {
        pid_t pid = procs[i].kp_proc.p_pid;
        if (pid == pgid) continue;
        // A zombie is the deepest thing in the group right up until its parent
        // reaps it, and it has no name left to report.
        if (procs[i].kp_proc.p_stat == SZOMB) continue;

        int depth = 0;
        pid_t walk = pid;
        while (walk != pgid && depth <= count) {
            pid_t parent = 0;
            for (int j = 0; j < count; j++) {
                if (procs[j].kp_proc.p_pid == walk) {
                    parent = procs[j].kp_eproc.e_ppid;
                    break;
                }
            }
            if (parent <= 0) { depth = -1; break; }   // parent left the group
            walk = parent;
            depth++;
        }
        if (depth <= 0 || walk != pgid) continue;     // not a descendant

        if (depth > best_depth || (depth == best_depth && pid > best)) {
            best = pid;
            best_depth = depth;
        }
    }

    free(procs);
    return best;
}
