/* iperf_bridge.cpp -- NAPI bridge engine implementation. See iperf_bridge.h.
 * JSON event shapes verified against the bundled iperf 3.22 sources; the
 * stream callback's string is freed by iperf right after we return, so
 * events are parsed here synchronously.
 */
#include "iperf_bridge.h"

#include <chrono>
#include <cstring>
#include <exception>
#include <string>
#include <system_error>
#include <utility>

/* iperf_config.h must precede iperf_api.h: without HAVE_STDATOMIC_H the
 * header falls back to `typedef u_int64_t atomic_uint_fast64_t`, which does
 * not exist on musl. */
#include "iperf_config.h"
#include "iperf_api.h"          /* public libiperf API (has extern "C" guards) */
#include "cjson.h"              /* bundled cJSON (has extern "C" guards) */
#include "patch/iperf_cancel.h" /* local patch: cross-thread cancellation */

namespace {

napi_value Undefined(napi_env env)
{
    napi_value u = nullptr;
    napi_get_undefined(env, &u);
    return u;
}

char* DuplicateString(const char* s)
{
    if (s == nullptr)
        return nullptr;
    const size_t len = std::strlen(s);
    char* p = new char[len + 1];
    std::memcpy(p, s, len + 1);
    return p;
}

void SetInt32Prop(napi_env env, napi_value obj, const char* name, int32_t value)
{
    napi_value prop = nullptr;
    if (napi_create_int32(env, value, &prop) == napi_ok)
        napi_set_named_property(env, obj, name, prop);
}

void SetDoubleProp(napi_env env, napi_value obj, const char* name, double value)
{
    napi_value prop = nullptr;
    if (napi_create_double(env, value, &prop) == napi_ok)
        napi_set_named_property(env, obj, name, prop);
}

void SetStringProp(napi_env env, napi_value obj, const char* name, const char* value)
{
    napi_value prop = nullptr;
    if (napi_create_string_utf8(env, value, std::strlen(value), &prop) == napi_ok)
        napi_set_named_property(env, obj, name, prop);
}

/* Reads a property; absent/undefined/null counts as "not present". */
bool GetPropValue(napi_env env, napi_value obj, const char* name, napi_value* out)
{
    napi_value v = nullptr;
    if (napi_get_named_property(env, obj, name, &v) != napi_ok || v == nullptr)
        return false;
    napi_valuetype t = napi_undefined;
    if (napi_typeof(env, v, &t) != napi_ok)
        return false;
    if (t == napi_undefined || t == napi_null)
        return false;
    *out = v;
    return true;
}

bool GetStringProp(napi_env env, napi_value obj, const char* name, std::string* out)
{
    napi_value v = nullptr;
    if (!GetPropValue(env, obj, name, &v))
        return false;
    napi_valuetype t = napi_undefined;
    if (napi_typeof(env, v, &t) != napi_ok || t != napi_string)
        return false;
    size_t len = 0;
    if (napi_get_value_string_utf8(env, v, nullptr, 0, &len) != napi_ok)
        return false;
    if (len == 0) {
        out->clear();
        return true;
    }
    out->assign(len, '\0');
    size_t copied = 0;
    /* bufsize len+1 lets NAPI write its NUL terminator at out->[len]. */
    if (napi_get_value_string_utf8(env, v, &(*out)[0], len + 1, &copied) != napi_ok)
        return false;
    out->resize(copied);
    return true;
}

bool GetDoubleProp(napi_env env, napi_value obj, const char* name, double* out)
{
    napi_value v = nullptr;
    if (!GetPropValue(env, obj, name, &v))
        return false;
    napi_valuetype t = napi_undefined;
    if (napi_typeof(env, v, &t) != napi_ok || t != napi_number)
        return false;
    return napi_get_value_double(env, v, out) == napi_ok;
}

bool GetBoolProp(napi_env env, napi_value obj, const char* name, bool* out)
{
    napi_value v = nullptr;
    if (!GetPropValue(env, obj, name, &v))
        return false;
    napi_valuetype t = napi_undefined;
    if (napi_typeof(env, v, &t) != napi_ok || t != napi_boolean)
        return false;
    return napi_get_value_bool(env, v, out) == napi_ok;
}

/* cJSON accessors (borrowed objects; never delete the items). */
bool JsonGetDouble(const cJSON* obj, const char* key, double* out)
{
    const cJSON* item = cJSON_GetObjectItem(obj, key);
    if (item == nullptr || !cJSON_IsNumber(item))
        return false;
    *out = item->valuedouble;
    return true;
}

bool JsonGetInt32(const cJSON* obj, const char* key, int32_t* out)
{
    double d = 0.0;
    if (!JsonGetDouble(obj, key, &d))
        return false;
    *out = static_cast<int32_t>(d);
    return true;
}

/* call_js trampolines: run on the ArkTS thread; consume and free the
 * heap message. */
void IntervalCallJs(napi_env env, napi_value js_cb, void* /*context*/, void* data)
{
    auto* msg = static_cast<IperfIntervalMsg*>(data);
    if (msg == nullptr)
        return;
    if (env != nullptr && js_cb != nullptr) {
        napi_value obj = nullptr;
        if (napi_create_object(env, &obj) == napi_ok) {
            SetInt32Prop(env, obj, "intervalId", msg->interval_id);
            SetDoubleProp(env, obj, "startSec", msg->start_sec);
            SetDoubleProp(env, obj, "endSec", msg->end_sec);
            SetDoubleProp(env, obj, "bytes", msg->bytes);
            SetDoubleProp(env, obj, "bps", msg->bps);
            if (msg->has_retransmits)
                SetInt32Prop(env, obj, "retransmits", msg->retransmits);
            if (msg->has_jitter_ms)
                SetDoubleProp(env, obj, "jitterMs", msg->jitter_ms);
            if (msg->has_lost_pct)
                SetDoubleProp(env, obj, "lostPct", msg->lost_pct);
            napi_value undef = nullptr;
            napi_get_undefined(env, &undef);
            napi_value argv[1] = { obj };
            napi_call_function(env, undef, js_cb, 1, argv, nullptr);
        }
    }
    delete msg;
}

void SummaryCallJs(napi_env env, napi_value js_cb, void* /*context*/, void* data)
{
    auto* msg = static_cast<IperfSummaryMsg*>(data);
    if (msg == nullptr)
        return;
    if (env != nullptr && js_cb != nullptr) {
        napi_value obj = nullptr;
        if (napi_create_object(env, &obj) == napi_ok) {
            napi_value b = nullptr;
            napi_get_boolean(env, msg->ok, &b);
            napi_set_named_property(env, obj, "ok", b);
            SetDoubleProp(env, obj, "sentBps", msg->sent_bps);
            SetDoubleProp(env, obj, "receivedBps", msg->received_bps);
            SetDoubleProp(env, obj, "durationSec", msg->duration_sec);
            if (msg->has_retransmits)
                SetInt32Prop(env, obj, "retransmits", msg->retransmits);
            if (msg->has_jitter_ms)
                SetDoubleProp(env, obj, "jitterMs", msg->jitter_ms);
            if (msg->has_lost_pct)
                SetDoubleProp(env, obj, "lostPct", msg->lost_pct);
            if (msg->error != nullptr)
                SetStringProp(env, obj, "error", msg->error);
            napi_value undef = nullptr;
            napi_get_undefined(env, &undef);
            napi_value argv[1] = { obj };
            napi_call_function(env, undef, js_cb, 1, argv, nullptr);
        }
    }
    delete[] msg->error;
    delete msg;
}

void ErrorCallJs(napi_env env, napi_value js_cb, void* /*context*/, void* data)
{
    auto* msg = static_cast<IperfErrorMsg*>(data);
    if (msg == nullptr)
        return;
    if (env != nullptr && js_cb != nullptr) {
        napi_value obj = nullptr;
        if (napi_create_object(env, &obj) == napi_ok) {
            SetInt32Prop(env, obj, "code", msg->code);
            SetStringProp(env, obj, "message", msg->message != nullptr ? msg->message : "");
            napi_value undef = nullptr;
            napi_get_undefined(env, &undef);
            napi_value argv[1] = { obj };
            napi_call_function(env, undef, js_cb, 1, argv, nullptr);
        }
    }
    delete[] msg->message;
    delete msg;
}

} /* namespace */

