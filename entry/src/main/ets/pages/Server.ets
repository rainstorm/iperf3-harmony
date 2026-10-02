// Server.ets —— 服务端模式页：配置监听、启停、区间速率与结果摘要展示。
// 自然完成的测试写入历史（utils/HistoryDb）；手动停止不写入，状态记「已停止」。
import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { native, IperfConfig, IntervalResult, SummaryResult, IperfError } from '../common/NativeIperf';
import { formatBps, formatDurationSec, formatMs, formatLostPct } from '../utils/Format';
import { historyDb, HistoryInput } from '../utils/HistoryDb';
import { RateChart } from '../common/RateChart';
import { FontSize, Gap, WidgetSize } from '../common/DesignTokens';
import { HelpSheet } from '../common/HelpSheet';
import { ProtocolChips, SecondaryButton, EmptyState, IntervalRateList } from '../common/SharedComponents';

const DEFAULT_PORT: number = 5201;
const DEFAULT_DURATION_SEC: number = 10;
const MAX_INTERVALS: number = 200;

@Entry
@Component
struct Server {
  // 配置
  @State portText: string = DEFAULT_PORT.toString();
  @State durationText: string = DEFAULT_DURATION_SEC.toString();
  @State protocol: string = 'tcp';
  // 运行状态
  @State running: boolean = false;
  @State elapsedSec: number = 0;
  @State statusText: string = '未启动';
  @State errorText: string = '';
  @State clientConnected: boolean = false;
  @State intervals: IntervalResult[] = [];
  // 摘要拆成扁平字段而非可空对象，避免 build 中判空收窄问题
  @State hasSummary: boolean = false;
  @State summaryOk: boolean = true;
  @State summarySentBps: number = 0;
  @State summaryReceivedBps: number = 0;
  @State summaryDurationSec: number = 0;
  @State summaryRetransmits: number = 0;
  @State summaryJitterMs: number = 0;
  @State summaryLostPct: number = 0;
  @State summaryError: string = '';
  @State summaryCanceled: boolean = false;
  @State savedRecordId: number = -1;

  private tickTimer: number = -1;
  private startTs: number = 0;
  private disposed: boolean = false;
  /** 用户主动点击「停止监听」置位：onFinish 据此区分用户取消与自然完成。 */
  private stopRequested: boolean = false;

  // 帮助浮窗（半模态，不占主布局）
  private helpController: CustomDialogController = new CustomDialogController({
    builder: HelpSheet({ topic: 'server' }),
    alignment: DialogAlignment.Bottom,
    customStyle: true,
    autoCancel: true
  });

  aboutToAppear(): void {
    this.disposed = false;
    // 回调重复注册时后次覆盖前次，每次进入页面重新注册
    native.onInterval((r: IntervalResult) => {
      if (this.disposed) {
        return;
      }
      this.clientConnected = true;
      this.elapsedSec = r.endSec;
      this.intervals.push(r);
      if (this.intervals.length > MAX_INTERVALS) {
        this.intervals.shift();
      }
      this.intervals = this.intervals.slice();
    });
    native.onFinish((s: SummaryResult) => {
      if (this.disposed) {
        return;
      }
      this.running = false;
      this.stopTick();
      // 手动停止时 native 报 ok:false error:'canceled'：归为「已停止」，
      // 不写历史、不算失败，避免 0 速率脏记录。
      const canceled: boolean = s.error === 'canceled' || this.stopRequested;
      this.stopRequested = false;
      if (canceled && this.intervals.length === 0) {
        // 手动停止且没有任何区间数据：不展示结果卡
        this.hasSummary = false;
        this.statusText = '已停止';
        return;
      }
      this.applySummary(s, canceled);
      if (canceled) {
        this.statusText = '已停止';
      } else {
        this.statusText = s.ok ? '测试完成' : '测试失败';
        // 仅自然完成（ok）写入历史；取消与失败不产生 0 速率脏记录
        if (s.ok) {
          this.saveRecord(s);
        }
      }
    });
    native.onError((e: IperfError) => {
      if (this.disposed) {
        return;
      }
      this.errorText = `[${e.code}] ${e.message}`;
      this.running = false;
      this.stopTick();
      this.statusText = this.elapsedSec > 0 ? '运行出错' : '启动失败';
    });
  }

  aboutToDisappear(): void {
    this.disposed = true;
    this.stopTick();
    if (this.running) {
      native.stop();
    }
    this.running = false;
  }

