/** 仅在用户请求后采样五秒，避免常驻逐帧采集影响串流。 */
export const SAMPLE_PAGE_DIAGNOSTICS = `((labels, id) => {
  const video = document.querySelector('#WelinkGameVideo') || document.querySelector('video');
  const isVideo = video instanceof HTMLVideoElement;
  const before = isVideo ? video.getVideoPlaybackQuality() : null;
  const source = isVideo ? video.srcObject : null;
  const url = isVideo ? video.currentSrc : '';
  const started = performance.now();
  let frameCallback;
  let decodeSeconds = 0;
  let decodeSamples = 0;
  let longTaskMs = 0;
  let observer;
  const onFrame = (now, metadata) => {
    if (typeof metadata.processingDuration === 'number') {
      decodeSeconds += metadata.processingDuration;
      decodeSamples++;
    }
    frameCallback = video.requestVideoFrameCallback(onFrame);
  };
  if (isVideo && typeof video.requestVideoFrameCallback === 'function') {
    frameCallback = video.requestVideoFrameCallback(onFrame);
  }
  if (typeof PerformanceObserver !== 'undefined' &&
      PerformanceObserver.supportedEntryTypes.includes('longtask')) {
    observer = new PerformanceObserver(list => {
      longTaskMs += list.getEntries().reduce((total, entry) => total + entry.duration, 0);
    });
    observer.observe({ entryTypes: ['longtask'] });
  }
  setTimeout(() => {
    if (frameCallback !== undefined) video.cancelVideoFrameCallback(frameCallback);
    if (observer) {
      longTaskMs += observer.takeRecords().reduce((total, entry) => total + entry.duration, 0);
      observer.disconnect();
    }
    const seconds = (performance.now() - started) / 1000;
    const network = labels[7] + (navigator.onLine ? labels[8] : labels[9]);
    let media = labels[0];
    if (isVideo) {
      const quality = video.getVideoPlaybackQuality();
      const frames = quality.totalVideoFrames - before.totalVideoFrames;
      const dropped = quality.droppedVideoFrames - before.droppedVideoFrames;
      const sameVideo = video.isConnected && video.srcObject === source && video.currentSrc === url && frames >= 0 && dropped >= 0;
      media = labels[1] + video.videoWidth + ' × ' + video.videoHeight +
        '\\n' + labels[2] + quality.totalVideoFrames + '\\n' + labels[3] + quality.droppedVideoFrames +
        '\\n' + labels[4] + (video.paused ? labels[5] : labels[6]) + '\\n' +
        (sameVideo ? labels[15] + seconds.toFixed(1) + labels[16] +
          '\\n' + labels[17] + ((frames - dropped) / seconds).toFixed(1) + labels[18] +
          '\\n' + labels[19] + dropped + (frames > 0 ? ' (' + (dropped / frames * 100).toFixed(1) + '%)' : '') +
          '\\n' + labels[20] + (decodeSamples ? (decodeSeconds * 1000 / decodeSamples).toFixed(1) + labels[21] : labels[22]) : labels[23]);
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
    const message = network + '\\n' + media + '\\n' + labels[24] +
      (observer ? longTaskMs.toFixed(0) + labels[21] : labels[22]) + '\\n\\n' + layout.join('\\n');
    console.info('EndfieldDiagnostics:' + JSON.stringify({ id, message }));
  }, 5000);
})`;