/* JSON-stream callback. C linkage: iperf_api.h:208 declares a C
 * function-pointer type. Runs on iperf's reporter-timer thread for
 * "interval" events and on the worker thread for start/end/error; the
 * engine is a singleton running at most one test at a time, so
 * dispatching via the singleton is exact. */

extern "C" {
static void IperfJsonStreamCallback(struct iperf_test* test, char* json)
{
    (void) test;
    IperfEngine::Get().HandleJsonEvent(json);
}
} /* extern "C" */

IperfEngine::IperfEngine()
{
}

IperfEngine::~IperfEngine()
{
    /* Process teardown, best effort: make a running test exit so the worker
     * reaches iperf_free_test(), then join the engine threads (bounded: the
     * watchdog exits on the shutdown flag, the worker after the forced
     * abort). The cancel runs under mutex_ so it can never act on a test
     * the worker has already unpublished and freed. */
    cancel_requested_.store(true);
    {
        std::lock_guard<std::mutex> g(mutex_);
        if (test_ != nullptr) {
            iperf_cancel_test(test_);
            iperf_force_abort_test(test_);
        }
    }
    {
        std::lock_guard<std::mutex> lk(watchdog_mutex_);
        watchdog_shutdown_ = true;
    }
    watchdog_cv_.notify_all();
    if (watchdog_.joinable())
        watchdog_.join();
    if (worker_.joinable())
        worker_.join();
    /* The worker's own end-of-run drain released any tsfns superseded
     * during the last run. tsfns still live in the slots are deliberately
     * not released here (static teardown may race the JS runtime); they are
     * released whenever a callback is re-registered. */
}

