/**
 * 关于页：应用信息、隐私政策、开源许可、联系方式、备案号。
 * 许可全文见 common/Licenses.ets（由 third_party/iperf/LICENSE 生成）。
 */
import { router } from '@kit.ArkUI';
import { bundleManager } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { FontSize, Gap, WidgetSize } from '../common/DesignTokens';
import { SecondaryButton } from '../common/SharedComponents';
import { IPERF_LICENSE_PARAS } from '../common/Licenses';

/** App/ICP 备案号，例如「粤ICP备2026XXXXXX号-2A」，完成备案后填写。 */
const BEIAN_NUMBER: string = '';
/** 隐私问题联系邮箱；留空时界面仅展示 GitHub 反馈渠道。 */
const CONTACT_EMAIL: string = '';
const DEVELOPER_NAME: string = 'rainstorm';
const REPO_URL: string = 'https://github.com/rainstorm/iperf3-harmony';

interface TextSection {
  title: string;
  paras: string[];
}

const APP_INTRO: string[] = [
  'iperf3 测速是 iperf3 网络性能测试工具的鸿蒙客户端/服务端实现，用于测量设备之间的 TCP/UDP 带宽、抖动与丢包。',
  '支持客户端与服务端模式、TCP/UDP 协议、反向测试、并行流、每秒区间速率与历史记录，测量结果与标准 iperf3 互通。'
];

const PRIVACY_SECTIONS: TextSection[] = [
  {
    title: '一、总则',
    paras: [
      '本应用尊重并保护所有用户的个人信息。本应用为本地网络测试工具，不注册账号、不联网采集任何个人信息，不向开发者或任何第三方上传、共享、转让您的任何数据。'
    ]
  },
  {
    title: '二、我们收集与使用的信息',
    paras: [
      '本应用不收集任何个人信息，包括但不限于：设备标识符、位置、通讯录、短信、相册、麦克风、相机、剪贴板、应用列表等。',
      '本应用不集成广告、统计、推送等任何第三方 SDK，也不含任何埋点。'
    ]
  },
  {
    title: '三、网络权限说明',
    paras: [
      '本应用仅申请一项权限：网络访问（ohos.permission.INTERNET），用于完成您主动发起的带宽测试——连接您指定的测速服务器，或在服务端模式下监听端口等待其他 iperf3 客户端连接。',
      '测试流量仅在您的设备与您指定的对端之间传输，不会流向开发者或第三方服务器。'
    ]
  },
  {
    title: '四、数据存储与删除',
    paras: [
      '测试历史记录（时间、对端地址、速率、时长等）仅保存在您的设备本地数据库中，您可以在「历史记录」页随时删除单条记录或清空全部记录；卸载本应用后相关数据将被一并删除。',
      '除历史记录外，本应用不在设备上保存其他数据，也不向任何服务器备份或同步上述数据。'
    ]
  },
  {
    title: '五、未成年人保护',
    paras: [
      '本应用为网络测试工具，不面向未成年人收集任何信息。'
    ]
  },
  {
    title: '六、本政策的更新',
    paras: [
      '如本政策发生变更，我们将在应用内及商店详情页同步更新并以显著方式提示。'
    ]
  },
  {
    title: '七、联系我们',
    paras: [
      '如您对本隐私政策有任何疑问、意见或投诉，可通过下方「联系方式」一节的渠道与我们联系，我们将在 15 个工作日内受理并处理。'
    ]
  }
];

const LICENSE_INTRO: string[] = [
  '本应用基于开源项目 iperf3（BSD-3-Clause，LBNL 变体）构建，并包含 cJSON(MIT)、net.c(MIT)、queue.h(BSD-3)、units(UIUC)、portable_endian(Public Domain) 等组件，完整许可文本如下。',
  '本应用自身代码同样以 BSD-3-Clause 许可发布，源码见项目仓库。'
];

@Entry
@Component
struct About {
  @State versionName: string = '';
  @State versionCode: number = 0;
  @State bundleName: string = '';

  aboutToAppear(): void {
    try {
      const info = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      this.versionName = info.versionName;
      this.versionCode = info.versionCode;
      this.bundleName = info.name;
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      this.versionName = '';
      this.bundleName = '';
    }
  }

