/* The browser decodes the silent MP4; Godot owns music, state and all buttons. */
(() => {
  'use strict';
  let active = null;
  const api = {
    start(callback) {
      api.stop();
      const canvas = document.getElementById('canvas');
      if (!canvas) { callback('failed'); return; }
      const video = document.createElement('video');
      const session = { video, callback, done: false, lastTime: -1, waiting: 0 };
      active = session;
      video.id = 'eatventure-opening-video';
      video.muted = true;
      video.playsInline = true;
      video.disablePictureInPicture = true;
      video.preload = 'auto';
      video.setAttribute('aria-hidden', 'true');
      Object.assign(video.style, { position: 'fixed', zIndex: '20', objectFit: 'contain', pointerEvents: 'none' });
      const fit = () => {
        const bounds = canvas.getBoundingClientRect();
        const scale = Math.min(bounds.width / 720, bounds.height / 1280);
        Object.assign(video.style, {
          left: `${bounds.left + (bounds.width - 720 * scale) / 2}px`,
          top: `${bounds.top + (bounds.height - 1280 * scale) / 2}px`,
          width: `${720 * scale}px`, height: `${1280 * scale}px`
        });
      };
      const notify = (event) => {
        if (active !== session || session.done) return;
        if (event !== 'started') session.done = true;
        callback(event);
      };
      video.onplaying = () => {
        if (!session.started) { session.started = true; notify('started'); }
      };
      video.onended = () => notify('finished');
      video.onerror = () => notify('failed');
      session.observer = new ResizeObserver(fit);
      session.observer.observe(canvas);
      session.fit = fit;
      window.addEventListener('resize', fit);
      window.addEventListener('scroll', fit, true);
      session.timer = window.setInterval(() => {
        if (document.hidden || session.done) return;
        if (video.currentTime > session.lastTime) {
          session.lastTime = video.currentTime; session.waiting = 0;
        } else if (++session.waiting >= 12) notify('failed');
      }, 1000);
      fit();
      document.body.appendChild(video);
      video.src = new URL('opening.mp4', document.baseURI).href;
      video.play().catch(() => notify('failed'));
    },
    stop() {
      const session = active;
      if (!session) return;
      active = null;
      session.done = true;
      clearInterval(session.timer);
      session.observer.disconnect();
      window.removeEventListener('resize', session.fit);
      window.removeEventListener('scroll', session.fit, true);
      session.video.onplaying = session.video.onended = session.video.onerror = null;
      session.video.pause();
      // Give the engine a rendered frame to replace the video with its final poster.
      requestAnimationFrame(() => requestAnimationFrame(() => {
        session.video.removeAttribute('src');
        session.video.load();
        session.video.remove();
      }));
    }
  };
  window.EatventureOpening = api;
})();
