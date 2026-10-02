/*
 * iperf_bridge.h -- NAPI bridge engine for libiperf 3.22 (NAPI contract:
 * entry/src/main/cpp/types/libiperf_napi/index.d.ts). 3.22 has no iperf_run();
 * run iperf_run_client()/iperf_run_server() on a worker thread, like the CLI
 * does (third_party/iperf/src/main.c).
 */
#ifndef IPERF_NAPI_BRIDGE_H
#define IPERF_NAPI_BRIDGE_H

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "napi/native_api.h"

/* NAPI-layer error codes (negative). Positive values are libiperf's i_errno
 * codes from src/iperf_api.h (1..301). */
enum IperfNapiErrorCode {
    IPERF_NAPI_ERR_ALREADY_RUNNING = -1, /* start() while a test is running */
    IPERF_NAPI_ERR_INVALID_CONFIG = -2,  /* malformed / inconsistent IperfConfig */
    IPERF_NAPI_ERR_INTERNAL = -3,        /* e.g. iperf_new_test() failure */
};

/* Heap messages: produced by the worker / iperf callback threads, consumed
 * and deleted by the call_js trampoline on the ArkTS thread. */
struct IperfIntervalMsg {
    int32_t interval_id;
    double start_sec;
    double end_sec;
    double bytes;
    double bps;
    bool has_retransmits;
    int32_t retransmits;
    bool has_jitter_ms;
    double jitter_ms;
    bool has_lost_pct;
    double lost_pct;
};

struct IperfSummaryMsg {
    bool ok;
    double sent_bps;
    double received_bps;
    double duration_sec;
    bool has_retransmits;
    int32_t retransmits;
    bool has_jitter_ms;
    double jitter_ms;
    bool has_lost_pct;
    double lost_pct;
    char* error; /* heap-allocated with strdup(), or nullptr */
};

struct IperfErrorMsg {
    int32_t code;
    char* message; /* heap-allocated with strdup() */
};

struct IperfRunConfig {
    char role; /* 'c' or 's' */
    bool udp;
    std::string host;
    int32_t port;
    int32_t duration;
    int32_t parallel;
    bool reverse;
    int32_t window;   /* 0 = leave iperf default (autotuning) */
    int32_t blksize;  /* 0 = leave iperf default */
};

class IperfEngine {
public:
    static IperfEngine& Get();

    /* NAPI entry points -- all called on the ArkTS thread. */
    napi_value Start(napi_env env, napi_callback_info info);
    napi_value Stop(napi_env env, napi_callback_info info);
    napi_value OnInterval(napi_env env, napi_callback_info info);
    napi_value OnFinish(napi_env env, napi_callback_info info);
    napi_value OnError(napi_env env, napi_callback_info info);

    /* Called from iperf's JSON-stream callback (reporter timer thread or
     * worker thread). `json` is owned by iperf and freed when we return, so
     * it is fully parsed here, synchronously. */
    void HandleJsonEvent(const char* json);

    ~IperfEngine();

private:
    IperfEngine();

    /* Worker thread body: owns the struct iperf_test for the whole run and
     * guarantees iperf_free_test() on every path. */
    void WorkerMain(IperfRunConfig cfg);
    void FinishWorker(int rc, int iperf_errno, const IperfRunConfig& cfg);

    /* Persistent escalation watchdog: stop() schedules a deadline; if the
     * worker is still running when it expires, the test is force-aborted
     * (patch/iperf_cancel.c). Joined in the destructor. */
    void WatchdogMain();
    void ScheduleForceAbort(std::chrono::milliseconds delay);

    /* Releases tsfn handles parked by RegisterCallback() while a run was
     * active; called at the end of every run, after the worker has made its
     * last tsfn call. */
    void DrainSupersededTsfns();

    /* JSON event handlers (cJSON objects borrowed from the parse tree). */
    void HandleIntervalEvent(void* data_obj);
    void HandleEndEvent(void* data_obj);

    /* Event emitters (any thread; no-op without a registered callback). */
    void EmitInterval(IperfIntervalMsg* msg);
    void EmitFinish(IperfSummaryMsg* msg);
    void EmitError(int32_t code, const char* message);

    /* tsfn registration helper: creates a threadsafe function for `cb`,
     * atomically replaces the stored one (later registration wins, per the
     * contract) and releases the previous. */
    napi_value RegisterCallback(napi_env env, napi_callback_info info,
                                const char* tsfn_name,
                                void (*call_js)(napi_env, napi_value, void*, void*),
                                std::atomic<napi_threadsafe_function>& slot);

    struct iperf_test* test_ = nullptr; /* guarded by mutex_, non-null only while the worker runs */

    std::thread worker_;
    std::thread watchdog_;
    std::mutex mutex_; /* guards test_, end_, interval accumulation */
    std::mutex watchdog_mutex_;
    std::condition_variable watchdog_cv_;
    std::chrono::steady_clock::time_point watchdog_deadline_{};
    bool watchdog_shutdown_ = false;

    std::atomic<bool> running_{false};
    std::atomic<bool> cancel_requested_{false};
    std::atomic<int32_t> interval_seq_{0};

    std::atomic<napi_threadsafe_function> interval_tsfn_{nullptr};
    std::atomic<napi_threadsafe_function> finish_tsfn_{nullptr};
    std::atomic<napi_threadsafe_function> error_tsfn_{nullptr};

    /* Tsfn handles replaced by re-registration while a run was active.
     * Guarded by mutex_; kept until the run ends so the worker never calls
     * a handle whose only thread reference was released. */
    std::vector<napi_threadsafe_function> superseded_tsfn_;

    /* Summary state accumulated from JSON events, guarded by mutex_. */
    struct EndSummary {
        bool has_end = false;
        double sent_bps = 0.0;
        double received_bps = 0.0;
        double duration_sec = 0.0;
        bool has_retransmits = false;
        int32_t retransmits = 0;
        bool has_jitter_ms = false;
        double jitter_ms = 0.0;
        bool has_lost_pct = false;
        double lost_pct = 0.0;
        std::string error;
    } end_;

    /* Fallback accumulation from interval events (used when no "end" event
     * arrives, e.g. a cancelled test). */
    double acc_bytes_ = 0.0;
    double acc_end_sec_ = 0.0;
    int acc_intervals_ = 0;
};

#endif /* IPERF_NAPI_BRIDGE_H */