  @Builder
  HeaderBar() {
    Row() {
      SecondaryButton({ label: '返回', onClickHandler: () => {
        router.back();
      } })
      Text('关于')
        .fontSize(FontSize.PageTitle)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
      // 与左侧返回按钮等宽的占位，保证标题真正居中
      Row().width(96)
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
        .textAlign(TextAlign.End)
    }
    .width('100%')
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
  Paragraphs(paras: string[]) {
    ForEach(paras, (p: string) => {
      Text(p)
        .fontSize(FontSize.Caption)
        .lineHeight(20)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        .width('100%')
    }, (p: string) => p)
  }

  @Builder
  AppInfoSection() {
    Column({ space: Gap.TitleToContent }) {
      Row({ space: Gap.FormItem }) {
        Image($r('app.media.startIcon'))
          .width(56)
          .height(56)
          .borderRadius(WidgetSize.CardRadius)
        Column({ space: 2 }) {
          Text('iperf3测速')
            .fontSize(FontSize.CardTitle)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.ohos_id_color_text_primary'))
          Text(this.versionName.length > 0 ? `版本 ${this.versionName}（${this.versionCode}）` : '版本未知')
            .fontSize(FontSize.Caption)
            .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')

      Column({ space: 6 }) {
        this.KvRow('开发者', DEVELOPER_NAME)
        if (this.bundleName.length > 0) {
          this.KvRow('应用包名', this.bundleName)
        }
        if (BEIAN_NUMBER.length > 0) {
          this.KvRow('备案号', BEIAN_NUMBER)
        }
      }
      .width('100%')

      this.Paragraphs(APP_INTRO)
    }
    .width('100%')
    .padding(Gap.CardPad)
    .borderRadius(WidgetSize.CardRadius)
    .backgroundColor($r('sys.color.ohos_id_color_list_card_bg'))
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  PrivacySection() {
    Column({ space: Gap.TitleToContent }) {
      this.CardTitle('隐私政策')
      Text('本政策适用于本应用（iperf3测速）。最后更新：2026 年 10 月。')
        .fontSize(FontSize.Caption)
        .fontColor($r('sys.color.ohos_id_color_text_tertiary'))
        .width('100%')
      ForEach(PRIVACY_SECTIONS, (sec: TextSection) => {
        Column({ space: Gap.LabelToInput }) {
          Text(sec.title)
            .fontSize(FontSize.Label)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.ohos_id_color_text_primary'))
            .width('100%')
          this.Paragraphs(sec.paras)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }, (sec: TextSection) => sec.title)
    }
    .width('100%')
    .padding(Gap.CardPad)
    .borderRadius(WidgetSize.CardRadius)
    .backgroundColor($r('sys.color.ohos_id_color_list_card_bg'))
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  LicenseSection() {
    Column({ space: Gap.TitleToContent }) {
      this.CardTitle('开源许可')
      this.Paragraphs(LICENSE_INTRO)
      Column({ space: 8 }) {
        ForEach(IPERF_LICENSE_PARAS, (p: string) => {
          Text(p)
            .fontSize(FontSize.Caption)
            .lineHeight(20)
            .fontColor($r('sys.color.ohos_id_color_text_tertiary'))
            .width('100%')
        }, (p: string) => p)
      }
      .width('100%')
      .padding(Gap.CardPad)
      .borderRadius(WidgetSize.CardRadius)
      .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(Gap.CardPad)
    .borderRadius(WidgetSize.CardRadius)
    .backgroundColor($r('sys.color.ohos_id_color_list_card_bg'))
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  ContactSection() {
    Column({ space: Gap.TitleToContent }) {
      this.CardTitle('联系方式')
      this.KvRow('项目仓库', REPO_URL)
      if (CONTACT_EMAIL.length > 0) {
        this.KvRow('邮箱', CONTACT_EMAIL)
      }
      Text('问题反馈、功能建议与隐私相关诉求均可在项目仓库提交 Issue。')
        .fontSize(FontSize.Caption)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        .width('100%')
    }
    .width('100%')
    .padding(Gap.CardPad)
    .borderRadius(WidgetSize.CardRadius)
    .backgroundColor($r('sys.color.ohos_id_color_list_card_bg'))
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Column() {
      this.HeaderBar()
      Scroll() {
        Column({ space: Gap.CardGap }) {
          this.AppInfoSection()
          this.PrivacySection()
          this.LicenseSection()
          this.ContactSection()
        }
        .width('100%')
        .padding({ left: Gap.PageH, right: Gap.PageH, top: Gap.HeaderBottom, bottom: Gap.BottomSafe })
        .constraintSize({ minHeight: '100%' })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
  }
}
