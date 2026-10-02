import { router } from '@kit.ArkUI';
import {
  native,
  IperfConfig,
  IntervalResult,
  SummaryResult,
  IperfError
} from '../common/NativeIperf';
import {
  formatBps,
  formatDurationSec,
  formatMs,
  formatLostPct
} from '../utils/Format';
import { RateChart } from '../common/RateChart';
import { FontSize, Gap, WidgetSize } from '../common/DesignTokens';
import { HelpSheet } from '../common/HelpSheet';
import { ProtocolChips, SecondaryButton, EmptyState, IntervalRateList } from '../common/SharedComponents';

/**
 * iperf3 客户端测速页。native 回调全局仅一份：onPageShow 重新注册覆盖其他页占用的回调，
 * onPageHide 停掉仍在跑的测试，aboutToDisappear 置空防泄露。
 */

type Protocol = 'tcp' | 'udp';

/** 区间列表上限，与 Server.ets 的 MAX_INTERVALS 一致。 */
const MAX_INTERVALS: number = 200;
/** UDP 分块合法范围（字节），libiperf 服务端限制。 */
const UDP_BLOCK_MIN: number = 16;
const UDP_BLOCK_MAX: number = 65507;

@Entry
@Component
struct Index {
  // 表单状态
  @State host: string = '127.0.0.1';
  @State port: string = '5201';
  @State durationSec: string = '10';
  @State parallel: string = '1';
  @State protocol: Protocol = 'tcp';
  @State reverse: boolean = false;
  // 高级选项放半模态弹层，不占主布局
  @State advancedOpen: boolean = false;
  @State windowBytes: string = '';
  @State blockSize: string = '';

  // 运行状态
  @State running: boolean = false;
  @State elapsedSec: number = 0;
  @State currentBps: number = 0;
  @State intervals: IntervalResult[] = [];
  @State statusText: string = '未开始';
  // 汇总用扁平字段，避免可空对象在 build 里判空收窄
  @State hasSummary: boolean = false;
  @State summaryOk: boolean = true;
  @State summaryCanceled: boolean = false;
  @State summarySentBps: number = 0;
  @State summaryReceivedBps: number = 0;
  @State summaryDurationSec: number = 0;
  @State summaryRetransmits: number = 0;
  @State summaryJitterMs: number = 0;
  @State summaryLostPct: number = 0;
  @State summaryError: string = '';

  private elapsedTimer: number = -1;

  // 帮助浮窗（半模态，不占主布局）
  private helpController: CustomDialogController = new CustomDialogController({
    builder: HelpSheet({ topic: 'client' }),
    alignment: DialogAlignment.Bottom,
    customStyle: true,
    autoCancel: true
  });

  aboutToAppear(): void {
    this.registerCallbacks();
  }

  onPageShow(): void {
    // 重新注册，覆盖被 Server 页占用的回调
    this.registerCallbacks();
  }

  onPageHide(): void {
    // 页面不可见时停掉测试，否则后台继续跑且返回后无法停止
    if (this.running) {
      native.stop();
    }
    this.running = false;
    this.stopElapsedTimer();
  }

  aboutToDisappear(): void {
    this.stopElapsedTimer();
    // 置空回调，防止 native 回调已销毁组件
    native.onInterval(() => {});
    native.onFinish(() => {});
    native.onError(() => {});
  }

  private registerCallbacks(): void {
    native.onInterval((r: IntervalResult) => {
      this.currentBps = r.bps;
      // 新 → 旧，截断到上限
      this.intervals = [r, ...this.intervals].slice(0, MAX_INTERVALS);
    });
    native.onFinish((r: SummaryResult) => {
      this.running = false;
      this.stopElapsedTimer();
      // 手动停止时 native 报 ok:false error:'canceled'，按「已停止」而非「测试失败」展示（取消语义同 Server.ets）
      const canceled: boolean = r.error === 'canceled';
      this.summaryCanceled = canceled;
      this.applySummary(r);
      if (r.ok) {
        this.currentBps = r.receivedBps;
      } else if (!canceled) {
        this.currentBps = 0;
      }
      this.statusText = canceled ? '已停止' : (r.ok ? '测试完成' : '测试失败');
    });
    native.onError((e: IperfError) => {
      this.running = false;
      this.stopElapsedTimer();
      this.statusText = '运行出错';
      // Toast 提示，不用中断式弹窗
      this.showToast(`错误码 ${e.code}: ${e.message}`);
    });
  }

