import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';

/**
 * 应用入口 Ability。
 * 首屏加载 pages/Index（客户端测试主页）。
 */
export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        console.error(`EntryAbility loadContent failed, code=${err.code}, msg=${err.message}`);
      }
    });
  }

  onDestroy(): void {
  }
}
