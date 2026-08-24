// ===== 全局轻触反馈 =====
// iOS Safari / PWA 通常不支持 navigator.vibrate，因此在 iOS 上使用很短的
// Web Audio 低频脉冲做触感近似；Capacitor App 则优先调用原生 Haptics。
// 这不是网页端的原生 Taptic Engine 震动，具体效果取决于设备和运行环境。
window.App = window.App || {};

App.Haptics = App.Haptics || (function () {
  var audioContext = null;
  var lastAt = 0;
  var nativeHandler = null;

  function isIOSLike() {
    return /iPhone|iPad|iPod/i.test(navigator.userAgent || '')
      || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  }

  function tryNativeTap() {
    try {
      if (typeof nativeHandler === 'function') {
        nativeHandler();
        return true;
      }

      // 兼容 Capacitor 壳已经注入 Haptics、但网页尚未打包插件模块的场景。
      var capacitor = window.Capacitor;
      var plugins = capacitor && capacitor.Plugins;
      var haptics = plugins && plugins.Haptics;
      var isNative = capacitor && typeof capacitor.isNativePlatform === 'function'
        ? capacitor.isNativePlatform()
        : false;
      if (isNative && haptics && typeof haptics.impact === 'function') {
        haptics.impact({ style: 'LIGHT' });
        return true;
      }
    } catch (error) {}
    return false;
  }

  function tap(options) {
    options = options || {};
    var now = Date.now();
    if (now - lastAt < 45) return;
    lastAt = now;

    if (tryNativeTap()) return;

    try {
      if (typeof navigator.vibrate === 'function') {
        navigator.vibrate(8);
        return;
      }
    } catch (error) {}

    if (!isIOSLike() || options.fallbackAudio === false) return;

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

  return {
    tap: tap,
    setNativeHandler: function (handler) {
      nativeHandler = typeof handler === 'function' ? handler : null;
    }
  };
})();

// 通过事件代理覆盖动态生成的按钮，不需要在每个页面单独绑定。
(function bindGlobalHaptics() {
  var actionSelector = 'button, [role="button"], a, .sticky-tab, .tab, .nav-item';
  var excludedSelector = '.sketch-pad, .doodle-overlay, .doodle-overlay__tool';

  document.addEventListener('pointerdown', function (event) {
    if (event.pointerType === 'mouse') return;
    var target = event.target && event.target.closest
      ? event.target.closest(actionSelector)
      : null;
    if (!target || target.disabled || target.getAttribute('aria-disabled') === 'true') return;
    if (target.closest(excludedSelector)) return;
    var isSpeedAction = !!target.closest('.sc-numpad, .sc-practice');
    // 速算保留既有按键音效；全局触感在原生 App 中调用系统震动，网页端不再额外叠加声音。
    App.Haptics.tap({ fallbackAudio: !isSpeedAction });
  }, { passive: true });
})();
