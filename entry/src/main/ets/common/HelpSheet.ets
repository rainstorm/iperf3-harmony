// HelpSheet.ets —— 使用说明帮助浮窗（半模态，底部弹出，不占主界面布局）。
// 唤出方自建 CustomDialogController：builder: HelpSheet({ topic })，alignment: Bottom，
// customStyle: true，autoCancel: true（点遮罩或下滑关闭）。
import { router } from '@kit.ArkUI';
import { FontSize, Gap, WidgetSize } from './DesignTokens';

export type HelpTopic = 'client' | 'server' | 'history';

interface HelpSectionData {
  title: string;
  lines: string[];
}

const CLIENT_SECTIONS: HelpSectionData[] = [
  {
    title: '基本配置',
    lines: [
      '服务器：填运行 iperf3 -s 的主机 IP 或域名，默认 127.0.0.1 为本机回环',
      '端口：须与服务端监听端口一致，默认 5201',
      '时长：建议 10~60 秒，过短无法稳定测量',
      '并行流：1~128，多流可测聚合带宽上限'
    ]
  },
  {
    title: '协议与方向',
    lines: [
      'TCP：测可靠带宽；UDP：测抖动 / 丢包（UDP 需网络可达，USB 隧道不支持）',
      '反向模式：开 = 服务端发、客户端收，测下行带宽'
    ]
  },
  {
    title: '高级选项',
    lines: [
      '窗口(B)：TCP 滑动窗口字节数，留空 = 系统自动协商',
      '分块(B)：单次读写缓冲，TCP 留空 = 128KB，UDP 留空 = 1460B（建议范围 16~65507 字节）'
    ]
  }
];

const SERVER_SECTIONS: HelpSectionData[] = [
  {
    title: '监听配置',
    lines: [
      '端口：与客户端填写一致，默认 5201',
      '时长：建议 10~60 秒，与客户端保持一致'
    ]
  },
  {
    title: '使用方式',
    lines: [
      '启动后保持本页前台，等待客户端连接',
      '测试自然完成后，结果自动写入历史记录',
      '手动停止 = 取消本次测试，不产生历史记录'
    ]
  }
];

const HISTORY_SECTIONS: HelpSectionData[] = [
  {
    title: '记录说明',
    lines: [
      '每条记录 = 一次完成的测试（服务端自然完成或客户端测试结束）',
      '点击记录可查看详情'
    ]
  },
  {
    title: '删除',
    lines: [
      '左滑单条记录可删除该条',
      '顶部「清空」删除全部记录'
    ]
  }
];

function sectionsOf(topic: HelpTopic): HelpSectionData[] {
  if (topic === 'server') {
    return SERVER_SECTIONS;
  }
  if (topic === 'history') {
    return HISTORY_SECTIONS;
  }
  return CLIENT_SECTIONS;
}

/** 半模态帮助浮窗。 */
@CustomDialog
export struct HelpSheet {
  controller: CustomDialogController;
  topic: HelpTopic = 'client';

  build() {
    Column() {
      // 顶部抓手条
      Row()
        .width(40)
        .height(4)
        .borderRadius(2)
        .backgroundColor($r('sys.color.ohos_id_color_text_tertiary'))
        .margin({ top: 8, bottom: 8 })

      Row() {
        Text('使用说明')
          .fontSize(FontSize.CardTitle)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
        Blank()
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(WidgetSize.HelpIcon)
          .fontColor([$r('sys.color.ohos_id_color_text_secondary')])
          .onClick(() => {
            this.controller.close();
          })
      }
      .width('100%')
      .padding({ left: Gap.CardPad, right: Gap.CardPad, bottom: Gap.TitleToContent })

      Scroll() {
        Column({ space: Gap.CardGap }) {
          ForEach(sectionsOf(this.topic), (section: HelpSectionData) => {
            Column({ space: Gap.InputV }) {
              Text(section.title)
                .fontSize(FontSize.Label)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('sys.color.ohos_id_color_text_primary'))
                .width('100%')
              ForEach(section.lines, (line: string) => {
                Text(line)
                  .fontSize(FontSize.Caption)
                  .fontColor($r('sys.color.ohos_id_color_text_secondary'))
                  .width('100%')
              }, (line: string) => line)
            }
            .width('100%')
            .padding(Gap.CardPad)
            .borderRadius(WidgetSize.CardRadius)
            .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
            .alignItems(HorizontalAlign.Start)
          }, (section: HelpSectionData) => section.title)
        }
        .width('100%')
        .padding({ left: Gap.PageH, right: Gap.PageH, bottom: Gap.BottomSafe })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)

      // 底部入口：应用内查看隐私政策与开源许可（上架审核要求可便捷进入）
      Row() {
        Text('关于与隐私政策')
          .fontSize(FontSize.Label)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
        Blank()
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(WidgetSize.HelpIcon)
          .fontColor([$r('sys.color.ohos_id_color_text_secondary')])
      }
      .width('100%')
      .padding({ left: Gap.CardPad, right: Gap.CardPad, top: Gap.HeaderBottom, bottom: Gap.BottomSafe })
      .onClick(() => {
        this.controller.close();
        router.pushUrl({ url: 'pages/About' });
      })
    }
    .width('100%')
    .height('60%')
    .borderRadius({ topLeft: 16, topRight: 16 })
    .backgroundColor($r('sys.color.ohos_id_color_list_card_bg'))
  }
}