  private startElapsedTimer(): void {
    this.stopElapsedTimer();
    this.elapsedSec = 0;
    this.elapsedTimer = setInterval(() => {
      this.elapsedSec += 1;
    }, 1000);
  }

  private stopElapsedTimer(): void {
    if (this.elapsedTimer >= 0) {
      clearInterval(this.elapsedTimer);
      this.elapsedTimer = -1;
    }
  }

  private parseConfig(): IperfConfig | null {
    const host: string = this.host.trim();
    if (host.length === 0) {
      this.showToast('请输入服务器地址');
      return null;
    }
    const port: number = parseInt(this.port, 10);
    if (isNaN(port) || port < 1 || port > 65535) {
      this.showToast('端口必须是 1~65535 的整数');
      return null;
    }
    const durationSec: number = parseInt(this.durationSec, 10);
    if (isNaN(durationSec) || durationSec <= 0) {
      this.showToast('时长必须是大于 0 的整数（秒）');
      return null;
    }
    const parallel: number = parseInt(this.parallel, 10);
    if (isNaN(parallel) || parallel < 1) {
      this.showToast('并行流数必须是大于等于 1 的整数');
      return null;
    }
    const config: IperfConfig = {
      role: 'client',
      host: host,
      port: port,
      durationSec: durationSec,
      parallel: parallel,
      protocol: this.protocol,
      reverse: this.reverse
    };
    // 高级选项
    const wb: string = this.windowBytes.trim();
    if (wb.length > 0) {
      const windowBytes: number = parseInt(wb, 10);
      if (isNaN(windowBytes) || windowBytes <= 0) {
        this.showToast('窗口大小必须是大于 0 的整数（字节）');
        return null;
      }
      config.windowBytes = windowBytes;
    }
    const bs: string = this.blockSize.trim();
    if (bs.length > 0) {
      const blockSize: number = parseInt(bs, 10);
      if (isNaN(blockSize)) {
        this.showToast('分块大小必须是整数（字节）');
        return null;
      }
      // UDP 受 libiperf 服务端 16~65507 字节限制
      if (this.protocol === 'udp') {
        if (blockSize < UDP_BLOCK_MIN || blockSize > UDP_BLOCK_MAX) {
          this.showToast(`UDP 分块须 ${UDP_BLOCK_MIN}~${UDP_BLOCK_MAX} 字节`);
          return null;
        }
      } else if (blockSize <= 0) {
        this.showToast('分块大小必须是大于 0 的整数（字节）');
        return null;
      }
      config.blockSize = blockSize;
    }
    return config;
  }

  private onStart(): void {
    const config: IperfConfig | null = this.parseConfig();
    if (config === null) {
      return;
    }
    this.hasSummary = false;
    this.summaryCanceled = false;
    this.intervals = [];
    this.currentBps = 0;
    this.running = true;
    this.statusText = '运行中';
    this.startElapsedTimer();
    try {
      native.start(config);
    } catch (err) {
      this.running = false;
      this.stopElapsedTimer();
      const errMsg: string = (err as Error).message;
      this.showToast(`启动失败: ${errMsg}`);
    }
  }

  private onStop(): void {
    native.stop();
    // 不置 running = false，等 onFinish 收尾，避免竞态
  }

  private showToast(msg: string): void {
    this.getUIContext().getPromptAction().showToast({ message: msg, duration: 2000 });
  }

  private applySummary(s: SummaryResult): void {
    this.hasSummary = true;
    this.summaryOk = s.ok;
    this.summarySentBps = s.sentBps;
    this.summaryReceivedBps = s.receivedBps;
    this.summaryDurationSec = s.durationSec;
    this.summaryRetransmits = s.retransmits !== undefined ? s.retransmits : 0;
    this.summaryJitterMs = s.jitterMs !== undefined ? s.jitterMs : 0;
    this.summaryLostPct = s.lostPct !== undefined ? s.lostPct : 0;
    this.summaryError = s.error !== undefined ? s.error : '';
  }