  private applySummary(s: SummaryResult, canceled: boolean): void {
    this.hasSummary = true;
    this.summaryCanceled = canceled;
    this.summaryOk = s.ok;
    this.summarySentBps = s.sentBps;
    this.summaryReceivedBps = s.receivedBps;
    this.summaryDurationSec = s.durationSec;
    this.summaryRetransmits = s.retransmits !== undefined ? s.retransmits : 0;
    this.summaryJitterMs = s.jitterMs !== undefined ? s.jitterMs : 0;
    this.summaryLostPct = s.lostPct !== undefined ? s.lostPct : 0;
    this.summaryError = s.error !== undefined ? s.error : '';
  }

  private async saveRecord(s: SummaryResult): Promise<void> {
    try {
      const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
      await historyDb.init(ctx);
      const input: HistoryInput = {
        timestamp: Date.now(),
        role: 'server',
        // 服务端记录不掌握客户端地址（连接由对端发起），这里记本地监听端口
        peer: `监听端口 ${this.parsePortOrDefault()}`,
        protocol: this.protocol,
        sentBps: s.sentBps,
        receivedBps: s.receivedBps,
        durationSec: s.durationSec,
        retransmits: s.retransmits,
        jitterMs: s.jitterMs,
        lostPct: s.lostPct
      };
      this.savedRecordId = await historyDb.insert(input);
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      this.errorText = `历史记录保存失败：${e.message}`;
    }
  }

  private parsePortOrDefault(): number {
    const v: number = Number.parseInt(this.portText, 10);
    if (Number.isNaN(v) || v < 1 || v > 65535) {
      return DEFAULT_PORT;
    }
    return v;
  }

  private parsePort(): number {
    const v: number = Number.parseInt(this.portText, 10);
    if (Number.isNaN(v) || v < 1 || v > 65535) {
      return -1;
    }
    return v;
  }

  private parseDuration(): number {
    const v: number = Number.parseInt(this.durationText, 10);
    if (Number.isNaN(v) || v <= 0) {
      return -1;
    }
    return v;
  }

  /** 供速率折线图使用：intervals 本身即旧 → 新顺序。 */
  private chartValues(): number[] {
    const vals: number[] = [];
    for (let i: number = 0; i < this.intervals.length; i++) {
      vals.push(this.intervals[i].bps);
    }
    return vals;
  }

  private onStartClick(): void {
    const port: number = this.parsePort();
    if (port < 0) {
      this.errorText = '端口需为 1~65535 的整数';
      return;
    }
    const duration: number = this.parseDuration();
    if (duration < 0) {
      this.errorText = '时长需为正整数秒';
      return;
    }
    this.errorText = '';
    this.intervals = [];
    this.hasSummary = false;
    this.summaryCanceled = false;
    this.savedRecordId = -1;
    this.clientConnected = false;
    this.elapsedSec = 0;
    this.stopRequested = false;
    const config: IperfConfig = {
      role: 'server',
      port: port,
      durationSec: duration,
      protocol: this.protocol === 'udp' ? 'udp' : 'tcp'
    };
    this.running = true;
    this.statusText = '监听中';
    this.startTs = Date.now();
    this.startTick();
    try {
      native.start(config);
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      this.running = false;
      this.stopTick();
      this.statusText = '启动失败';
      this.errorText = `启动异常：${e.message}`;
    }
  }

  private onStopClick(): void {
    // 置位取消标志：onFinish 据此把本次结束归类为「已停止」而非「测试完成/失败」
    this.stopRequested = true;
    try {
      native.stop();
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      this.errorText = `停止异常：${e.message}`;
    }
    this.stopTick();
    if (this.running) {
      this.running = false;
      if (!this.hasSummary) {
        this.statusText = '已停止';
      }
    }
  }

  private startTick(): void {
    this.stopTick();
    this.tickTimer = setInterval(() => {
      if (this.running) {
        this.elapsedSec = Math.floor((Date.now() - this.startTs) / 1000);
      }
    }, 1000);
  }

  private stopTick(): void {
    if (this.tickTimer >= 0) {
      clearInterval(this.tickTimer);
      this.tickTimer = -1;
    }
  }

  private statusColor(): ResourceColor {
    if (this.errorText.length > 0) {
      return $r('sys.color.ohos_id_color_warning');
    }
    if (this.running) {
      return $r('sys.color.ohos_id_color_primary');
    }
    return $r('sys.color.ohos_id_color_text_tertiary');
  }