IperfEngine& IperfEngine::Get()
{
    static IperfEngine instance;
    return instance;
}

void IperfEngine::EmitInterval(IperfIntervalMsg* msg)
{
    napi_threadsafe_function tsfn = interval_tsfn_.load(std::memory_order_acquire);
    if (tsfn == nullptr) {
        delete msg;
        return;
    }
    if (napi_call_threadsafe_function(tsfn, msg, napi_tsfn_nonblocking) != napi_ok)
        delete msg;
}

void IperfEngine::EmitFinish(IperfSummaryMsg* msg)
{
    napi_threadsafe_function tsfn = finish_tsfn_.load(std::memory_order_acquire);
    if (tsfn == nullptr) {
        delete[] msg->error;
        delete msg;
        return;
    }
    if (napi_call_threadsafe_function(tsfn, msg, napi_tsfn_nonblocking) != napi_ok) {
        delete[] msg->error;
        delete msg;
    }
}

void IperfEngine::EmitError(int32_t code, const char* message)
{
    auto* msg = new IperfErrorMsg{};
    msg->code = code;
    msg->message = DuplicateString(message != nullptr ? message : "unknown error");
    napi_threadsafe_function tsfn = error_tsfn_.load(std::memory_order_acquire);
    if (tsfn == nullptr || napi_call_threadsafe_function(tsfn, msg, napi_tsfn_nonblocking) != napi_ok) {
        delete[] msg->message;
        delete msg;
    }
}

void IperfEngine::HandleJsonEvent(const char* json)
{
    if (json == nullptr)
        return;
    cJSON* root = cJSON_Parse(json);
    if (root == nullptr)
        return;
    cJSON* ev = cJSON_GetObjectItem(root, "event");
    cJSON* data = cJSON_GetObjectItem(root, "data");
    const char* evname = (ev != nullptr && cJSON_IsString(ev)) ? cJSON_GetStringValue(ev) : nullptr;
    if (evname != nullptr && data != nullptr) {
        if (std::strcmp(evname, "interval") == 0 && cJSON_IsObject(data)) {
            HandleIntervalEvent(data);
        } else if (std::strcmp(evname, "end") == 0 && cJSON_IsObject(data)) {
            HandleEndEvent(data);
        } else if (std::strcmp(evname, "error") == 0 && cJSON_IsString(data)) {
            const char* err = cJSON_GetStringValue(data);
            if (err != nullptr) {
                std::lock_guard<std::mutex> g(mutex_);
                end_.error = err;
            }
        }
        /* "start", "server_output_json", "server_output_text": ignored. */
    }
    cJSON_Delete(root);
}

