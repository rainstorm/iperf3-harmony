/**
 * 设计令牌：字号/间距/组件尺寸集中定义。
 * 页面代码不要散写字号字面量，统一引用这里的常量。
 */

/** 字号（vp）。 */
export class FontSize {
  static readonly PageTitle: number = 20;
  static readonly CardTitle: number = 16;
  static readonly Label: number = 14;
  static readonly Body: number = 16;
  static readonly BigNumber: number = 40;
  static readonly ValueMd: number = 20;
  static readonly Caption: number = 13;
  static readonly ListRow: number = 13;
  static readonly ListValue: number = 14;
}

/** 间距（vp，8pt 基线）。 */
export class Gap {
  static readonly PageH: number = 16;      // 页面左右
  static readonly HeaderTop: number = 16;  // 标题区上沿
  static readonly HeaderBottom: number = 12; // 标题区下沿
  static readonly CardGap: number = 12;    // 卡片间
  static readonly CardPad: number = 16;    // 卡片内边距
  static readonly TitleToContent: number = 12; // 卡片标题 → 内容
  static readonly FormItem: number = 12;   // 表单项间
  static readonly InputV: number = 8;      // 输入框上下
  static readonly LabelToInput: number = 4; // 标签 → 输入框
  static readonly BottomSafe: number = 24; // 底部安全区
}

/** 组件尺寸（vp）。 */
export class WidgetSize {
  static readonly PrimaryButtonH: number = 48; // 底部主按钮（胶囊形，圆角 24）
  static readonly PrimaryButtonRadius: number = 24;
  static readonly InputH: number = 44;         // 输入框（触摸目标）
  static readonly ChipH: number = 36;          // 协议 Chip（圆角 18）
  static readonly ChipRadius: number = 18;
  static readonly CardRadius: number = 12;
  static readonly HelpIcon: number = 20;
}
