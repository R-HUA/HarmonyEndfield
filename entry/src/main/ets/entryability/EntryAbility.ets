/*
 * Copyright (c) 2026 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { UIAbility } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';

const DOMAIN = 0x1EFD;

/** 窗口内核负责网页会话，前后台切换不重新加载页面。 */
export default class EntryAbility extends UIAbility {
  async onWindowStageCreate(windowStage: window.WindowStage): Promise<void> {
    try {
      const mainWindow = windowStage.getMainWindowSync();
      // 网页视口占满窗口，系统栏叠加显示，不占用额外网页高度。
      await mainWindow.setWindowLayoutFullScreen(true);
      await mainWindow.setWindowSystemBarProperties({
        statusBarColor: '#00000000', navigationBarColor: '#00000000',
        statusBarContentColor: '#FFFFFF', navigationBarContentColor: '#FFFFFF'
      });
    } catch (error) {
      const code = (error as BusinessError).code;
      hilog.error(DOMAIN, 'EndfieldCloud', '{"event":"window.layout_failed","code":%{public}d}', code);
      throw new Error(`Window layout failed: ${code}`);
    }
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'EndfieldCloud', '{"event":"window.load_failed","code":%{public}d}', err.code);
        throw new Error(`Window load failed: ${err.code}`);
      }
      hilog.info(DOMAIN, 'EndfieldCloud', '{"event":"window.loaded"}');
    });
  }

  onForeground(): void {
    hilog.info(DOMAIN, 'EndfieldCloud', '{"event":"ability.foreground"}');
  }

  onBackground(): void {
    hilog.info(DOMAIN, 'EndfieldCloud', '{"event":"ability.background"}');
  }
}