void IperfEngine::HandleIntervalEvent(void* data_obj)
{
    const cJSON* data = static_cast<const cJSON*>(data_obj);
    /* One aggregate per interval; bidirectional runs also emit
     * "sum_bidir_reverse", which we drop. iperf_print_intermediate() names
     * the aggregate "sum" when this side is the sender but "sum_received"
     * when it is the receiver (iperf_api.c:4174), so accept either name. */
    const cJSON* sum = cJSON_GetObjectItem(data, "sum");
    if (sum == nullptr)
        sum = cJSON_GetObjectItem(data, "sum_received");
    if (sum == nullptr)
        sum = cJSON_GetObjectItem(data, "sum_sent");
    if (sum == nullptr)
        return;

    auto* msg = new IperfIntervalMsg{};
    msg->interval_id = interval_seq_.fetch_add(1, std::memory_order_relaxed) + 1;
    double d = 0.0;
    int32_t i32 = 0;
    if (JsonGetDouble(sum, "start", &d))
        msg->start_sec = d;
    if (JsonGetDouble(sum, "end", &d))
        msg->end_sec = d;
    if (JsonGetDouble(sum, "bytes", &d))
        msg->bytes = d;
    if (JsonGetDouble(sum, "bits_per_second", &d))
        msg->bps = d;
    if (JsonGetInt32(sum, "retransmits", &i32)) {
        msg->has_retransmits = true;
        msg->retransmits = i32;
    }
    if (JsonGetDouble(sum, "jitter_ms", &d)) {
        msg->has_jitter_ms = true;
        msg->jitter_ms = d;
    }
    if (JsonGetDouble(sum, "lost_percent", &d)) {
        msg->has_lost_pct = true;
        msg->lost_pct = d;
    }

    {
        std::lock_guard<std::mutex> g(mutex_);
        acc_bytes_ += msg->bytes;
        if (msg->end_sec > acc_end_sec_)
            acc_end_sec_ = msg->end_sec;
        acc_intervals_++;
    }
    EmitInterval(msg);
}

void IperfEngine::HandleEndEvent(void* data_obj)
{
    const cJSON* data = static_cast<const cJSON*>(data_obj);
    std::lock_guard<std::mutex> g(mutex_);
    end_.has_end = true;

    double d = 0.0;
    int32_t i32 = 0;
    const cJSON* sum_sent = cJSON_GetObjectItem(data, "sum_sent");
    const cJSON* sum_received = cJSON_GetObjectItem(data, "sum_received");
    const cJSON* sum = cJSON_GetObjectItem(data, "sum");

    if (sum_sent != nullptr) {
        if (JsonGetDouble(sum_sent, "bits_per_second", &d))
            end_.sent_bps = d;
        if (JsonGetDouble(sum_sent, "seconds", &d))
            end_.duration_sec = d;
        if (JsonGetInt32(sum_sent, "retransmits", &i32)) {
            end_.has_retransmits = true;
            end_.retransmits = i32;
        }
    }
    if (sum_received != nullptr) {
        if (JsonGetDouble(sum_received, "bits_per_second", &d))
            end_.received_bps = d;
        if (end_.duration_sec == 0.0 && JsonGetDouble(sum_received, "seconds", &d))
            end_.duration_sec = d;
        if (JsonGetDouble(sum_received, "jitter_ms", &d)) {
            end_.has_jitter_ms = true;
            end_.jitter_ms = d;
        }
        if (JsonGetDouble(sum_received, "lost_percent", &d)) {
            end_.has_lost_pct = true;
            end_.lost_pct = d;
        }
    }
    if (sum != nullptr) {
        /* UDP "legacy" mixed summary: fallback source for jitter/loss. */
        if (!end_.has_jitter_ms && JsonGetDouble(sum, "jitter_ms", &d)) {
            end_.has_jitter_ms = true;
            end_.jitter_ms = d;
        }
        if (!end_.has_lost_pct && JsonGetDouble(sum, "lost_percent", &d)) {
            end_.has_lost_pct = true;
            end_.lost_pct = d;
        }
        if (end_.duration_sec == 0.0 && JsonGetDouble(sum, "seconds", &d))
            end_.duration_sec = d;
    }
}

