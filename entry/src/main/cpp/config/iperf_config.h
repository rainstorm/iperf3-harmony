/* Hand-maintained stand-in for autoconf's iperf_config.h (template:
 * third_party/iperf/src/iperf_config.h.in) for the OHOS build (musl +
 * Linux kernel + clang); like `configure --with-openssl=no`. Local glue,
 * not upstream code. */
#ifndef IPERF_CONFIG_HARMONY_H
#define IPERF_CONFIG_HARMONY_H

/* Must match AC_INIT([iperf],[3.22]) in third_party/iperf/configure.ac. */
#define PACKAGE "iperf"
#define PACKAGE_NAME "iperf"
#define PACKAGE_TARNAME "iperf"
#define PACKAGE_VERSION "3.22"
#define PACKAGE_STRING "iperf 3.22"
#define PACKAGE_BUGREPORT "https://github.com/esnet/iperf"
#define PACKAGE_URL "https://github.com/esnet/iperf"
#define VERSION "3.22"

/* Without this, upstream approximates atomic_iperf_size_t with a plain
 * uint64_t and emits a #warning (iperf_api.h). */
#define HAVE_STDATOMIC_H 1

/* OHOS musl has no pthread_cancel family; patch/iperf_pthread_shim.c
 * supplies them. */
#define HAVE_PTHREAD 1

/* All three live in musl's libc -- no -lrt, unlike glibc. */
#define HAVE_CLOCK_GETTIME 1
#define HAVE_CLOCK_NANOSLEEP 1
#define HAVE_NANOSLEEP 1

/* musl endian.h; the HAVE_SYS_ENDIAN_H fallback is for BSDs. */
#define HAVE_ENDIAN_H 1

/* Linux kernel, so the uapi linux/tcp.h is in the sysroot; this selects
 * the real struct tcp_info branch in iperf.h (TCP rtt/retransmit/cwnd
 * interval statistics depend on it). */
#define HAVE_LINUX_TCP_H 1

#define HAVE_POLL_H 1
#define HAVE_GETLINE 1

/* sendfile: -Z zerocopy; never used from the NAPI layer. */
#define HAVE_SENDFILE 1

/* daemon(): server -D mode; we never daemonize inside an app. */
#define HAVE_DAEMON 1

/* Standard headers, all present in musl. */
#define HAVE_STDINT_H 1
#define HAVE_STDIO_H 1
#define HAVE_STDLIB_H 1
#define HAVE_STRING_H 1
#define HAVE_STRINGS_H 1
#define HAVE_INTTYPES_H 1
#define HAVE_SYS_SOCKET_H 1
#define HAVE_SYS_STAT_H 1
#define HAVE_SYS_TYPES_H 1
#define HAVE_UNISTD_H 1
#define HAVE_DLFCN_H 1
#define STDC_HEADERS 1

/* Deliberately undefined: everything below is cleanly guarded upstream, so
 * the code paths just compile out. Verify against the OHOS sysroot and
 * kernel policy before defining any of them. */

/* HAVE_SSL: the `--with-openssl=no` equivalent. Only iperf_auth.c (fully
 * wrapped in #if defined(HAVE_SSL)) and the iperf_api.h auth setters are
 * lost; no OpenSSL ends up in the .so. */

/* HAVE_SCTP_H: SCTP off; iperf_sctp.c compiles to an empty unit. */

/* Socket options not verified against the OHOS sysroot / kernel policy:
 *   HAVE_TCP_CONGESTION        (-C congestion control)
 *   HAVE_TCP_USER_TIMEOUT      (control-socket send timeout)
 *   HAVE_TCP_KEEPALIVE         (control-connection keepalive)
 *   HAVE_SO_MAX_PACING_RATE    (FQ pacing)
 *   HAVE_SO_BINDTODEVICE, CAN_BIND_TO_DEVICE, HAVE_IP_BOUND_IF  (-B bind dev)
 *   HAVE_DONT_FRAGMENT, HAVE_IP_DONTFRAG, HAVE_IP_DONTFRAGMENT,
 *   HAVE_IP_MTU_DISCOVER       (--dont-fragment)
 *   HAVE_FLOWLABEL             (IPv6 flow label)
 *   HAVE_MSG_TRUNC             (--skip-rx-copy)
 *   HAVE_UDP_SEGMENT, HAVE_UDP_GRO  (UDP offload features)
 *   HAVE_IPPROTO_MPTCP         (--mptcp)
 *   HAVE_TCP_INFO_SND_WND      (extra tcp_info field)
 *   HAVE_SOCKET_SHUTDOWN_SHUT_WR
 *   HAVE_CPU_AFFINITY, HAVE_SCHED_SETAFFINITY, HAVE_CPUSET_SETAFFINITY,
 *   HAVE_SETPROCESSAFFINITYMASK  (-A affinity; also check seccomp)
 *   HAVE_STRUCT_SCTP_ASSOC_VALUE
 *   HAVE_PTHREAD_PRIO_INHERIT
 */

#endif /* IPERF_CONFIG_HARMONY_H */
