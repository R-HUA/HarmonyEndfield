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

import { webview } from '@kit.ArkWeb';
import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { FIT_OFFICIAL_MENU } from './OfficialMenu';

const CLOUD_URL = 'https://endfield.hypergryph.com/cloud';
const DOMAIN = 0x1EFD;
const RELEASE_INPUT = 'document.exitPointerLock(); if (navigator.keyboard) navigator.keyboard.unlock();';

/** 挖孔使用实际矩形，避免将整条屏幕边缘都作为不可见区域。 */
interface OfficialMenuLayout {
  width: number;
  height: number;
  left: window.Rect;
  right: window.Rect;
}

/** 为官方弹出页保留独立控制器及 opener 关系。 */
@CustomDialog
struct PopupPage {
  controller?: CustomDialogController;
  webController: webview.WebviewController = new webview.WebviewController();

  build() {
    Column() {
      Row() {
        Blank()
        Button($r('app.string.close_page')).height(44).fontColor('#F4F4F2').backgroundColor('#303436')
          .onClick(() => this.controller?.close())
      }.width('100%').padding(8)
      Web({ src: '', controller: this.webController })
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .layoutWeight(1)
        .width('100%')
        .onWindowExit(() => this.controller?.close())
    }.width('96%').height('90%').backgroundColor('#161819')
  }
}

/** 仅承载官方网页，生命周期恢复不刷新正在进行的会话。 */
@Entry
@Component
struct Index {
  private controller: webview.WebviewController = new webview.WebviewController();
  @State private attached: boolean = false;
  private exitHandler?: FullScreenExitHandler;
  private popup: CustomDialogController | null = null;
  @State private fullscreen: boolean = false;
  @State private failed: boolean = false;
  @State private operationFailed: boolean = false;
  @State private toolsVisible: boolean = false;
  private lastBackAt: number = 0;
  private toolsTimer: number = 0;
  private requestFailures: string[] = [];

  /** 保留请求阶段及错误码，诊断不采集参数或登录凭据。 */
  private recordRequestFailure(kind: string, code: number, request: WebResourceRequest): void {
    const host = request.getRequestUrl().split('/')[2];
    const detail = `${kind}：${host}（${code}）`;
    this.requestFailures.push(detail);
    if (this.requestFailures.length > 8) this.requestFailures.shift();
    hilog.error(DOMAIN, 'EndfieldCloud', '{"event":"request.failed","kind":"%{public}s","host":"%{public}s","code":%{public}d}',
      kind, host, code);
  }