void IperfEngine::WorkerMain(IperfRunConfig cfg)
{
    struct iperf_test* test = iperf_new_test();
    if (test == nullptr) {
        EmitError(IPERF_NAPI_ERR_INTERNAL, "iperf_new_test() failed (out of memory)");
        auto* msg = new IperfSummaryMsg{};
        msg->ok = false;
        msg->error = DuplicateString("iperf_new_test() failed (out of memory)");
        EmitFinish(msg);
        running_.store(false);
        return;
    }
    iperf_defaults(test);

    /* Configure through the public setters (mic.c/mis.c pattern). */
    iperf_set_test_role(test, cfg.role);
    if (cfg.role == 'c')
        iperf_set_test_server_hostname(test, cfg.host.c_str());
    iperf_set_test_server_port(test, static_cast<int>(cfg.port));
    iperf_set_test_duration(test, static_cast<int>(cfg.duration));
    iperf_set_test_num_streams(test, static_cast<int>(cfg.parallel));
    if (set_protocol(test, cfg.udp ? Pudp : Ptcp) != 0) {
        const int ierr = i_errno;
        iperf_free_test(test);
        const char* text = iperf_strerror(ierr);
        EmitError(static_cast<int32_t>(ierr), text);
        auto* msg = new IperfSummaryMsg{};
        msg->ok = false;
        msg->error = DuplicateString(text);
        EmitFinish(msg);
        running_.store(false);
        return;
    }
    if (cfg.reverse)
        iperf_set_test_reverse(test, 1);
    if (cfg.window > 0)
        iperf_set_test_socket_bufsize(test, static_cast<int>(cfg.window));
    /* UDP block size: libiperf seeds blksize with the TCP default (128 KiB,
     * iperf_api.h:67), which is larger than MAX_UDP_BLOCKSIZE = 65507
     * (iperf.h:469). The CLI leaves blksize at 0 for -u and resolves the UDP
     * default lazily in iperf_connect() (iperf_client_api.c:512-521), so an
     * API caller carrying 128 KiB is never corrected and a peer server
     * rejects the run with IEUDPBLOCKSIZE. Apply the UDP default when the
     * caller left blockSize unset (<= 0). */
    if (cfg.udp && cfg.blksize <= 0)
        cfg.blksize = DEFAULT_UDP_BLKSIZE; /* 1460; iperf_api.h:66 */
    if (cfg.blksize > 0)
        iperf_set_test_blksize(test, static_cast<int>(cfg.blksize));

    /* JSON-stream mode is 3.22's interval callback (no public per-interval
     * hook exists). Mirrors the CLI --json-stream handling
     * (src/iperf_api.c:1280-1283): json_output must also be enabled, or
     * iperf_json_start()/json_finish() never run. */
    iperf_set_test_json_output(test, 1);
    iperf_set_test_json_stream(test, 1);
    iperf_set_test_json_callback(test, &IperfJsonStreamCallback);

    {
        std::lock_guard<std::mutex> g(mutex_);
        end_ = EndSummary();
        acc_bytes_ = 0.0;
        acc_end_sec_ = 0.0;
        acc_intervals_ = 0;
        test_ = test; /* published for stop() */
    }

    int rc = 0;
    int ierr = 0;
    if (cancel_requested_.load()) {
        /* stop() arrived in the window before the run started; i_errno is
         * left untouched (it is a global that may hold a stale value). */
        rc = -1;
    } else if (cfg.role == 'c') {
        rc = iperf_run_client(test); /* blocking; no iperf_run() exists in 3.22 */
        if (rc != 0)
            ierr = i_errno;
    } else {
        rc = iperf_run_server(test); /* blocking; one client session per start() */
        if (rc != 0)
            ierr = i_errno;
    }

    {
        std::lock_guard<std::mutex> g(mutex_);
        test_ = nullptr; /* unpublish before freeing */
    }
    iperf_free_test(test); /* every path: normal completion, error, cancel */

    FinishWorker(rc, ierr, cfg);
    running_.store(false); /* no further tsfn calls from this thread */
    /* Release tsfn handles that were superseded by callback re-registration
     * during this run; deferred until now so in-flight calls on the worker
     * thread could never race their destruction. */
    DrainSupersededTsfns();
}

