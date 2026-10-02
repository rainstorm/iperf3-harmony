/*
 * iperf_cancel.c -- see patch/iperf_cancel.h for the rationale. Separate
 * translation unit so third_party/iperf stays pristine; needs the full
 * struct iperf_test, hence the internal src/iperf.h (upstream installs
 * only iperf_api.h, Makefile.am:8). Upstream refs are iperf 3.22.
 */
#include "iperf_cancel.h"

#include "iperf.h"

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <poll.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

/*
 * Wake a select() blocked on the idle control listener: connect from
 * loopback and close again, so the server's cookie read fails and it takes
 * its cleanup path (iperf_server_api.c:193-201). Failure is harmless --
 * select() is already awake or the listener is gone.
 *
 * Non-blocking with a bounded 100 ms wait: the NAPI bridge calls this under
 * its engine mutex, so a blocking connect (e.g. a full listen backlog)
 * would stall the ArkTS thread. The poll only ensures the connection lands
 * in the listen queue -- that alone makes the listener readable.
 */
static void
iperf_napi_wake_listener(struct iperf_test *ipt)
{
    struct sockaddr_in sa;
    struct pollfd pfd;
    int fd, flags, rc;

    if (ipt == NULL || ipt->listener < 0 || ipt->server_port <= 0)
        return;

    fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0)
        return;
    flags = fcntl(fd, F_GETFL, 0);
    if (flags >= 0)
        (void) fcntl(fd, F_SETFL, flags | O_NONBLOCK);
    memset(&sa, 0, sizeof(sa));
    sa.sin_family = AF_INET;
    sa.sin_port = htons((unsigned short) ipt->server_port);
    sa.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    rc = connect(fd, (struct sockaddr *) &sa, sizeof(sa));
    if (rc == 0 || (rc < 0 && errno == EINPROGRESS)) {
        pfd.fd = fd;
        pfd.events = POLLOUT;
        pfd.revents = 0;
        (void) poll(&pfd, 1, 100);
    }
    (void) close(fd);
}

void
iperf_cancel_test(struct iperf_test *ipt)
{
    if (ipt == NULL)
        return;

    /* Client: main loop notices `done` within one interval and runs the
     * normal TEST_END shutdown (iperf_client_api.c:777-835). */
    ipt->done = 1;

    if (ipt->role == 's') {
        /* Server: break the main loop condition (iperf_server_api.c:631)
         * via the public state setter, then make sure a blocked select()
         * actually returns. */
        iperf_set_test_state(ipt, IPERF_DONE);
        if (ipt->ctrl_sck >= 0) {
            /* Established control connection: the server reads EOF, sets
             * IPERF_DONE itself and exits cleanly
             * (iperf_server_api.c:249-254). */
            (void) shutdown(ipt->ctrl_sck, SHUT_RDWR);
        } else {
            /* Idle server: select() blocks on the listener with no timeout
             * (iperf_server_api.c:666-671, idle_timeout defaults to 0). */
            iperf_napi_wake_listener(ipt);
        }
    }
}

void
iperf_force_abort_test(struct iperf_test *ipt)
{
    if (ipt == NULL)
        return;

    ipt->done = 1;
    iperf_set_test_state(ipt, IPERF_DONE);
    if (ipt->ctrl_sck >= 0)
        (void) shutdown(ipt->ctrl_sck, SHUT_RDWR);
    iperf_napi_wake_listener(ipt);
    /* Data sockets are closed by the run's own cleanup paths
     * (iperf_client_end() / cleanup_server()); unblocking the control
     * select is sufficient to let those paths run. */
}
