/**
 * libiperf_napi.so -- iperf3 (ESnet, BSD-3-Clause) native module.
 * Field names and types must match iperf_bridge.cpp exactly; ArkTS code
 * imports this only through entry/src/main/ets/common/NativeIperf.ets.
 *
 *  - Register onInterval/onFinish/onError before start(); a later
 *    registration replaces the earlier one. Re-registering mid-run is safe:
 *    events go to the new callback, the old one is released at run end.
 *  - start() returns immediately (the test runs on a native worker thread);
 *    a second start() while running reports code -1 "already running".
 *  - onFinish fires exactly once per started test, on every path; onError
 *    additionally fires for non-cancellation failures.
 *  - stop() interrupts the test; the summary then reports ok=false with
 *    error "canceled".
 *  - IperfError.code: negative = NAPI layer (-1 already running, -2 invalid
 *    config, -3 internal); positive = libiperf i_errno codes
 *    (third_party/iperf/src/iperf_api.h).
 *  - Server mode: one start() serves one client session; call start()
 *    again to keep listening.
 *  - IntervalResult.intervalId is a 1-based sequence number.
 */

export interface IperfConfig {
  role: 'client' | 'server';
  host?: string;            // client 必填，server 忽略
  port?: number;            // 默认 5201
  durationSec?: number;     // 默认 10
  parallel?: number;        // 并行流数，默认 1
  protocol: 'tcp' | 'udp';
  reverse?: boolean;
  windowBytes?: number;     // 0 = iperf 默认
  blockSize?: number;       // 0 = iperf 默认
}

export interface IntervalResult {
  intervalId: number; startSec: number; endSec: number;
  bytes: number; bps: number;
  retransmits?: number;                 // TCP
  jitterMs?: number; lostPct?: number;  // UDP
}

export interface SummaryResult {
  ok: boolean; sentBps: number; receivedBps: number; durationSec: number;
  retransmits?: number; jitterMs?: number; lostPct?: number; error?: string;
}

export interface IperfError { code: number; message: string }

export const start: (config: IperfConfig) => void;
export const stop: () => void;
export const onInterval: (cb: (r: IntervalResult) => void) => void;
export const onFinish: (cb: (r: SummaryResult) => void) => void;
export const onError: (cb: (e: IperfError) => void) => void;