void IperfEngine::FinishWorker(int rc, int iperf_errno, const IperfRunConfig& cfg)
{
    const bool cancelled = cancel_requested_.load();

    EndSummary snap;
    double acc_bytes = 0.0;
    double acc_end = 0.0;
    int acc_count = 0;
    {
        std::lock_guard<std::mutex> g(mutex_);
        snap = end_;
        acc_bytes = acc_bytes_;
        acc_end = acc_end_sec_;
        acc_count = acc_intervals_;
    }

    auto* msg = new IperfSummaryMsg{};

    if (snap.has_end) {
        msg->sent_bps = snap.sent_bps;
        msg->received_bps = snap.received_bps;
        msg->duration_sec = snap.duration_sec;
        msg->has_retransmits = snap.has_retransmits;
        msg->retransmits = snap.retransmits;
        msg->has_jitter_ms = snap.has_jitter_ms;
        msg->jitter_ms = snap.jitter_ms;
        msg->has_lost_pct = snap.has_lost_pct;
        msg->lost_pct = snap.lost_pct;
    } else if (acc_count > 0 && acc_end > 0.0) {
        /* No "end" event (cancelled or failed before the final report):
         * fall back to accumulated interval bytes. That rate is the sending
         * side for a client and the receiving side for a server. */
        const double bps = acc_bytes * 8.0 / acc_end;
        msg->sent_bps = (cfg.role == 'c') ? bps : 0.0;
        msg->received_bps = (cfg.role == 's') ? bps : 0.0;
        msg->duration_sec = acc_end;
    } else {
        msg->duration_sec = (cfg.role == 'c') ? static_cast<double>(cfg.duration) : 0.0;
    }

    if (cancelled) {
        msg->ok = false;
        msg->error = DuplicateString("canceled");
    } else if (rc != 0) {
        msg->ok = false;
        const std::string text = !snap.error.empty() ? snap.error : iperf_strerror(iperf_errno);
        msg->error = DuplicateString(text.c_str());
        EmitError(static_cast<int32_t>(iperf_errno), text.c_str());
    } else {
        msg->ok = true;
        msg->error = nullptr;
    }

    EmitFinish(msg);
}

void IperfEngine::ScheduleForceAbort(std::chrono::milliseconds delay)
{
    {
        std::lock_guard<std::mutex> lk(watchdog_mutex_);
        watchdog_deadline_ = std::chrono::steady_clock::now() + delay;
    }
    if (!watchdog_.joinable())
        watchdog_ = std::thread(&IperfEngine::WatchdogMain, this);
    watchdog_cv_.notify_one();
}

void IperfEngine::WatchdogMain()
{
    std::unique_lock<std::mutex> lk(watchdog_mutex_);
    for (;;) {
        watchdog_cv_.wait(lk, [this] {
            return watchdog_shutdown_ ||
                   watchdog_deadline_.time_since_epoch() != std::chrono::steady_clock::duration::zero();
        });
        if (watchdog_shutdown_)
            return;
        const std::chrono::steady_clock::time_point deadline = watchdog_deadline_;
        watchdog_deadline_ = std::chrono::steady_clock::time_point{};
        lk.unlock();

        while (running_.load() && std::chrono::steady_clock::now() < deadline)
            std::this_thread::sleep_for(std::chrono::milliseconds(50));

        if (running_.load()) {
            /* Force-abort under mutex_: the worker nulls test_ under the
             * same mutex before iperf_free_test(), so this can never act on
             * a freed struct. */
            {
                std::lock_guard<std::mutex> g(mutex_);
                if (test_ != nullptr)
                    iperf_force_abort_test(test_);
            }
            /* Bounded grace period for the worker's cleanup. */
            for (int i = 0; i < 100 && running_.load(); ++i)
                std::this_thread::sleep_for(std::chrono::milliseconds(50));
        }
        lk.lock();
    }
}

void IperfEngine::DrainSupersededTsfns()
{
    std::vector<napi_threadsafe_function> drain;
    {
        std::lock_guard<std::mutex> g(mutex_);
        drain.swap(superseded_tsfn_);
    }
    for (napi_threadsafe_function handle : drain)
        napi_release_threadsafe_function(handle, napi_tsfn_release);
}

/* NAPI entry points (ArkTS thread) */

