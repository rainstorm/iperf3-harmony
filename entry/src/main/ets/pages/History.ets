// 历史记录页：HistoryDb 里的测试记录，点击进详情，侧滑删除/顶部清空。
import { router, promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { historyDb, HistoryRecord } from '../utils/HistoryDb';
import { formatBps, formatDurationSec, formatMs, formatLostPct } from '../utils/Format';
import { FontSize, Gap, WidgetSize } from '../common/DesignTokens';
import { HelpSheet } from '../common/HelpSheet';
import { SecondaryButton } from '../common/SharedComponents';

@Entry
@Component
struct History {
  @State records: HistoryRecord[] = [];
  @State loading: boolean = true;
  @State errorText: string = '';
  // 详情（原始字段承载，避免可空对象在 build 中的判空收窄问题）
  @State detailVisible: boolean = false;
  @State detailId: number = -1;
  @State detailTimestamp: number = 0;
  @State detailRole: string = '';
  @State detailPeer: string = '';
  @State detailProtocol: string = '';
  @State detailSentBps: number = 0;
  @State detailReceivedBps: number = 0;
  @State detailDurationSec: number = 0;
  @State detailRetransmits: number = 0;
  @State detailJitterMs: number = 0;
  @State detailLostPct: number = 0;

  private readonly dateFormatter: Intl.DateTimeFormat =
    new Intl.DateTimeFormat('zh-CN', { year: 'numeric', month: '2-digit', day: '2-digit',
      hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false });

  // 帮助浮窗（半模态，不占主布局）
  private helpController: CustomDialogController = new CustomDialogController({
    builder: HelpSheet({ topic: 'history' }),
    alignment: DialogAlignment.Bottom,
    customStyle: true,
    autoCancel: true
  });

  aboutToAppear(): void {
    this.reload();
  }

  private async reload(): Promise<void> {
    this.loading = true;
    this.errorText = '';
    try {
      const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
      await historyDb.init(ctx);
      this.records = await historyDb.queryAll();
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      this.errorText = `读取历史记录失败：${e.message}`;
      this.records = [];
    } finally {
      this.loading = false;
    }
  }

  private openDetail(rec: HistoryRecord): void {
    this.detailVisible = true;
    this.detailId = rec.id;
    this.detailTimestamp = rec.timestamp;
    this.detailRole = rec.role;
    this.detailPeer = rec.peer;
    this.detailProtocol = rec.protocol;
    this.detailSentBps = rec.sentBps;
    this.detailReceivedBps = rec.receivedBps;
    this.detailDurationSec = rec.durationSec;
    this.detailRetransmits = rec.retransmits;
    this.detailJitterMs = rec.jitterMs;
    this.detailLostPct = rec.lostPct;
  }

  private closeDetail(): void {
    this.detailVisible = false;
  }

  private formatTs(ts: number): string {
    try {
      return this.dateFormatter.format(new Date(ts));
    } catch (e) {
      return new Date(ts).toLocaleString();
    }
  }

  private async deleteRecord(id: number): Promise<void> {
    try {
      await historyDb.deleteById(id);
      if (this.detailId === id) {
        this.closeDetail();
      }
      await this.reload();
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      this.errorText = `删除失败：${e.message}`;
    }
  }

  private async clearAll(): Promise<void> {
    try {
      await historyDb.deleteAll();
      this.closeDetail();
      await this.reload();
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      this.errorText = `清空失败：${e.message}`;
    }
  }

  private confirmClearAll(): void {
    try {
      const pa = this.getUIContext().getPromptAction();
      pa.showDialog({
        title: '清空历史记录',
        message: '将删除全部历史测试记录，是否继续？',
        buttons: [
          { text: '取消', color: $r('sys.color.ohos_id_color_text_secondary') },
          { text: '清空', color: $r('sys.color.ohos_id_color_warning') }
        ]
      }).then((res: promptAction.ShowDialogSuccessResponse) => {
        if (res.index === 1) {
          this.clearAll();
        }
      }).catch(() => {
        // 用户关闭或失败：不做额外处理
      });
    } catch (err) {
      // 兜底：直接执行
      this.clearAll();
    }
  }

  private confirmDelete(rec: HistoryRecord): void {
    try {
      const pa = this.getUIContext().getPromptAction();
      pa.showDialog({
        title: '删除记录',
        message: `删除 ${this.formatTs(rec.timestamp)} 的这条记录？`,
        buttons: [
          { text: '取消', color: $r('sys.color.ohos_id_color_text_secondary') },
          { text: '删除', color: $r('sys.color.ohos_id_color_warning') }
        ]
      }).then((res: promptAction.ShowDialogSuccessResponse) => {
        if (res.index === 1) {
          this.deleteRecord(rec.id);
        }
      }).catch(() => {
        // 用户关闭或失败：不做额外处理
      });
    } catch (err) {
      this.deleteRecord(rec.id);
    }
  }

  @Builder
  HeaderBar() {
    Row() {
      SecondaryButton({ label: '返回', onClickHandler: () => {
        router.back();
      } })
      Text('历史记录')
        .fontSize(FontSize.PageTitle)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
      Row({ space: 12 }) {
        SymbolGlyph($r('sys.symbol.questionmark_circle'))
          .fontSize(WidgetSize.HelpIcon)
          .fontColor([$r('sys.color.ohos_id_color_text_secondary')])
          .onClick(() => { this.helpController.open(); })
        Text('清空')
          .fontSize(FontSize.Label)
          .fontColor(this.records.length > 0 ?
            $r('sys.color.ohos_id_color_warning') : $r('sys.color.ohos_id_color_text_tertiary'))
          .onClick(() => {
            if (this.records.length > 0) {
              this.confirmClearAll();
            }
          })
      }
      .width(96)
      .justifyContent(FlexAlign.End)
    }
    .width('100%')
    .height(56)
    .padding({ left: 8, right: 8 })
    .backgroundColor($r('sys.color.ohos_id_color_list_card_bg'))
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
  ListItem(rec: HistoryRecord) {
    Column({ space: 6 }) {
      Row() {
        Text(this.formatTs(rec.timestamp))
          .fontSize(FontSize.Caption)
          .fontColor($r('sys.color.ohos_id_color_text_tertiary'))
        Blank()
        Text(`${rec.role === 'server' ? '服务端' : '客户端'} · ${rec.protocol.toUpperCase()}`)
          .fontSize(FontSize.Caption)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
      }
      .width('100%')
      Row() {
        Text(rec.peer)
          .fontSize(FontSize.Body)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(formatBps(rec.receivedBps))
          .fontSize(FontSize.Body)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.ohos_id_color_primary'))
      }
      .width('100%')
      Row({ space: 12 }) {
        Text(`↑ ${formatBps(rec.sentBps)}`)
          .fontSize(FontSize.Caption)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        Text(formatDurationSec(rec.durationSec))
          .fontSize(FontSize.Caption)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        if (rec.protocol === 'tcp') {
          Text(`重传 ${rec.retransmits}`)
            .fontSize(FontSize.Caption)
            .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        } else {
          Text(`${formatMs(rec.jitterMs)} / ${formatLostPct(rec.lostPct)}`)
            .fontSize(FontSize.Caption)
            .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        }
      }
      .width('100%')
    }
    .width('100%')
    .padding(Gap.CardPad)
    .borderRadius(WidgetSize.CardRadius)
    .backgroundColor($r('sys.color.ohos_id_color_list_card_bg'))
    .onClick(() => {
      this.openDetail(rec);
    })
  }

  @Builder
  DetailPanel() {
    Column({ space: 10 }) {
      this.KvRow('时间', this.formatTs(this.detailTimestamp))
      this.KvRow('角色', this.detailRole === 'server' ? '服务端' : '客户端')
      this.KvRow('对端', this.detailPeer)
      this.KvRow('协议', this.detailProtocol.toUpperCase())
      this.KvRow('发送速率', formatBps(this.detailSentBps))
      this.KvRow('接收速率', formatBps(this.detailReceivedBps))
      this.KvRow('时长', formatDurationSec(this.detailDurationSec))
      if (this.detailProtocol === 'tcp') {
        this.KvRow('重传', `${this.detailRetransmits} 次`)
      } else {
        this.KvRow('抖动', formatMs(this.detailJitterMs))
        this.KvRow('丢包', formatLostPct(this.detailLostPct))
      }
      Row({ space: 12 }) {
        Button('删除')
          .type(ButtonType.Normal)
          .layoutWeight(1)
          .backgroundColor(Color.Transparent)
          .fontColor($r('sys.color.ohos_id_color_warning'))
          .onClick(() => {
            this.deleteRecord(this.detailId);
          })
        Button('关闭')
          .type(ButtonType.Normal)
          .layoutWeight(1)
          .backgroundColor($r('sys.color.ohos_id_color_component_normal'))
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
          .onClick(() => {
            this.closeDetail();
          })
      }
      .width('100%')
      .margin({ top: 6 })
    }
    .width('100%')
    .padding(20)
    .borderRadius(16)
    .backgroundColor($r('sys.color.ohos_id_color_list_card_bg'))
  }

  build() {
    Stack() {
      Column() {
        this.HeaderBar()
        if (this.loading) {
          Column({ space: Gap.InputV }) {
            Text('加载中…')
              .fontSize(FontSize.Label)
              .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.errorText.length > 0) {
          Column({ space: Gap.CardGap }) {
            Text(this.errorText)
              .fontSize(FontSize.Label)
              .fontColor($r('sys.color.ohos_id_color_warning'))
            Button('重试')
              .height(WidgetSize.ChipH)
              .onClick(() => {
                this.reload();
              })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.records.length === 0) {
          Column({ space: Gap.InputV }) {
            SymbolGlyph($r('sys.symbol.doc_text_badge_magnifyingglass'))
              .fontSize(48)
              .fontColor([$r('sys.color.ohos_id_color_text_tertiary')])
            Text('暂无历史记录')
              .fontSize(FontSize.CardTitle)
              .fontColor($r('sys.color.ohos_id_color_text_secondary'))
            Text('完成一次测试后，结果会自动保存到这里')
              .fontSize(FontSize.Caption)
              .fontColor($r('sys.color.ohos_id_color_text_tertiary'))
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          List({ space: Gap.CardGap }) {
            ForEach(this.records, (rec: HistoryRecord) => {
              ListItem() {
                this.ListItem(rec)
              }
              .swipeAction({
                end: {
                  builder: () => {
                    this.SwipeDeleteBuilder(rec)
                  }
                }
              })
            }, (rec: HistoryRecord) => `${rec.id}`)
          }
          .layoutWeight(1)
          .width('100%')
          .padding({ left: Gap.PageH, right: Gap.PageH, top: Gap.HeaderBottom, bottom: Gap.BottomSafe })
          .scrollBar(BarState.Auto)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('sys.color.ohos_id_color_sub_background'))

      if (this.detailVisible) {
        Column() {
          Blank()
            .layoutWeight(1)
          this.DetailPanel()
        }
        .width('100%')
        .height('100%')
        .padding(24)
        .backgroundColor($r('app.color.dialog_mask'))
        .onClick(() => {
          this.closeDetail();
        })
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  SwipeDeleteBuilder(rec: HistoryRecord) {
    Row() {
      Button('删除')
        .type(ButtonType.Normal)
        .backgroundColor($r('sys.color.ohos_id_color_warning'))
        .fontColor(Color.White)
        .height('100%')
        .onClick(() => {
          this.confirmDelete(rec);
        })
    }
    .width(84)
    .height('100%')
  }
}
