/** 官网收起态仍保留整条挖孔边距，仅将该状态贴合可见屏幕边缘。 */
export const FIT_OFFICIAL_MENU = `(layout => {
  let observed;
  const update = () => {
    const button = document.querySelector('button[aria-label="游戏菜单"]');
    if (!button) return;
    const container = button.parentElement;
    if (observed !== container) {
      styleObserver.disconnect();
      observed = container;
      styleObserver.observe(container, { attributes: true, attributeFilter: ['style'] });
    }
    const transform = new DOMMatrixReadOnly(container.style.transform);
    let offset = 0;
    if (transform.m41 !== 0) {
      const left = transform.m41 < 0;
      const side = left ? 'left' : 'right';
      const inset = Number.parseFloat(getComputedStyle(document.documentElement)
        .getPropertyValue('--safe-area-inset-' + side));
      const rect = button.getBoundingClientRect();
      const scaleX = innerWidth / layout.width;
      const scaleY = innerHeight / layout.height;
      const cutout = left ? layout.left : layout.right;
      const overlaps = cutout.width > 0 && rect.bottom > cutout.top * scaleY &&
        rect.top < (cutout.top + cutout.height) * scaleY;
      offset = (left ? -1 : 1) * (inset - (overlaps ? cutout.width * scaleX : 0));
    }
    const translate = offset + 'px';
    if (container.style.translate !== translate) container.style.translate = translate;
  };
  const styleObserver = new MutationObserver(update);
  const pageObserver = new MutationObserver(update);
  pageObserver.observe(document.body, { childList: true, subtree: true });
  window.addEventListener('resize', update);
  update();
})`;
