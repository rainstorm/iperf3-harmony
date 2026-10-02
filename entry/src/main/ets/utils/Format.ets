// 速率/字节/时长/百分比格式化，页面统一用这里，别各自实现换算。

/**
 * 格式化比特率。
 * 例：formatBps(950e6) => "950 Mbps"；formatBps(1536) => "1.50 Kbps"
 */
export function formatBps(bps: number): string {
  if (bps < 0) {
    return '-';
  }
  const units: string[] = ['bps', 'Kbps', 'Mbps', 'Gbps', 'Tbps'];
  let value: number = bps;
  let idx: number = 0;
  while (value >= 1000 && idx < units.length - 1) {
    value /= 1000;
    idx += 1;
  }
  if (idx === 0) {
    return `${Math.round(value)} ${units[idx]}`;
  }
  if (value >= 100) {
    return `${value.toFixed(0)} ${units[idx]}`;
  }
  return `${value.toFixed(2)} ${units[idx]}`;
}

/**
 * 格式化字节数。
 * 例：formatBytes(125000000) => "119 MB"
 */
export function formatBytes(bytes: number): string {
  if (bytes < 0) {
    return '-';
  }
  const units: string[] = ['B', 'KB', 'MB', 'GB', 'TB'];
  let value: number = bytes;
  let idx: number = 0;
  while (value >= 1024 && idx < units.length - 1) {
    value /= 1024;
    idx += 1;
  }
  if (idx === 0) {
    return `${Math.round(value)} ${units[idx]}`;
  }
  if (value >= 100) {
    return `${value.toFixed(0)} ${units[idx]}`;
  }
  return `${value.toFixed(2)} ${units[idx]}`;
}

/**
 * 格式化时长（秒）。
 * 例：formatDurationSec(75) => "1分15秒"；formatDurationSec(9.8) => "10秒"
 */
export function formatDurationSec(sec: number): string {
  if (sec < 0) {
    return '-';
  }
  // 一律按整秒显示：原生回调给的秒数带小数（如 9.800522），直接展示会泄露浮点尾数
  const totalSec: number = Math.round(sec);
  if (totalSec < 60) {
    return `${totalSec}秒`;
  }
  const m: number = Math.floor(totalSec / 60);
  const s: number = totalSec % 60;
  return `${m}分${s}秒`;
}

/**
 * 格式化毫秒。
 * 例：formatMs(0.123) => "0.123 ms"
 */
export function formatMs(ms: number): string {
  if (ms < 0) {
    return '-';
  }
  return `${ms.toFixed(3)} ms`;
}

/**
 * 格式化丢包率等百分比（入参为 0~100 的数值）。
 * 例：formatLostPct(0.35) => "0.35%"
 */
export function formatLostPct(pct: number): string {
  if (pct < 0) {
    return '-';
  }
  return `${pct.toFixed(2)}%`;
}
