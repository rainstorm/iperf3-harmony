/**
 * NativeIperf 开发期替身，仅供 UI 联调；页面统一走 NativeIperf.ets，不要直接 import 本文件。
 * stop() 语义对齐 cpp/types/libiperf_napi/index.d.ts：中断时汇总报 ok:false、error:'canceled'。
 */

import { IperfConfig, IperfError, IntervalResult, NativeIperf, SummaryResult } from './NativeIperf';

const DEFAULT_PORT: number = 5201;
const DEFAULT_DURATION_SEC: number = 10;
const DEFAULT_PARALLEL: number = 1;

const ERR_INVALID_CONFIG: number = 1;
const ERR_ALREADY_RUNNING: number = 2;

const TICK_MS: number = 1000;
// 模拟基准速率（bps）：TCP 约 900 Mbps，UDP 约 400 Mbps
const BASE_BPS_TCP: number = 9.0e8;
const BASE_BPS_UDP: number = 4.0e8;

function round3(v: number): number {
  return Math.round(v * 1000) / 1000;
}

class NativeIperfDevStub implements NativeIperf {
  private intervalCb: ((r: IntervalResult) => void) | null = null;
  private finishCb: ((r: SummaryResult) => void) | null = null;
  private errorCb: ((e: IperfError) => void) | null = null;

  private running: boolean = false;
  private timerId: number = -1;
  private role: 'client' | 'server' = 'client';
  private protocol: 'tcp' | 'udp' = 'tcp';
  private durationSec: number = DEFAULT_DURATION_SEC;
  private parallel: number = DEFAULT_PARALLEL;
  private elapsedSec: number = 0;
  private intervalId: number = 0;
  private totalBytes: number = 0;
  private totalRetransmits: number = 0;
  private jitterAccMs: number = 0;
  private lostAccPct: number = 0;

  start(config: IperfConfig): void {
    if (this.running) {
      this.emitError(ERR_ALREADY_RUNNING, '已有测试在运行，请先调用 stop()');
      return;
    }
    const errMsg: string = this.validate(config);
    if (errMsg.length > 0) {
      this.emitError(ERR_INVALID_CONFIG, errMsg);
      return;
    }
    this.role = config.role;
    this.protocol = config.protocol;
    this.durationSec = config.durationSec !== undefined ? config.durationSec : DEFAULT_DURATION_SEC;
    this.parallel = config.parallel !== undefined ? config.parallel : DEFAULT_PARALLEL;
    this.elapsedSec = 0;
    this.intervalId = 0;
    this.totalBytes = 0;
    this.totalRetransmits = 0;
    this.jitterAccMs = 0;
    this.lostAccPct = 0;
    this.running = true;

    if (this.role === 'server') {
      // 模拟监听等待：只计时，不产生区间数据，直到 stop() 结束
      this.timerId = setInterval(() => {
        this.elapsedSec += 1;
      }, TICK_MS);
      return;
    }
    this.timerId = setInterval(() => {
      this.tick();
    }, TICK_MS);
  }

  stop(): void {
    if (!this.running) {
      return;
    }
    this.clearTimer();
    this.running = false;
    this.emitFinish(true);
  }

  onInterval(cb: (r: IntervalResult) => void): void {
    this.intervalCb = cb;
  }

  onFinish(cb: (r: SummaryResult) => void): void {
    this.finishCb = cb;
  }

  onError(cb: (e: IperfError) => void): void {
    this.errorCb = cb;
  }

  private tick(): void {
    this.elapsedSec += 1;
    this.intervalId += 1;
    const base: number = this.protocol === 'udp' ? BASE_BPS_UDP : BASE_BPS_TCP;
    // 慢速正弦波动叠加随机噪声，模拟速率波动
    const wave: number = 1.0 + 0.08 * Math.sin(this.elapsedSec / 3.0);
    const noise: number = 0.9 + 0.2 * Math.random();
    const bps: number = base * wave * noise * this.parallel;
    const bytes: number = Math.floor(bps / 8.0);
    this.totalBytes += bytes;

    let r: IntervalResult;
    if (this.protocol === 'tcp') {
      const retransmits: number = Math.floor(Math.random() * 6);
      this.totalRetransmits += retransmits;
      r = {
        intervalId: this.intervalId,
        startSec: this.elapsedSec - 1,
        endSec: this.elapsedSec,
        bytes: bytes,
        bps: bps,
        retransmits: retransmits
      };
    } else {
      const jitterMs: number = round3(0.05 + Math.random() * 0.45);
      const lostPct: number = round3(Math.random() * 0.8);
      this.jitterAccMs += jitterMs;
      this.lostAccPct += lostPct;
      r = {
        intervalId: this.intervalId,
        startSec: this.elapsedSec - 1,
        endSec: this.elapsedSec,
        bytes: bytes,
        bps: bps,
        jitterMs: jitterMs,
        lostPct: lostPct
      };
    }
    if (this.intervalCb !== null) {
      this.intervalCb(r);
    }
    if (this.elapsedSec >= this.durationSec) {
      this.clearTimer();
      this.running = false;
      this.emitFinish(false);
    }
  }

  private emitFinish(canceled: boolean): void {
    const dur: number = this.elapsedSec;
    let avgBps: number = 0;
    if (this.role === 'client' && dur > 0) {
      avgBps = this.totalBytes * 8.0 / dur;
    }
    let s: SummaryResult;
    if (canceled) {
      s = {
        ok: false,
        sentBps: avgBps,
        receivedBps: avgBps,
        durationSec: dur,
        error: 'canceled'
      };
    } else if (this.protocol === 'tcp') {
      s = {
        ok: true,
        sentBps: avgBps,
        receivedBps: avgBps,
        durationSec: dur,
        retransmits: this.totalRetransmits
      };
    } else {
      const jitterMs: number = dur > 0 ? round3(this.jitterAccMs / dur) : 0;
      const lostPct: number = dur > 0 ? round3(this.lostAccPct / dur) : 0;
      s = {
        ok: true,
        sentBps: avgBps,
        receivedBps: avgBps,
        durationSec: dur,
        jitterMs: jitterMs,
        lostPct: lostPct
      };
    }
    if (this.finishCb !== null) {
      this.finishCb(s);
    }
  }

  private emitError(code: number, message: string): void {
    if (this.errorCb !== null) {
      const e: IperfError = { code: code, message: message };
      this.errorCb(e);
    }
  }

  private clearTimer(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  private validate(config: IperfConfig): string {
    if (config.role === 'client') {
      if (config.host === undefined || config.host.trim().length === 0) {
        return 'client 模式必须提供 host';
      }
    }
    if (config.port !== undefined && (config.port < 1 || config.port > 65535)) {
      return 'port 必须在 1~65535 之间';
    }
    if (config.durationSec !== undefined && config.durationSec <= 0) {
      return 'durationSec 必须大于 0';
    }
    if (config.parallel !== undefined && config.parallel < 1) {
      return 'parallel 必须大于等于 1';
    }
    if (config.windowBytes !== undefined && config.windowBytes <= 0) {
      return 'windowBytes 必须大于 0';
    }
    if (config.blockSize !== undefined && config.blockSize <= 0) {
      return 'blockSize 必须大于 0';
    }
    return '';
  }
}

export const mockNative: NativeIperf = new NativeIperfDevStub();
