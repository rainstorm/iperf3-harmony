// native 接口定义与 ArkTS 侧统一入口：页面只 import 本文件，不直接引 libiperf_napi.so 或 NativeIperfMock。
// 类型字段须与 entry/src/main/cpp/types/libiperf_napi/index.d.ts 保持一致；同类回调重复注册，后次覆盖前次。

import { start, stop, onInterval, onFinish, onError } from 'libiperf_napi.so';

export interface IperfConfig {
  role: 'client' | 'server';
  host?: string;            // client 必填，server 忽略
  port?: number;            // 默认 5201
  durationSec?: number;     // 默认 10
  parallel?: number;        // 并行流数，默认 1
  protocol: 'tcp' | 'udp';
  reverse?: boolean;        // 反向模式
  windowBytes?: number;
  blockSize?: number;
}

/** 每秒区间结果。TCP 带 retransmits；UDP 带 jitterMs / lostPct。 */
export interface IntervalResult {
  intervalId: number;
  startSec: number;
  endSec: number;
  bytes: number;
  bps: number;
  retransmits?: number;                 // TCP
  jitterMs?: number;
  lostPct?: number;                     // UDP
}

export interface SummaryResult {
  ok: boolean;
  sentBps: number;
  receivedBps: number;
  durationSec: number;
  retransmits?: number;
  jitterMs?: number;
  lostPct?: number;
  error?: string;
}

export interface IperfError {
  code: number;
  message: string;
}

/** 真实 so 与 NativeIperfMock 都实现这组接口。 */
export interface NativeIperf {
  start(config: IperfConfig): void;
  stop(): void;
  onInterval(cb: (r: IntervalResult) => void): void;
  onFinish(cb: (r: SummaryResult) => void): void;
  onError(cb: (e: IperfError) => void): void;
}

class NativeIperfReal implements NativeIperf {
  start(config: IperfConfig): void {
    start(config);
  }
  stop(): void {
    stop();
  }
  onInterval(cb: (r: IntervalResult) => void): void {
    onInterval(cb);
  }
  onFinish(cb: (r: SummaryResult) => void): void {
    onFinish(cb);
  }
  onError(cb: (e: IperfError) => void): void {
    onError(cb);
  }
}

export const native: NativeIperf = new NativeIperfReal();
