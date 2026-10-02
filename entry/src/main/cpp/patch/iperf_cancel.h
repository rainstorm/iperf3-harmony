/*
 * Stop a running libiperf test from another thread. Upstream has no cancel
 * API (the CLI stops via SIGINT + longjmp into exit(), unusable in an app
 * process), so we set the library-internal stop flags directly:
 *  - client: test->done; the main loop checks it every iteration and the
 *    select() timeout is bounded by the 1 s stats/reporter timers, so the
 *    normal shutdown path runs within about one interval;
 *  - server: iperf_set_test_state(IPERF_DONE) breaks the run loop. A running
 *    server notices within its 1 s select timeout, but an idle one
 *    (idle_timeout 0) blocks on the listener forever, so also shutdown() the
 *    control socket (server reads EOF, exits cleanly) or self-connect to the
 *    listen port (cookie read fails, run_server returns -1).
 *
 * done/state are plain fields written from the NAPI thread while the run loop
 * re-reads them -- same discipline as upstream's signal handler, sound on
 * aarch64, not formally atomic. The struct iperf_test must stay alive for the
 * duration of the call; the NAPI bridge calls both functions while holding
 * the mutex the worker thread takes before freeing the test.
 */
#ifndef IPERF_NAPI_CANCEL_H
#define IPERF_NAPI_CANCEL_H

/* iperf_config.h must come first: without HAVE_STDATOMIC_H, iperf_api.h
 * falls back to `typedef u_int64_t atomic_uint_fast64_t`, which musl
 * does not provide. */
#include "iperf_config.h"
#include "iperf_api.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Graceful cancel: ask the running test to stop, and wake any select() that
 * would not see the flags on its own. NULL-safe; harmless if not running. */
void iperf_cancel_test(struct iperf_test *ipt);

/* Hard abort for when the graceful cancel is not observed (e.g. blocked in a
 * control-phase select()): also shuts the control socket down. The run still
 * returns through its cleanup path and frees everything. NULL-safe. */
void iperf_force_abort_test(struct iperf_test *ipt);

#ifdef __cplusplus
}
#endif

#endif /* IPERF_NAPI_CANCEL_H */