  @Builder
  HeaderBar() {
    Row() {
      SecondaryButton({ label: '返回', onClickHandler: () => {
        router.back();
      } })
      Text('服务端模式')
        .fontSize(FontSize.PageTitle)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
      SymbolGlyph($r('sys.symbol.questionmark_circle'))
        .fontSize(WidgetSize.HelpIcon)
        .fontColor([$r('sys.color.ohos_id_color_text_secondary')])
        .width(56)
        .onClick(() => { this.helpController.open(); })
    }
    .width('100%')
    .height(56)
    .padding({ left: 8, right: 8 })
    .backgroundColor($r('sys.color.ohos_id_color_list_card_bg'))
  }

  @Builder
  CardTitle(title: string) {
    Text(title)
      .fontSize(FontSize.CardTitle)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('sys.color.ohos_id_color_text_primary'))
      .width('100%')
  }

  @Builder
  KvRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(FontSize.Label)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
      Blank()
      Text(value)
        .fontSize(FontSize.Label)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
    }
    .width('100%')
  }

  build() {
    Column() {
      this.HeaderBar()
      Scroll() {
        Column({ space: Gap.CardGap }) {
          // 监听配置
          Column({ space: Gap.FormItem }) {
            this.CardTitle('监听配置')
            Row() {
              Text('端口')
                .fontSize(FontSize.Label)
                .fontColor($r('sys.color.ohos_id_color_text_secondary'))
                .width(72)
              TextInput({ text: this.portText, placeholder: `${DEFAULT_PORT}` })
                .type(InputType.Number)
                .fontSize(FontSize.Body)
                .height(WidgetSize.InputH)
                .enabled(!this.running)
                .layoutWeight(1)
                .onChange((v: string) => {
                  this.portText = v;
                })
            }
            .width('100%')
            Row() {
              Text('时长(秒)')
                .fontSize(FontSize.Label)
                .fontColor($r('sys.color.ohos_id_color_text_secondary'))
                .width(72)
              TextInput({ text: this.durationText, placeholder: `${DEFAULT_DURATION_SEC}` })
                .type(InputType.Number)
                .fontSize(FontSize.Body)
                .height(WidgetSize.InputH)
                .enabled(!this.running)
                .layoutWeight(1)
                .onChange((v: string) => {
                  this.durationText = v;
                })
            }
            .width('100%')
            Row() {
              Text('协议')
                .fontSize(FontSize.Label)
                .fontColor($r('sys.color.ohos_id_color_text_secondary'))
                .width(72)
              ProtocolChips({ protocol: this.protocol, isEnabled: !this.running, onChange: (v: string) => { this.protocol = v; } })
                .layoutWeight(1)
            }
            .width('100%')
          }
          .width('100%')
          .padding(Gap.CardPad)
          .borderRadius(WidgetSize.CardRadius)
          .backgroundColor($r('sys.color.ohos_id_color_list_card_bg'))
          .alignItems(HorizontalAlign.Start)

          // 监听状态（与客户端页「测试状态」对齐）
          Column({ space: Gap.FormItem }) {
            this.CardTitle('监听状态')
            Row({ space: 8 }) {
              Text('●')
                .fontSize(FontSize.Label)
                .fontColor(this.statusColor())
              Text(this.statusText)
                .fontSize(FontSize.Body)
                .fontColor($r('sys.color.ohos_id_color_text_primary'))
                .layoutWeight(1)
            }
            .width('100%')
            // 实时数据必须内联：带参数的 @Builder 按值传参不随状态刷新，KvRow 会停在初始值。
            Row() {
              Text('已运行')
                .fontSize(FontSize.Label)
                .fontColor($r('sys.color.ohos_id_color_text_secondary'))
              Blank()
              Text(formatDurationSec(this.elapsedSec))
                .fontSize(FontSize.Label)
                .fontColor($r('sys.color.ohos_id_color_text_primary'))
            }
            .width('100%')
            Row() {
              Text('接收区间数')
                .fontSize(FontSize.Label)
                .fontColor($r('sys.color.ohos_id_color_text_secondary'))
              Blank()
              Text(`${this.intervals.length}`)
                .fontSize(FontSize.Label)
                .fontColor($r('sys.color.ohos_id_color_text_primary'))
            }
            .width('100%')
            Row() {
              Text('客户端接入')
                .fontSize(FontSize.Label)
                .fontColor($r('sys.color.ohos_id_color_text_secondary'))
              Blank()
              Text(this.clientConnected ? '是' : (this.running ? '等待中' : '—'))
                .fontSize(FontSize.Label)
                .fontColor($r('sys.color.ohos_id_color_text_primary'))
            }
            .width('100%')
            if (this.errorText.length > 0) {
              Text(this.errorText)
                .fontSize(FontSize.Caption)
                .fontColor($r('sys.color.ohos_id_color_warning'))
                .width('100%')
            }
          }
          .width('100%')
          .padding(Gap.CardPad)
          .borderRadius(WidgetSize.CardRadius)
          .backgroundColor($r('sys.color.ohos_id_color_list_card_bg'))
          .alignItems(HorizontalAlign.Start)

          // 最近一次测试结果摘要
          if (this.hasSummary) {
            Column({ space: Gap.FormItem }) {
              this.CardTitle('最近一次测试结果')
              this.KvRow('状态', this.summaryCanceled ? '已停止' : (this.summaryOk ? '成功' : '失败'))
              // 服务端默认只收不发：发送速率为 0 时不展示该行（反向测试才会有发送速率）
              if (this.summarySentBps > 0) {
                this.KvRow('发送速率', formatBps(this.summarySentBps))
              }
              this.KvRow('接收速率', formatBps(this.summaryReceivedBps))
              this.KvRow('时长', formatDurationSec(this.summaryDurationSec))
              if (this.protocol === 'tcp') {
                this.KvRow('重传', `${this.summaryRetransmits} 次`)
              } else {
                this.KvRow('抖动', formatMs(this.summaryJitterMs))
                this.KvRow('丢包', formatLostPct(this.summaryLostPct))
              }
              if (this.summaryError.length > 0) {
                this.KvRow('错误', this.summaryError)
              }
              if (this.savedRecordId >= 0) {
                this.KvRow('历史记录', `#${this.savedRecordId}`)
              }
            }
            .width('100%')
            .padding(Gap.CardPad)
            .borderRadius(WidgetSize.CardRadius)
            .backgroundColor($r('sys.color.ohos_id_color_list_card_bg'))
            .alignItems(HorizontalAlign.Start)
          }

          // 每秒区间速率（曲线 + 列表）
          Column({ space: Gap.TitleToContent }) {
            this.CardTitle('区间速率')
            if (this.intervals.length === 0) {
              EmptyState({
                mainText: this.running ? '等待客户端数据…' : '暂无区间数据',
                subText: this.running ? '客户端开始传输后，每秒速率会显示在这里' : '启动监听并等待客户端连接后，这里会显示每秒区间速率'
              })
            } else {
              Text('速率曲线')
                .fontSize(FontSize.Label)
                .fontColor($r('sys.color.ohos_id_color_text_secondary'))
                .alignSelf(ItemAlign.Start)
              RateChart({ values: this.chartValues() })
              Text('每秒区间')
                .fontSize(FontSize.Label)
                .fontColor($r('sys.color.ohos_id_color_text_secondary'))
                .alignSelf(ItemAlign.Start)
              IntervalRateList({ intervals: this.intervals, protocol: this.protocol })
            }
          }
          .width('100%')
          .padding(Gap.CardPad)
          .borderRadius(WidgetSize.CardRadius)
          .backgroundColor($r('sys.color.ohos_id_color_list_card_bg'))
          .alignItems(HorizontalAlign.Start)

          Text('服务端模式会持续监听，直到手动停止；完成后结果自动写入历史记录。')
            .fontSize(FontSize.Caption)
            .fontColor($r('sys.color.ohos_id_color_text_tertiary'))
            .width('100%')
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .padding({ left: Gap.PageH, right: Gap.PageH, top: Gap.HeaderBottom, bottom: Gap.BottomSafe })
        // 内容不满一屏时也占满视口高度，避免 Scroll 垂直居中留下空白
        .constraintSize({ minHeight: '100%' })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Auto)

      // 底部主按钮，与客户端页同款
      Row() {
        Button(this.running ? '停止监听' : '启动监听')
          .width('100%')
          .height(WidgetSize.PrimaryButtonH)
          .borderRadius(WidgetSize.PrimaryButtonRadius)
          .fontSize(FontSize.Body)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .backgroundColor(this.running ?
            $r('sys.color.ohos_id_color_warning') : $r('sys.color.ohos_id_color_primary'))
          .onClick(() => {
            if (this.running) {
              this.onStopClick();
            } else {
              this.onStartClick();
            }
          })
      }
      .width('100%')
      .padding({ left: Gap.PageH, right: Gap.PageH, bottom: Gap.BottomSafe, top: Gap.CardGap })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }
}
