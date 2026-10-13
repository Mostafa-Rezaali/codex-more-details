// Start a program as its own "responsible" process (so macOS privacy prompts
// and existing permission grants apply to ChatGPT, not to this launcher),
// inheriting our file descriptors, and exit with its status.
#include <errno.h>
#include <signal.h>
#include <spawn.h>
#include <stdio.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;
extern int responsibility_spawnattrs_setdisclaim(posix_spawnattr_t *attrs, int disclaim) __attribute__((weak_import));

static pid_t child = 0;
static void forward(int sig) { if (child > 0) kill(child, sig); }

int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "usage: %s program [args...]\n", argv[0]); return 2; }
    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    sigset_t none, all;
    sigemptyset(&none); sigfillset(&all);
    posix_spawnattr_setsigmask(&attr, &none);
    posix_spawnattr_setsigdefault(&attr, &all);
    posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF);
    if (responsibility_spawnattrs_setdisclaim) responsibility_spawnattrs_setdisclaim(&attr, 1);
    int err = posix_spawn(&child, argv[1], NULL, &attr, &argv[1], environ);
    posix_spawnattr_destroy(&attr);
    if (err != 0) { fprintf(stderr, "spawn %s: %s\n", argv[1], strerror(err)); return 127; }
    signal(SIGTERM, forward); signal(SIGINT, forward); signal(SIGHUP, forward);
    int status;
    while (waitpid(child, &status, 0) < 0) if (errno != EINTR) return 1;
    return WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status);
}
