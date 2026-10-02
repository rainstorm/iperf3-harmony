import { FontSize, Gap, WidgetSize } from './DesignTokens';
import { IntervalResult } from './NativeIperf';
import { formatBps, formatBytes, formatMs, formatLostPct } from '../utils/Format';

/**
 * TCP/UDP 分段选择器，客户端与服务端共用。
 * @Prop 的改动不会回传父组件，所以点击走 onChange，由父组件更新自己的 @State。
 */
@Component
export struct ProtocolChips {
  @Prop protocol: string = 'tcp';
  // 运行中禁止切换。
  @Prop isEnabled: boolean = true;
  onChange: (value: string) => void = () => {};

  @Builder
  private Chip(label: string, value: string) {
    Button(label)
      .type(ButtonType.Normal)
      .fontSize(FontSize.Label)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.protocol === value ? Color.White : $r('sys.color.ohos_id_color_text_primary'))
      .backgroundColor(this.protocol === value ?
        $r('sys.color.ohos_id_color_primary') : $r('sys.color.ohos_id_color_component_normal'))
      .borderRadius(WidgetSize.ChipRadius)
      .height(WidgetSize.ChipH)
      .layoutWeight(1)
      .enabled(this.isEnabled)
      .onClick(() => {
        this.onChange(value);
      })
  }

  build() {
    Row({ space: 8 }) {
      this.Chip('TCP', 'tcp')
      this.Chip('UDP', 'udp')
    }
    .width('100%')
  }
}

/**
 * 次要按钮，配色与未选中的 ProtocolChip 同色系，视觉权重低于主按钮。
 */
@Component
export struct SecondaryButton {
  @Prop label: string = '';
  @Prop isEnabled: boolean = true;
  // true 时撑满宽度：底部导航按钮平分一行用。
  @Prop fill: boolean = false;
  onClickHandler: () => void = () => {};

  build() {
    if (this.fill) {
      Button(this.label)
        .type(ButtonType.Normal)
        .fontSize(FontSize.Label)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
        .backgroundColor($r('sys.color.ohos_id_color_component_normal'))
        .height(WidgetSize.ChipH)
        .borderRadius(WidgetSize.ChipRadius)
        .enabled(this.isEnabled)
        .width('100%')
        .onClick(() => {
          this.onClickHandler();
        })
    } else {
      Button(this.label)
        .type(ButtonType.Normal)
        .fontSize(FontSize.Label)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
        .backgroundColor($r('sys.color.ohos_id_color_component_normal'))
        .height(WidgetSize.ChipH)
        .borderRadius(WidgetSize.ChipRadius)
        .enabled(this.isEnabled)
        .onClick(() => {
          this.onClickHandler();
        })
    }
  }
}

@Component
export struct EmptyState {
  @Prop mainText: string = '';
  @Prop subText: string = '';

  build() {
    Column({ space: Gap.InputV }) {
      SymbolGlyph($r('sys.symbol.doc_text_badge_magnifyingglass'))
        .fontSize(48)
        .fontColor([$r('sys.color.ohos_id_color_text_tertiary')])
      Text(this.mainText)
        .fontSize(FontSize.Label)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
      Text(this.subText)
        .fontSize(FontSize.Caption)
        .fontColor($r('sys.color.ohos_id_color_text_tertiary'))
        .textAlign(TextAlign.Center)
        .width('85%')
    }
    .width('100%')
    .padding({ top: 24, bottom: 24 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}

/**
 * 每秒区间速率列表，客户端 / 服务端共用。
 * 不用内部 List 而是直接平铺在页面滚动流里：嵌套的可滚动列表会先吃掉
 * 外层 Scroll 的滑动手势，页面整体滑动变卡。
 * 只显示最近 limit 个区间，防止长测时页面无限变长。
 */
@Component
export struct IntervalRateList {
  @Prop intervals: IntervalResult[] = [];
  @Prop protocol: string = 'tcp';
  @Prop limit: number = 20;

  private extraText(r: IntervalResult): string {
    if (this.protocol === 'tcp') {
      return `重传 ${r.retransmits !== undefined ? r.retransmits : 0}`;
    }
    const jitter: number = r.jitterMs !== undefined ? r.jitterMs : 0;
    const lost: number = r.lostPct !== undefined ? r.lostPct : 0;
    return `${formatMs(jitter)} / ${formatLostPct(lost)}`;
  }

  build() {
    Column() {
      ForEach(this.intervals.slice(0, this.limit), (r: IntervalResult) => {
        Column() {
          Row() {
            Text(`${r.startSec.toFixed(0)}-${r.endSec.toFixed(0)}s`)
              .fontSize(FontSize.ListRow)
              .fontColor($r('sys.color.ohos_id_color_text_secondary'))
              .width(56)
            Text(formatBps(r.bps))
              .fontSize(FontSize.ListValue)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.ohos_id_color_text_primary'))
              .layoutWeight(1)
            Text(formatBytes(r.bytes))
              .fontSize(FontSize.ListRow)
              .fontColor($r('sys.color.ohos_id_color_text_secondary'))
              .width(72)
            Text(this.extraText(r))
              .fontSize(FontSize.Caption)
              .fontColor($r('sys.color.ohos_id_color_text_tertiary'))
          }
          .width('100%')
          .padding({ top: 6, bottom: 6 })
          Divider()
            .color($r('sys.color.ohos_id_color_list_separator'))
        }
        .width('100%')
      }, (r: IntervalResult) => `${r.intervalId}`)
      if (this.intervals.length > this.limit) {
        Text(`仅显示最近 ${this.limit} 个区间（共 ${this.intervals.length} 个）`)
          .fontSize(FontSize.Caption)
          .fontColor($r('sys.color.ohos_id_color_text_tertiary'))
          .width('100%')
          .padding({ top: 6 })
      }
    }
    .width('100%')
  }
}