napi_value IperfEngine::RegisterCallback(napi_env env, napi_callback_info info,
                                         const char* tsfn_name,
                                         void (*call_js)(napi_env, napi_value, void*, void*),
                                         std::atomic<napi_threadsafe_function>& slot)
{
    size_t argc = 1;
    napi_value argv[1] = { nullptr };
    if (napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) != napi_ok || argc < 1) {
        napi_throw_type_error(env, nullptr, "a callback function argument is required");
        return nullptr;
    }
    napi_valuetype type = napi_undefined;
    if (napi_typeof(env, argv[0], &type) != napi_ok || type != napi_function) {
        napi_throw_type_error(env, nullptr, "callback argument must be a function");
        return nullptr;
    }

    napi_value name = nullptr;
    napi_create_string_utf8(env, tsfn_name, std::strlen(tsfn_name), &name);
    napi_threadsafe_function tsfn = nullptr;
    /* max_queue_size 0 = unbounded queue (interval bursts must never be
     * dropped under backpressure); initial_thread_count 1 is the engine's
     * single logical user. */
    napi_status st = napi_create_threadsafe_function(env, argv[0], nullptr, name,
                                                     0, 1,
                                                     nullptr, /* thread_finalize_data */
                                                     nullptr, /* thread_finalize_cb */
                                                     nullptr, /* context */
                                                     call_js, /* call_js_cb */
                                                     &tsfn);  /* result */
    if (st != napi_ok || tsfn == nullptr) {
        napi_throw_error(env, nullptr, "failed to create threadsafe function");
        return nullptr;
    }

    /* Re-registration overrides the previous callback. Releasing the old
     * tsfn immediately would be a use-after-free if the worker is between
     * loading the handle and calling it. While a run is active the old
     * handle is parked and released when the run ends (DrainSupersededTsfns);
     * when idle no other thread can call it, so it is released right away. */
    napi_threadsafe_function old = nullptr;
    {
        std::lock_guard<std::mutex> g(mutex_);
        old = slot.exchange(tsfn);
        if (old != nullptr && running_.load()) {
            superseded_tsfn_.push_back(old);
            old = nullptr;
        }
    }
    if (old != nullptr)
        napi_release_threadsafe_function(old, napi_tsfn_release);
    return Undefined(env);
}

napi_value IperfEngine::OnInterval(napi_env env, napi_callback_info info)
{
    return RegisterCallback(env, info, "iperf_napi_on_interval", &IntervalCallJs, interval_tsfn_);
}

napi_value IperfEngine::OnFinish(napi_env env, napi_callback_info info)
{
    return RegisterCallback(env, info, "iperf_napi_on_finish", &SummaryCallJs, finish_tsfn_);
}

napi_value IperfEngine::OnError(napi_env env, napi_callback_info info)
{
    return RegisterCallback(env, info, "iperf_napi_on_error", &ErrorCallJs, error_tsfn_);
}