  /** intervals 是新 → 旧，折线图需要旧 → 新序列。 */
  private chartValues(): number[] {
    const vals: number[] = [];
    for (let i: number = this.intervals.length - 1; i >= 0; i--) {
      vals.push(this.intervals[i].bps);
    }
    return vals;
  }

  @Builder
  ConfigSection() {
    Column({ space: Gap.FormItem }) {
      Text('连接配置')
        .fontSize(FontSize.CardTitle)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
        .width('100%')
      Row() {
        Text('服务器')
          .fontSize(FontSize.Label)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          .width(72)
        TextInput({ text: this.host, placeholder: 'IP 或域名' })
          .fontSize(FontSize.Body)
          .height(WidgetSize.InputH)
          .layoutWeight(1)
          .enabled(!this.running)
          .onChange((v: string) => { this.host = v; })
      }
      .width('100%')

      Row() {
        Text('端口')
          .fontSize(FontSize.Label)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          .width(72)
        TextInput({ text: this.port })
          .fontSize(FontSize.Body)
          .height(WidgetSize.InputH)
          .type(InputType.Number)
          .enabled(!this.running)
          .layoutWeight(1)
          .onChange((v: string) => { this.port = v; })
      }
      .width('100%')

      Row() {
        Text('时长(秒)')
          .fontSize(FontSize.Label)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          .width(72)
        TextInput({ text: this.durationSec })
          .fontSize(FontSize.Body)
          .height(WidgetSize.InputH)
          .type(InputType.Number)
          .enabled(!this.running)
          .layoutWeight(1)
          .onChange((v: string) => { this.durationSec = v; })
      }
      .width('100%')

      Row() {
        Text('并行流')
          .fontSize(FontSize.Label)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          .width(72)
        TextInput({ text: this.parallel })
          .fontSize(FontSize.Body)
          .height(WidgetSize.InputH)
          .type(InputType.Number)
          .enabled(!this.running)
          .layoutWeight(1)
          .onChange((v: string) => { this.parallel = v; })
      }
      .width('100%')

      Row() {
        Text('协议')
          .fontSize(FontSize.Label)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          .width(72)
        ProtocolChips({ protocol: this.protocol, isEnabled: !this.running, onChange: (v: string) => { this.protocol = v === 'udp' ? 'udp' : 'tcp'; } })
          .layoutWeight(1)
      }
      .width('100%')

      Row() {
        Text('反向模式')
          .fontSize(FontSize.Label)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          .width(72)
        Toggle({ type: ToggleType.Switch, isOn: this.reverse })
          .enabled(!this.running)
          .onChange((v: boolean) => { this.reverse = v; })
        Blank()
      }
      .width('100%')
    }
    .width('100%')
    .padding(Gap.CardPad)
    .backgroundColor($r('sys.color.ohos_id_color_list_card_bg'))
    .borderRadius(WidgetSize.CardRadius)
  }

  // bindSheet 的弹层内容
  @Builder
  AdvancedSheet() {
    Column({ space: Gap.CardGap }) {
      Text('高级选项')
        .fontSize(FontSize.CardTitle)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
        .width('100%')
      Row({ space: Gap.InputV }) {
        Text('窗口(B)').fontSize(FontSize.Label).fontColor($r('sys.color.ohos_id_color_text_secondary')).width(72)
        TextInput({ text: this.windowBytes, placeholder: '留空默认' })
          .fontSize(FontSize.Body)
          .height(WidgetSize.InputH)
          .layoutWeight(1)
          .type(InputType.Number)
          .enabled(!this.running)
          .onChange((v: string) => { this.windowBytes = v; })
      }
      .width('100%')
      Row({ space: Gap.InputV }) {
        Text('分块(B)').fontSize(FontSize.Label).fontColor($r('sys.color.ohos_id_color_text_secondary')).width(72)
        TextInput({ text: this.blockSize, placeholder: '留空默认' })
          .fontSize(FontSize.Body)
          .height(WidgetSize.InputH)
          .layoutWeight(1)
          .type(InputType.Number)
          .enabled(!this.running)
          .onChange((v: string) => { this.blockSize = v; })
      }
      .width('100%')
      Text(this.protocol === 'udp'
        ? `UDP 分块建议 ${UDP_BLOCK_MIN}~${UDP_BLOCK_MAX} 字节；留空默认 1460B`
        : 'TCP 窗口/分块留空由系统自动协商（分块默认 128KB）')
        .fontSize(FontSize.Caption)
        .fontColor($r('sys.color.ohos_id_color_text_tertiary'))
        .width('100%')
    }
    .width('100%')
    .padding(Gap.CardPad)
    .alignItems(HorizontalAlign.Start)
  }

