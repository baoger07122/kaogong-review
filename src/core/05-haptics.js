// ===== 全局轻触反馈 =====
// iOS Safari / PWA 通常不支持 navigator.vibrate，因此在 iOS 上使用很短的
// Web Audio 低频脉冲做触感近似；这不是原生 Taptic Engine 震动，具体效果取决于
// 设备、系统和声音设置。速算键盘保留自己的触感实现，不在这里重复触发。
window.App = window.App || {};

App.Haptics = App.Haptics || (function () {
  var audioContext = null;
  var lastAt = 0;

  function isIOSLike() {
    return /iPhone|iPad|iPod/i.test(navigator.userAgent || '')
      || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  }

  function tap() {
    var now = Date.now();
    if (now - lastAt < 45) return;
    lastAt = now;

    try {
      if (typeof navigator.vibrate === 'function') {
        navigator.vibrate(8);
        return;
      }
    } catch (error) {}

    if (!isIOSLike()) return;

    try {
      var AudioContextClass = window.AudioContext || window.webkitAudioContext;
      if (!AudioContextClass) return;
      if (!audioContext) audioContext = new AudioContextClass();
      if (audioContext.state === 'suspended' && audioContext.resume) {
        audioContext.resume();
      }

      var oscillator = audioContext.createOscillator();
      var gain = audioContext.createGain();
      var startAt = audioContext.currentTime;
      oscillator.type = 'sine';
      oscillator.frequency.value = 55;
      gain.gain.setValueAtTime(0.06, startAt);
      gain.gain.exponentialRampToValueAtTime(0.0001, startAt + 0.07);
      oscillator.connect(gain);
      gain.connect(audioContext.destination);
      oscillator.start(startAt);
      oscillator.stop(startAt + 0.07);
    } catch (error) {}
  }

  return { tap: tap };
})();

// 通过事件代理覆盖动态生成的按钮，不需要在每个页面单独绑定。
(function bindGlobalHaptics() {
  var actionSelector = 'button, [role="button"], a, .sticky-tab, .tab, .nav-item';
  var excludedSelector = '.sc-numpad, .sc-practice, .sketch-pad, .doodle-overlay';

  document.addEventListener('pointerdown', function (event) {
    if (event.pointerType === 'mouse') return;
    var target = event.target && event.target.closest
      ? event.target.closest(actionSelector)
      : null;
    if (!target || target.disabled || target.getAttribute('aria-disabled') === 'true') return;
    if (target.closest(excludedSelector)) return;
    App.Haptics.tap();
  }, { passive: true });
})();
