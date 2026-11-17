/* Keep the loading animation visible until the intro or its fallback takes over. */
(() => {
  'use strict';
  const engine = { loaded: 0, total: 0 };
  const media = { loaded: 0, total: 0 };
  const introGraceMs = 3000;
  let playIntro, introGraceTimer;
  let mediaDone = false, released = false, failed = false;
  const root = () => document.getElementById('welcome-loading');
  function render() {
    const screen = root();
    if (!screen || screen.dataset.state !== 'loading') return;
    const bar = document.getElementById('welcome-progress');
    const label = document.getElementById('welcome-progress-label');
    const number = document.getElementById('welcome-percentage');
    if (playIntro && mediaDone) {
      bar.value = 100;
      number.textContent = '100%';
      label.textContent = '加载完成';
      screen.dataset.state = 'ready';
      screen.setAttribute('aria-busy', 'false');
      document.getElementById('welcome-caption').hidden = true;
      const button = document.getElementById('welcome-play');
      button.hidden = false;
      button.focus({ preventScroll: true });
      return;
    }
    if ((!engine.total && !playIntro) || (!media.total && !mediaDone)) {
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
  }
  window.EatventureLoading = {
    progress(current, total) {
      if (failed || released) return;
      engine.loaded = Math.max(0, Number(current) || 0);
      engine.total = Math.max(0, Number(total) || 0);
      render();
    },
    ready(startIntro) {
      if (playIntro || failed || released) return;
      playIntro = startIntro;
      engine.loaded = engine.total;
      if (!mediaDone) {
        introGraceTimer = setTimeout(() => {
          window.EatventureOpening.cancelPreload();
          finishMedia();
        }, introGraceMs);
      }
      render();
    },
    release(afterCanvasFrame = false) {
      if (released || failed) return;
      released = true;
      playIntro = null;
      const hide = () => {
        root().hidden = true;
        document.getElementById('welcome-animation').pause();
        const canvas = document.getElementById('canvas');
        if (canvas) {
          canvas.inert = false;
          canvas.focus({ preventScroll: true });
        }
      };
      if (afterCanvasFrame) {
        requestAnimationFrame(() => requestAnimationFrame(hide));
      } else {
        hide();
      }
    },
    fail() {
      if (released || failed) return;
      failed = true;
      clearTimeout(introGraceTimer);
      window.EatventureOpening.cancelPreload();
      const screen = root();
      if (!screen) return;
      screen.dataset.state = 'failed';
      document.getElementById('welcome-animation').pause();
      screen.setAttribute('aria-busy', 'false');
      document.getElementById('welcome-progress-label').textContent = '加载失败，请刷新重试';
      document.getElementById('welcome-percentage').textContent = '!';
      document.getElementById('welcome-progress').hidden = true;
      document.getElementById('welcome-caption').hidden = true;
      document.getElementById('welcome-play').hidden = true;
      document.getElementById('welcome-retry').hidden = false;
    }
  };
  function finishMedia() {
    if (mediaDone) return;
    mediaDone = true;
    media.loaded = media.total;
    clearTimeout(introGraceTimer);
    render();
  }
  function mount() {
    const canvas = document.getElementById('canvas');
    if (canvas) canvas.inert = true;
    const button = document.getElementById('welcome-play');
    button.addEventListener('click', () => {
      if (root().dataset.state !== 'ready') return;
      root().dataset.state = 'starting';
      button.disabled = true;
      // Call through synchronously so the browser can start the sound from this gesture.
      playIntro();
    });
    document.getElementById('welcome-retry').addEventListener('click', () => location.reload());
    window.EatventureOpening.preload((loaded, total) => {
      if (mediaDone) return;
      media.loaded = loaded; media.total = total; render();
    }).finally(finishMedia);
    render();
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', mount, { once: true });
  else mount();
})();