napi_value IperfEngine::Start(napi_env env, napi_callback_info info)
{
    size_t argc = 1;
    napi_value argv[1] = { nullptr };
    if (napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr) != napi_ok || argc < 1) {
        EmitError(IPERF_NAPI_ERR_INVALID_CONFIG, "start(config) requires an IperfConfig object");
        return Undefined(env);
    }
    napi_valuetype type = napi_undefined;
    if (napi_typeof(env, argv[0], &type) != napi_ok || type != napi_object) {
        EmitError(IPERF_NAPI_ERR_INVALID_CONFIG, "start(config) requires an IperfConfig object");
        return Undefined(env);
    }
    napi_value config = argv[0];

    IperfRunConfig cfg;
    cfg.role = 'c';
    cfg.udp = false;
    cfg.port = 5201;   /* PORT, src/iperf.h:446 */
    cfg.duration = 10; /* DURATION, src/iperf.h:453 */
    cfg.parallel = 1;
    cfg.reverse = false;
    cfg.window = 0;   /* 0 = keep iperf default (socket autotuning; safe for TCP+UDP) */
    cfg.blksize = 0;  /* 0 = not set: TCP keeps 128 KiB, UDP gets DEFAULT_UDP_BLKSIZE */

    std::string role;
    if (!GetStringProp(env, config, "role", &role) || (role != "client" && role != "server")) {
        EmitError(IPERF_NAPI_ERR_INVALID_CONFIG, "config.role must be 'client' or 'server'");
        return Undefined(env);
    }
    cfg.role = (role == "client") ? 'c' : 's';

    std::string protocol;
    if (!GetStringProp(env, config, "protocol", &protocol) || (protocol != "tcp" && protocol != "udp")) {
        EmitError(IPERF_NAPI_ERR_INVALID_CONFIG, "config.protocol must be 'tcp' or 'udp'");
        return Undefined(env);
    }
    cfg.udp = (protocol == "udp");

    (void) GetStringProp(env, config, "host", &cfg.host);
    if (cfg.role == 'c' && cfg.host.empty()) {
        EmitError(IPERF_NAPI_ERR_INVALID_CONFIG, "config.host is required when role is 'client'");
        return Undefined(env);
    }

    double num = 0.0;
    if (GetDoubleProp(env, config, "port", &num))
        cfg.port = static_cast<int32_t>(num);
    if (GetDoubleProp(env, config, "durationSec", &num))
        cfg.duration = static_cast<int32_t>(num);
    if (GetDoubleProp(env, config, "parallel", &num))
        cfg.parallel = static_cast<int32_t>(num);
    if (GetDoubleProp(env, config, "windowBytes", &num))
        cfg.window = static_cast<int32_t>(num);
    if (GetDoubleProp(env, config, "blockSize", &num))
        cfg.blksize = static_cast<int32_t>(num);
    (void) GetBoolProp(env, config, "reverse", &cfg.reverse);

    /* Range checks mirror the CLI limits (src/iperf.h:462-476). */
    if (cfg.port < 1 || cfg.port > 65535) {
        EmitError(IPERF_NAPI_ERR_INVALID_CONFIG, "config.port must be within 1..65535");
        return Undefined(env);
    }
    if (cfg.duration < 1 || cfg.duration > 86400) { /* MAX_TIME */
        EmitError(IPERF_NAPI_ERR_INVALID_CONFIG, "config.durationSec must be within 1..86400");
        return Undefined(env);
    }
    if (cfg.parallel < 1 || cfg.parallel > 128) { /* MAX_STREAMS */
        EmitError(IPERF_NAPI_ERR_INVALID_CONFIG, "config.parallel must be within 1..128");
        return Undefined(env);
    }
    if (cfg.window < 0 || cfg.blksize < 0) {
        EmitError(IPERF_NAPI_ERR_INVALID_CONFIG, "config.windowBytes/blockSize must be >= 0 (0 = default)");
        return Undefined(env);
    }

    if (running_.load()) {
        EmitError(IPERF_NAPI_ERR_ALREADY_RUNNING, "an iperf test is already running");
        return Undefined(env);
    }

    /* running_ == false guarantees the previous WorkerMain returned; join
     * its (finished) thread before reusing the std::thread member. */
    if (worker_.joinable())
        worker_.join();

    cancel_requested_.store(false);
    interval_seq_.store(0);
    running_.store(true);
    try {
        worker_ = std::thread(&IperfEngine::WorkerMain, this, cfg);
    } catch (const std::exception& e) {
        /* std::thread construction failed (std::system_error, e.g. EAGAIN
         * under resource pressure; bad_alloc is also possible). Roll
         * running_ back, otherwise the already-running check above would
         * permanently reject every later start() until app restart. */
        running_.store(false);
        const std::string text = std::string("failed to start worker thread: ") + e.what();
        EmitError(IPERF_NAPI_ERR_INTERNAL, text.c_str());
        return Undefined(env);
    }
    return Undefined(env);
}

napi_value IperfEngine::Stop(napi_env env, napi_callback_info info)
{
    (void) info;
    if (!running_.load())
        return Undefined(env); /* nothing to stop */

    cancel_requested_.store(true);

    {
        /* Cancel under mutex_: the worker nulls test_ under the same mutex
         * before iperf_free_test(), so a cancel issued inside this critical
         * section can never act on a freed struct iperf_test. */
        std::lock_guard<std::mutex> g(mutex_);
        if (test_ != nullptr)
            iperf_cancel_test(test_); /* graceful; see patch/iperf_cancel.h */
    }

    /* Escalation: if the worker is still running in ~3 s (e.g. blocked in a
     * control-phase select() because the peer died), force-abort so the run
     * still reaches iperf_free_test(). */
    ScheduleForceAbort(std::chrono::milliseconds(3000));
    return Undefined(env);
}
