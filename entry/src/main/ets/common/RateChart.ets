// 每秒区间速率的简单折线图（自绘 Path，无图表库依赖）；只做展示，格式化走 utils/Format.ets。
// 坑：Path 的 commands 坐标按 px 解释，而 width/height 属性按 vp，差一个屏幕密度倍率，
// 所以在 onAreaChange 里 vp2px 换算实测尺寸，折线坐标全部按 px 生成。

const CHART_HEIGHT_VP: number = 76;
const CHART_PAD_VP: number = 6;
const STROKE_VP: number = 2;
/** 最多绘制最近 60 个点，避免长测时折线过密。 */
const MAX_POINTS: number = 60;

/** values 为 bps 序列（旧 → 新）。 */
@Component
export struct RateChart {
  @Prop values: number[] = [];
  // px 单位，onAreaChange 实测后才有值。
  @State private pxW: number = 0;
  @State private pxH: number = 0;
  @State private strokePx: number = 0;
  @State private padPx: number = 0;

  // 归一化到画布 px 坐标，输出 M/L 折线 commands。
  private buildCommands(): string {
    const total: number = this.values.length;
    if (total === 0 || this.pxW <= 0 || this.pxH <= 0) {
      return '';
    }
    const pts: number[] = total > MAX_POINTS ? this.values.slice(total - MAX_POINTS) : this.values;
    const count: number = pts.length;
    // 纵轴按数据区间 [min, max] 自适应；固定从 0 起算的话，平稳速率会压成一条直线。
    let minV: number = pts[0];
    let maxV: number = pts[0];
    for (let i: number = 1; i < count; i++) {
      if (pts[i] < minV) {
        minV = pts[i];
      }
      if (pts[i] > maxV) {
        maxV = pts[i];
      }
    }
    const span: number = maxV - minV;
    if (span <= 0) {
      minV = maxV * 0.9;
    } else {
      minV = minV - span * 0.1;
      maxV = maxV + span * 0.1;
    }
    const innerW: number = this.pxW - this.padPx * 2;
    const innerH: number = this.pxH - this.padPx * 2;
    if (count === 1) {
      // 单点画不出折线：以一小段水平线示意当前位置
      const x: number = this.padPx + innerW / 2;
      const y: number = this.padPx + innerH * (1 - this.clampRatio(pts[0], minV, maxV));
      const half: number = this.strokePx * 2;
      return `M${(x - half).toFixed(1)} ${y.toFixed(1)} L${(x + half).toFixed(1)} ${y.toFixed(1)}`;
    }
    let cmds: string = '';
    for (let i: number = 0; i < count; i++) {
      const x: number = this.padPx + innerW * i / (count - 1);
      const y: number = this.padPx + innerH * (1 - this.clampRatio(pts[i], minV, maxV));
      if (i === 0) {
        cmds += `M${x.toFixed(1)} ${y.toFixed(1)}`;
      } else {
        cmds += ` L${x.toFixed(1)} ${y.toFixed(1)}`;
      }
    }
    return cmds;
  }

  private clampRatio(v: number, minV: number, maxV: number): number {
    const span: number = maxV - minV;
    if (span <= 0) {
      return 0.5;
    }
    let ratio: number = (v - minV) / span;
    if (ratio < 0) {
      ratio = 0;
    }
    if (ratio > 1) {
      ratio = 1;
    }
    return ratio;
  }

  private syncSize(widthVp: number, heightVp: number): void {
    if (!(widthVp > 0) || !(heightVp > 0)) {
      return;
    }
    const ui = this.getUIContext();
    this.pxW = ui.vp2px(widthVp);
    this.pxH = ui.vp2px(heightVp);
    this.strokePx = ui.vp2px(STROKE_VP);
    this.padPx = ui.vp2px(CHART_PAD_VP);
  }

  build() {
    Path()
      .width('100%')
      .height(CHART_HEIGHT_VP)
      .commands(this.buildCommands())
      .fillOpacity(0)
      .stroke($r('sys.color.ohos_id_color_primary'))
      .strokeWidth(this.strokePx > 0 ? this.strokePx : STROKE_VP)
      .strokeLineJoin(LineJoinStyle.Round)
      .strokeLineCap(LineCapStyle.Round)
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        this.syncSize(parseFloat(`${newArea.width}`), parseFloat(`${newArea.height}`));
      })
  }
}
