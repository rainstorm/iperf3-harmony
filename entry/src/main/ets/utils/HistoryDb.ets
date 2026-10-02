/**
 * 历史测试记录的 RDB 封装。页面不要直接用 relationalStore，统一经本文件读写；
 * 速率/时长格式化在 utils/Format.ets。
 * timestamp 记 epoch 毫秒；peer：client 记 host:port，server 记监听端口。
 */

import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

/** 一条历史记录（读出形态，缺失字段以 0 填充）。 */
export interface HistoryRecord {
  id: number;
  timestamp: number;
  role: string;
  peer: string;
  protocol: string;
  sentBps: number;
  receivedBps: number;
  durationSec: number;
  retransmits: number;
  jitterMs: number;
  lostPct: number;
}

/** 写入形态；TCP 的 retransmits 与 UDP 的 jitterMs/lostPct 视协议二选一。 */
export interface HistoryInput {
  timestamp: number;
  role: string;
  peer: string;
  protocol: string;
  sentBps: number;
  receivedBps: number;
  durationSec: number;
  retransmits?: number;
  jitterMs?: number;
  lostPct?: number;
}

export interface HistoryDb {
  /** 幂等，可重复调用。 */
  init(context: common.UIAbilityContext): Promise<void>;
  /** 返回自增主键 id。 */
  insert(rec: HistoryInput): Promise<number>;
  /** 按时间倒序。 */
  queryAll(): Promise<HistoryRecord[]>;
  queryById(id: number): Promise<HistoryRecord | null>;
  deleteById(id: number): Promise<number>;
  deleteAll(): Promise<number>;
}

const DB_NAME: string = 'iperf3_history.db';
const TABLE: string = 'history';

const CREATE_TABLE_SQL: string =
  'CREATE TABLE IF NOT EXISTS history (' +
  'id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
  'timestamp INTEGER NOT NULL, ' +
  'role TEXT NOT NULL, ' +
  'peer TEXT NOT NULL, ' +
  'protocol TEXT NOT NULL, ' +
  'sentBps REAL NOT NULL, ' +
  'receivedBps REAL NOT NULL, ' +
  'durationSec REAL NOT NULL, ' +
  'retransmits INTEGER NOT NULL DEFAULT 0, ' +
  'jitterMs REAL NOT NULL DEFAULT 0, ' +
  'lostPct REAL NOT NULL DEFAULT 0)';

class HistoryDbImpl implements HistoryDb {
  private store: relationalStore.RdbStore | null = null;
  private initPromise: Promise<void> | null = null;

  init(context: common.UIAbilityContext): Promise<void> {
    // 已成功初始化，直接复用
    if (this.store !== null && this.initPromise !== null) {
      return this.initPromise;
    }
    // 失败时清空缓存，下次调用可重试
    const p: Promise<void> = this.open(context).catch((err: Error) => {
      this.initPromise = null;
      this.store = null;
      throw err;
    });
    this.initPromise = p;
    return p;
  }

  private async open(context: common.UIAbilityContext): Promise<void> {
    const config: relationalStore.StoreConfig = {
      name: DB_NAME,
      securityLevel: relationalStore.SecurityLevel.S1
    };
    const store: relationalStore.RdbStore = await relationalStore.getRdbStore(context, config);
    await store.executeSql(CREATE_TABLE_SQL);
    this.store = store;
  }

  private requireStore(): relationalStore.RdbStore {
    if (this.store === null) {
      throw new Error('HistoryDb 未初始化，请先调用 init(context)');
    }
    return this.store;
  }

  async insert(rec: HistoryInput): Promise<number> {
    const store: relationalStore.RdbStore = this.requireStore();
    const values: relationalStore.ValuesBucket = {
      'timestamp': rec.timestamp,
      'role': rec.role,
      'peer': rec.peer,
      'protocol': rec.protocol,
      'sentBps': rec.sentBps,
      'receivedBps': rec.receivedBps,
      'durationSec': rec.durationSec,
      'retransmits': rec.retransmits !== undefined ? rec.retransmits : 0,
      'jitterMs': rec.jitterMs !== undefined ? rec.jitterMs : 0,
      'lostPct': rec.lostPct !== undefined ? rec.lostPct : 0
    };
    return await store.insert(TABLE, values);
  }

  async queryAll(): Promise<HistoryRecord[]> {
    const store: relationalStore.RdbStore = this.requireStore();
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE);
    predicates.orderByDesc('timestamp');
    const resultSet: relationalStore.ResultSet = await store.query(predicates);
    const list: HistoryRecord[] = [];
    try {
      while (resultSet.goToNextRow()) {
        list.push(this.readRow(resultSet));
      }
    } finally {
      resultSet.close();
    }
    return list;
  }

  async queryById(id: number): Promise<HistoryRecord | null> {
    const store: relationalStore.RdbStore = this.requireStore();
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('id', id);
    const resultSet: relationalStore.ResultSet = await store.query(predicates);
    try {
      if (resultSet.goToFirstRow()) {
        return this.readRow(resultSet);
      }
      return null;
    } finally {
      resultSet.close();
    }
  }

  async deleteById(id: number): Promise<number> {
    const store: relationalStore.RdbStore = this.requireStore();
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE);
    predicates.equalTo('id', id);
    return await store.delete(predicates);
  }

  async deleteAll(): Promise<number> {
    const store: relationalStore.RdbStore = this.requireStore();
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE);
    return await store.delete(predicates);
  }

  private readRow(rs: relationalStore.ResultSet): HistoryRecord {
    const record: HistoryRecord = {
      id: rs.getLong(rs.getColumnIndex('id')),
      timestamp: rs.getLong(rs.getColumnIndex('timestamp')),
      role: rs.getString(rs.getColumnIndex('role')),
      peer: rs.getString(rs.getColumnIndex('peer')),
      protocol: rs.getString(rs.getColumnIndex('protocol')),
      sentBps: rs.getDouble(rs.getColumnIndex('sentBps')),
      receivedBps: rs.getDouble(rs.getColumnIndex('receivedBps')),
      durationSec: rs.getDouble(rs.getColumnIndex('durationSec')),
      retransmits: rs.getLong(rs.getColumnIndex('retransmits')),
      jitterMs: rs.getDouble(rs.getColumnIndex('jitterMs')),
      lostPct: rs.getDouble(rs.getColumnIndex('lostPct'))
    };
    return record;
  }
}

/** 全局单例。 */
export const historyDb: HistoryDb = new HistoryDbImpl();
