/*
 * pthread_cancel() family for HarmonyOS NEXT: OH 4.0+ musl doesn't provide
 * these symbols, so iperf3 won't link. Mirrors upstream's Android workaround
 * (src/iperf_pthread.c, BSD-3): pthread_kill + a handler that pthread_exit()s.
 */
#include <pthread.h>
#include <signal.h>
#include <string.h>

#ifndef IPERF_NAPI_CANCEL_SIGNAL
#define IPERF_NAPI_CANCEL_SIGNAL SIGUSR1
#endif

/* pthread_exit() in a signal handler is not async-signal-safe. */
static void
iperf_napi_thread_exit_handler(int sig)
{
    (void) sig;
    pthread_exit(0);
}

static int
iperf_napi_install_thread_exit_handler(void)
{
    struct sigaction sa;

    memset(&sa, 0, sizeof(sa));
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = 0;
    sa.sa_handler = iperf_napi_thread_exit_handler;
    return sigaction(IPERF_NAPI_CANCEL_SIGNAL, &sa, NULL);
}

/* No-ops: deferred cancellation is emulated, as in upstream's Android shim. */
int pthread_setcanceltype(int type, int *oldtype)
{
    (void) type;
    (void) oldtype;
    return 0;
}

int pthread_setcancelstate(int state, int *oldstate)
{
    (void) state;
    (void) oldstate;
    return 0;
}

/* SIGUSR1 is process-wide and reinstalled on every call; if another component
 * installs its own SIGUSR1 handler, cancel degrades to EINTR and join may
 * block (the iperf loops poll sp->done/test->done anyway). Switch signals by
 * defining IPERF_NAPI_CANCEL_SIGNAL. */
int pthread_cancel(pthread_t thread)
{
    if (iperf_napi_install_thread_exit_handler() != 0)
        return -1;
    return pthread_kill(thread, IPERF_NAPI_CANCEL_SIGNAL);
}
