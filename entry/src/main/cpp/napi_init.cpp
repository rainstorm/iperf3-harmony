/*
 * NAPI module registration for libiperf_napi.so; the logic lives in
 * iperf_bridge.cpp (IperfEngine). ArkTS-side type declarations:
 * types/libiperf_napi/index.d.ts.
 */
#include "napi/native_api.h"

#include "iperf_bridge.h"

static napi_value Start(napi_env env, napi_callback_info info)
{
    return IperfEngine::Get().Start(env, info);
}

static napi_value Stop(napi_env env, napi_callback_info info)
{
    return IperfEngine::Get().Stop(env, info);
}

static napi_value OnInterval(napi_env env, napi_callback_info info)
{
    return IperfEngine::Get().OnInterval(env, info);
}

static napi_value OnFinish(napi_env env, napi_callback_info info)
{
    return IperfEngine::Get().OnFinish(env, info);
}

static napi_value OnError(napi_env env, napi_callback_info info)
{
    return IperfEngine::Get().OnError(env, info);
}

#ifdef __cplusplus
extern "C" {
#endif

static napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        { "start", nullptr, Start, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "stop", nullptr, Stop, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "onInterval", nullptr, OnInterval, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "onFinish", nullptr, OnFinish, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "onError", nullptr, OnError, nullptr, nullptr, nullptr, napi_default, nullptr },
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}

static napi_module iperfModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "iperf_napi", /* -> libiperf_napi.so, import 'libiperf_napi.so' */
    .nm_priv = nullptr,
    .reserved = { 0 },
};

__attribute__((constructor)) void RegisterIperfModule(void)
{
    napi_module_register(&iperfModule);
}

#ifdef __cplusplus
}
#endif