  private statusColor(): ResourceColor {
    if (this.statusText === '运行出错' || this.statusText === '测试失败') {
      return $r('sys.color.ohos_id_color_warning');
    }
    if (this.running) {
      return $r('sys.color.ohos_id_color_primary');
    }
    return $r('sys.color.ohos_id_color_text_tertiary');
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

  @Builder
  StatusSection() {
    Column({ space: Gap.FormItem }) {
      Text('测试状态')
        .fontSize(FontSize.CardTitle)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
        .width('100%')
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
      // 带参数的 @Builder 按值传参不随状态刷新，实时数据必须内联，不能用 KvRow
      Row() {
        Text('已用时间')
          .fontSize(FontSize.Label)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        Blank()
        Text(formatDurationSec(this.elapsedSec))
          .fontSize(FontSize.Label)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
      }
      .width('100%')
      Row() {
        Text('区间数')
          .fontSize(FontSize.Label)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        Blank()
        Text(`${this.intervals.length}`)
          .fontSize(FontSize.Label)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
      }
      .width('100%')
      Row() {
        Text('服务器')
          .fontSize(FontSize.Label)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        Blank()
        Text(`${this.host}:${this.port}`)
          .fontSize(FontSize.Label)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
      }
      .width('100%')
    }
    .width('100%')
    .padding(Gap.CardPad)
    .borderRadius(WidgetSize.CardRadius)
    .backgroundColor($r('sys.color.ohos_id_color_list_card_bg'))
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  RealtimeSection() {
    Column({ space: Gap.TitleToContent }) {
      Text('区间速率')
        .fontSize(FontSize.CardTitle)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
        .width('100%')
      Column({ space: Gap.LabelToInput }) {
        Text('当前速率')
          .fontSize(FontSize.Label)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        Text(this.running || this.intervals.length > 0 ? formatBps(this.currentBps) : '--')
          .fontSize(FontSize.BigNumber)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.ohos_id_color_primary'))
        if (this.running) {
          Text(`已用 ${formatDurationSec(this.elapsedSec)}`)
            .fontSize(FontSize.Caption)
            .fontColor($r('sys.color.ohos_id_color_text_tertiary'))
        }
      }
      .alignItems(HorizontalAlign.Center)
      .width('100%')
      .padding({ top: Gap.InputV, bottom: Gap.InputV })

      if (this.intervals.length > 0) {
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
      } else {
        EmptyState({ mainText: '尚未开始测试', subText: '设置好参数后，点击底部「开始测试」，每秒速率会显示在这里' })
      }
    }
    .width('100%')
    .padding(Gap.CardPad)
    .backgroundColor($r('sys.color.ohos_id_color_list_card_bg'))
    .borderRadius(WidgetSize.CardRadius)
  }

  @Builder
  SummarySection() {
    if (this.hasSummary) {
      Column({ space: Gap.FormItem }) {
        Text('最近一次测试结果')
          .fontSize(FontSize.CardTitle)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
          .width('100%')
        this.KvRow('状态', this.summaryCanceled ? '已停止' : (this.summaryOk ? '成功' : '失败'))
        this.KvRow('发送速率', formatBps(this.summarySentBps))
        this.KvRow('接收速率', formatBps(this.summaryReceivedBps))
        this.KvRow('时长', formatDurationSec(this.summaryDurationSec))
        if (this.protocol === 'tcp') {
          this.KvRow('重传', `${this.summaryRetransmits} 次`)
        } else {
          this.KvRow('抖动', formatMs(this.summaryJitterMs))
          this.KvRow('丢包', formatLostPct(this.summaryLostPct))
        }
        if (!this.summaryOk && !this.summaryCanceled && this.summaryError.length > 0) {
          this.KvRow('错误', this.summaryError)
        }
      }
      .width('100%')
      .padding(Gap.CardPad)
      .borderRadius(WidgetSize.CardRadius)
      .backgroundColor($r('sys.color.ohos_id_color_list_card_bg'))
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  FooterSection() {
    Row({ space: Gap.CardGap }) {
      Column() {
        SecondaryButton({ label: '服务端模式', isEnabled: !this.running, fill: true, onClickHandler: () => {
          router.pushUrl({ url: 'pages/Server' });
        } })
      }
      .layoutWeight(1)
      Column() {
        SecondaryButton({ label: '历史记录', isEnabled: !this.running, fill: true, onClickHandler: () => {
          router.pushUrl({ url: 'pages/History' });
        } })
      }
      .layoutWeight(1)
    }
    .width('100%')
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        Text('iperf3 客户端测速')
          .fontSize(FontSize.PageTitle)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
        Blank()
        if (this.running) {
          Text('运行中')
            .fontSize(FontSize.Caption)
            .fontColor($r('sys.color.ohos_id_color_primary'))
            .padding({ left: 8, right: 8, top: 2, bottom: 2 })
            .backgroundColor($r('sys.color.ohos_id_color_component_normal'))
            .borderRadius(8)
            .margin({ right: Gap.InputV })
        }
        SymbolGlyph(this.advancedOpen ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
          .fontSize(WidgetSize.HelpIcon)
          .fontColor([$r('sys.color.ohos_id_color_text_secondary')])
          .margin({ right: Gap.InputV })
          .onClick(() => { this.advancedOpen = true; })
        SymbolGlyph($r('sys.symbol.questionmark_circle'))
          .fontSize(WidgetSize.HelpIcon)
          .fontColor([$r('sys.color.ohos_id_color_text_secondary')])
          .onClick(() => { this.helpController.open(); })
      }
      .width('100%')
      .height(56)
      .padding({ left: Gap.PageH, right: Gap.PageH })
      .backgroundColor($r('sys.color.ohos_id_color_list_card_bg'))

      Scroll() {
        Column({ space: Gap.CardGap }) {
          this.ConfigSection()
          this.StatusSection()
          this.RealtimeSection()
          this.SummarySection()
          this.FooterSection()
        }
        .width('100%')
        .padding({ left: Gap.PageH, right: Gap.PageH, top: Gap.HeaderBottom, bottom: Gap.BottomSafe })
        // Scroll 会把不满一屏的内容垂直居中，minHeight 撑满避免标题下大片空白
        .constraintSize({ minHeight: '100%' })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Auto)

      Row() {
        if (!this.running) {
          Button('开始测试')
            .fontSize(FontSize.Body)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
            .width('100%')
            .height(WidgetSize.PrimaryButtonH)
            .borderRadius(WidgetSize.PrimaryButtonRadius)
            .backgroundColor($r('sys.color.ohos_id_color_primary'))
            .onClick(() => { this.onStart(); })
        } else {
          Button('停止测试')
            .fontSize(FontSize.Body)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
            .width('100%')
            .height(WidgetSize.PrimaryButtonH)
            .borderRadius(WidgetSize.PrimaryButtonRadius)
            .backgroundColor($r('sys.color.ohos_id_color_warning'))
            .onClick(() => { this.onStop(); })
        }
      }
      .width('100%')
      .padding({ left: Gap.PageH, right: Gap.PageH, bottom: Gap.BottomSafe, top: Gap.CardGap })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
    // 高级选项半模态弹层
    .bindSheet($$this.advancedOpen, this.AdvancedSheet(), {
      height: SheetSize.MEDIUM,
      dragBar: true,
      showClose: true,
      onDisappear: () => { this.advancedOpen = false; }
    })
  }
}
