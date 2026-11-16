/* Animate the supplied GIF before engine startup; mirror the native loading UI. */
(() => {
  'use strict';
  const engine = { loaded: 0, total: 0 };
  const media = { loaded: 0, total: 0 };
  let engineReady = false, mediaDone = false, released = false, failed = false, scheduled = false;
  const root = () => document.getElementById('welcome-loading');
  function render() {
    const screen = root();
    if (!screen || failed || released) return;
    const bar = document.getElementById('welcome-progress');
    const label = document.getElementById('welcome-progress-label');
    const number = document.getElementById('welcome-percentage');
    if ((!engine.total && !engineReady) || (!media.total && !mediaDone)) {
      bar.removeAttribute('value');
      number.textContent = '…';
      label.textContent = '美味正在准备中…';
      return;
    }
    const total = engine.total + media.total;
    const percentage = Math.min(99, Math.floor(100 * (engine.loaded + media.loaded) / Math.max(1, total)));
    bar.value = percentage;
    number.textContent = `${percentage}%`;
    label.textContent = '美味正在准备中…';
    if (!engineReady || !mediaDone || scheduled) return;
    scheduled = true;
    bar.value = 100;
    number.textContent = '100%';
    label.textContent = '加载完成';
    document.getElementById('welcome-caption').textContent = '加载完成，点击播放片头';
    screen.dataset.state = 'ready';
    // Godot's matching welcome and button must have a rendered frame before revealing them.
    requestAnimationFrame(() => requestAnimationFrame(() => {
      if (failed) return;
      released = true;
      screen.hidden = true;
      screen.setAttribute('aria-busy', 'false');
      const canvas = document.getElementById('canvas');
      if (canvas) { canvas.inert = false; canvas.focus({ preventScroll: true }); }
      document.removeEventListener('keydown', blockActivation, true);
      document.removeEventListener('keyup', blockActivation, true);
    }));
  }
  window.EatventureLoading = {
    progress(current, total) {
      if (failed || released) return;
      engine.loaded = Math.max(0, Number(current) || 0);
      engine.total = Math.max(0, Number(total) || 0);
      render();
    },
    ready() { engineReady = true; engine.loaded = engine.total; render(); },
    fail() {
      if (released || failed) return;
      failed = true;
      const screen = root();
      if (!screen) return;
      screen.dataset.state = 'failed';
      screen.setAttribute('aria-busy', 'false');
      document.getElementById('welcome-progress-label').textContent = '加载失败，请刷新重试';
      document.getElementById('welcome-percentage').textContent = '!';
      document.getElementById('welcome-progress').hidden = true;
      document.getElementById('welcome-caption').hidden = true;
      document.getElementById('welcome-retry').hidden = false;
    }
  };
  // An engine-ready canvas must remain noninteractive while the intro is still downloading.
  function blockActivation(event) {
    if (!released && !failed && (event.key === 'Enter' || event.key === ' ')) {
      event.preventDefault(); event.stopImmediatePropagation();
    }
  }
  document.addEventListener('keydown', blockActivation, true);
  document.addEventListener('keyup', blockActivation, true);
  function mount() {
    const canvas = document.getElementById('canvas');
    if (canvas) canvas.inert = true;
    document.getElementById('welcome-retry').addEventListener('click', () => location.reload());
    window.EatventureOpening.preload((loaded, total) => {
      media.loaded = loaded; media.total = total; render();
    }).finally(() => { mediaDone = true; media.loaded = media.total; render(); });
    render();
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', mount, { once: true });
  else mount();
})();