  /** 系统栏仅跟随网页真实全屏事件，不靠隐藏系统栏修正布局。 */
  private async setFullscreen(value: boolean): Promise<void> {
    this.fullscreen = value;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const mainWindow = await window.getLastWindow(context);
      await mainWindow.setWindowSystemBarEnable(value ? [] : ['status', 'navigation']);
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(DOMAIN, 'EndfieldCloud', '{"event":"fullscreen.failed","code":%{public}d}', err.code);
      this.operationFailed = true;
    }
  }

  private releaseInput(): void {
    if (!this.attached) return;
    this.controller.runJavaScript(RELEASE_INPUT, (err) => {
      if (err) {
        hilog.error(DOMAIN, 'EndfieldCloud', '{"event":"input.release_failed","code":%{public}d}', err.code);
        this.operationFailed = true;
      }
    });
  }

  onPageShow(): void {
    if (!this.attached) return;
    try {
      this.controller.onActive();
    } catch (error) {
      hilog.error(DOMAIN, 'EndfieldCloud', '{"event":"web.activate_failed","code":%{public}d}',
        (error as BusinessError).code);
      this.operationFailed = true;
    }
  }

  onPageHide(): void {
    this.hideTools();
    this.popup?.close();
    this.releaseInput();
    if (this.fullscreen) this.exitHandler?.exitFullScreen();
    if (!this.attached) return;
    try {
      this.controller.onInactive();
    } catch (error) {
      hilog.error(DOMAIN, 'EndfieldCloud', '{"event":"web.deactivate_failed","code":%{public}d}',
        (error as BusinessError).code);
      this.operationFailed = true;
    }
  }

  private hideTools(): void {
    clearTimeout(this.toolsTimer);
    this.toolsVisible = false;
    this.lastBackAt = 0;
  }

  aboutToDisappear(): void {
    clearTimeout(this.toolsTimer);
  }

  /** 首次返回保留游戏现场，只有两秒内再次返回才交给系统退出。 */
  onBackPress(): boolean {
    this.releaseInput();
    const now = Date.now();
    if (now - this.lastBackAt < 2000) return false;
    this.lastBackAt = now;
    this.toolsVisible = true;
    clearTimeout(this.toolsTimer);
    this.toolsTimer = setTimeout(() => this.hideTools(), 5000);
    try {
      this.getUIContext().getPromptAction().showToast({
        message: $r('app.string.exit_hint'), duration: 2000
      });
    } catch (error) {
      hilog.error(DOMAIN, 'EndfieldCloud', '{"event":"exit_hint.failed","code":%{public}d}',
        (error as BusinessError).code);
      this.operationFailed = true;
    }
    return true;
  }

  private reload(): void {
    this.getUIContext().showAlertDialog({
      message: $r('app.string.reload_confirm'),
      primaryButton: { value: $r('app.string.cancel'), action: () => {} },
      secondaryButton: { value: $r('app.string.reload'), action: () => {
        this.operationFailed = false;
        this.controller.loadUrl(CLOUD_URL);
      } }
    });
  }

  private openBrowser(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    context.startAbility({ action: 'ohos.want.action.viewData', entities: ['entity.system.browsable'], uri: CLOUD_URL })
      .catch((err: BusinessError) => {
        hilog.error(DOMAIN, 'EndfieldCloud', '{"event":"browser.failed","code":%{public}d}', err.code);
        this.operationFailed = true;
      });
  }

  /** 只调整官网已收起的菜单，展开、点击和拖动仍由官网处理。 */
  private fitOfficialMenu(): void {
    try {
      const mainWindow = window.findWindow(this.getUIContext().getWindowName() as string);
      const rect = mainWindow.getWindowProperties().windowRect;
      const cutout = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_CUTOUT);
      const layout: OfficialMenuLayout = {
        width: rect.width, height: rect.height, left: cutout.leftRect, right: cutout.rightRect
      };
      this.controller.runJavaScript(`${FIT_OFFICIAL_MENU}(${JSON.stringify(layout)})`, (error) => {
        if (error) {
          hilog.error(DOMAIN, 'EndfieldCloud', '{"event":"menu.fit_failed","code":%{public}d}', error.code);
          this.operationFailed = true;
        }
      });
    } catch (error) {
      hilog.error(DOMAIN, 'EndfieldCloud', '{"event":"menu.bounds_failed","code":%{public}d}',
        (error as BusinessError).code);
      this.operationFailed = true;
    }
  }

  /** 网络状态影响官网测速入口；视频数据只展示内核的实际结果。 */
  private showDiagnostics(): void {
    const resources = (this.getUIContext().getHostContext() as common.UIAbilityContext).resourceManager;
    let labels: string[];
    try {
      labels = [
        resources.getStringSync($r('app.string.no_video').id),
        resources.getStringSync($r('app.string.video_size').id),
        resources.getStringSync($r('app.string.total_frames').id),
        resources.getStringSync($r('app.string.dropped_frames').id),
        resources.getStringSync($r('app.string.playback_state').id),
        resources.getStringSync($r('app.string.paused').id),
        resources.getStringSync($r('app.string.playing').id),
        resources.getStringSync($r('app.string.network_state').id),
        resources.getStringSync($r('app.string.online').id),
        resources.getStringSync($r('app.string.offline').id),
        resources.getStringSync($r('app.string.canvas_render').id),
        resources.getStringSync($r('app.string.viewport_size').id),
        resources.getStringSync($r('app.string.screen_size').id),
        resources.getStringSync($r('app.string.visible_size').id),
        resources.getStringSync($r('app.string.safe_area').id)
      ];
    } catch (error) {
      hilog.error(DOMAIN, 'EndfieldCloud', '{"event":"diagnostics.labels_failed","code":%{public}d}',
        (error as BusinessError).code);
      this.operationFailed = true;
      return;
    }
    const script = `(() => {
      const labels = ${JSON.stringify(labels)};
      const video = document.querySelector('#WelinkGameVideo') || document.querySelector('video');
      const network = labels[7] + (navigator.onLine ? labels[8] : labels[9]) + '\\n';
      let media = labels[0];
      if (video instanceof HTMLVideoElement) {
        const quality = video.getVideoPlaybackQuality();
        media = labels[1] + video.videoWidth + ' × ' + video.videoHeight +
          '\\n' + labels[2] + quality.totalVideoFrames + '\\n' + labels[3] + quality.droppedVideoFrames +
          '\\n' + labels[4] + (video.paused ? labels[5] : labels[6]);
      } else if (video instanceof HTMLCanvasElement) {
        media = labels[10] + ' ' + video.width + ' × ' + video.height;
      }
      const vv = window.visualViewport;
      const style = getComputedStyle(document.documentElement);
      const safe = ['top', 'right', 'bottom', 'left'].map(side =>
        style.getPropertyValue('--safe-area-inset-' + side).trim() || '0px');
      const layout = [labels[11] + innerWidth + ' × ' + innerHeight,
        labels[12] + screen.width + ' × ' + screen.height + ' / ' + devicePixelRatio,
        labels[13] + (vv ? Math.round(vv.width) + ' × ' + Math.round(vv.height) : '—'),
        labels[14] + safe.join(' / ')];
      return network + media + '\\n\\n' + layout.join('\\n');
    })()`;
    this.controller.runJavaScriptExt(script, (err, result) => {
      if (err) {
        hilog.error(DOMAIN, 'EndfieldCloud', '{"event":"diagnostics.failed","code":%{public}d}', err.code);
        this.operationFailed = true;
        return;
      }
      const message = (JSON.parse(result.getString()) as string) +
        (this.requestFailures.length ? '\n\n' + this.requestFailures.join('\n') : '');
      this.getUIContext().showAlertDialog({
        title: $r('app.string.page_diagnostics'), message,
        confirm: { value: $r('app.string.confirm'), action: () => {} }
      });
    });
  }

  build() {
    Stack() {
        Web({ src: CLOUD_URL, controller: this.controller })
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .mediaPlayGestureAccess(false)
          .multiWindowAccess(true)
          .allowWindowOpenMethod(true)
          .width('100%').height('100%')
          .onControllerAttached(() => { this.attached = true; })
          .onPageBegin(() => { this.failed = false; this.requestFailures = []; })
          .onPageEnd(() => {
            hilog.info(DOMAIN, 'EndfieldCloud', '{"event":"page.loaded"}');
            this.fitOfficialMenu();
            this.controller.runJavaScript('navigator.onLine', (error, result) => {
              if (error) {
                hilog.error(DOMAIN, 'EndfieldCloud', '{"event":"network.status_failed","code":%{public}d}', error.code);
                this.operationFailed = true;
                return;
              }
              hilog.info(DOMAIN, 'EndfieldCloud', '{"event":"network.status","online":%{public}s}', result);
            });
          })
          .onErrorReceive((event) => {
            this.recordRequestFailure('连接失败', event.error.getErrorCode(), event.request);
            if (event.request.isMainFrame()) {
              this.failed = true;
              hilog.error(DOMAIN, 'EndfieldCloud', '{"event":"page.load_failed","code":%{public}d}',
                event.error.getErrorCode());
            }
          })
          .onHttpErrorReceive((event) => {
            this.recordRequestFailure('服务响应失败', event.response.getResponseCode(), event.request);
            if (event.request.isMainFrame()) {
              this.failed = true;
              hilog.error(DOMAIN, 'EndfieldCloud', '{"event":"page.http_failed","code":%{public}d}',
                event.response.getResponseCode());
            }
          })
          .onConsole((event) => {
            const message = event.message.getMessage();
            const codes = message.match(/net::ERR_[A-Z_]+|Failed to fetch|CORS/g);
            if (codes) {
              const hosts = message.match(/https?:\/\/[a-z0-9.:-]+/gi) || [];
              const detail = '页面错误：' + codes.join('、') + ' ' + hosts.join('、');
              this.requestFailures.push(detail);
              if (this.requestFailures.length > 8) this.requestFailures.shift();
              hilog.error(DOMAIN, 'EndfieldCloud', '{"event":"page.script_failed","detail":"%{public}s"}', detail);
            }
            return false;
          })
          .onRenderExited((event) => {
            this.failed = true;
            hilog.error(DOMAIN, 'EndfieldCloud', '{"event":"renderer.exited","reason":%{public}d}',
              event.renderExitReason);
          })
          .onFullScreenEnter((event) => {
            this.exitHandler = event.handler;
            this.setFullscreen(true);
          })
          .onFullScreenExit(() => {
            this.releaseInput();
            this.exitHandler = undefined;
            this.setFullscreen(false);
          })
          .onWindowNew((event) => {
            this.popup?.close();
            const popupController = new webview.WebviewController();
            event.handler.setWebController(popupController);
            this.popup = new CustomDialogController({
              builder: PopupPage({ webController: popupController }), isModal: true,
              autoCancel: false, customStyle: true
            });
            this.popup.open();
          })
        if (this.failed) {
          Column({ space: 20 }) {
            Text($r('app.string.load_failed')).fontColor('#EFEFED').fontSize(18)
            Button($r('app.string.reload')).height(44).fontColor('#161819').backgroundColor('#DCE36B')
              .onClick(() => this.reload())
            Button($r('app.string.browser')).height(44).fontColor('#F4F4F2').backgroundColor('#303436')
              .onClick(() => this.openBrowser())
          }.width('100%').height('100%').justifyContent(FlexAlign.Center).backgroundColor('#161819')
        }
      if (this.toolsVisible) {
        Button($r('app.string.tools')).fontSize(16).fontColor('#F4F4F2').backgroundColor('#E6303436')
          .height(44).padding({ left: 20, right: 20 })
          .position({ right: 24, top: '50%' }).markAnchor({ x: 0, y: '50%' })
          .bindMenu([
            { value: $r('app.string.reload'), enabled: this.attached, action: () => this.reload() },
            { value: $r('app.string.browser'), action: () => this.openBrowser() },
            { value: $r('app.string.diagnostics'), enabled: this.attached, action: () => this.showDiagnostics() }
          ], {
            placement: Placement.Left,
            onAppear: () => { clearTimeout(this.toolsTimer); this.lastBackAt = 0; },
            onDisappear: () => this.hideTools()
          })
      }
      if (this.operationFailed) {
        Text($r('app.string.operation_failed')).fontColor('#FFE08A').backgroundColor('#CC161819').padding(8)
          .position({ left: '50%', bottom: 24 }).markAnchor({ x: '50%', y: 0 })
      }
    }.width('100%').height('100%').backgroundColor('#161819')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
