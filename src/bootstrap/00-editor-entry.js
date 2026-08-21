// ===== 启动入口：Notion 移动端编辑器与 Service Worker =====
window.initNotionMobileEditor = function (containerSelector, options) {
  return App.Components.initNotionMobileEditor(containerSelector, options);
};

  
;

    // 强制更新机制：Service Worker 负责联网优先，页面负责校验线上 index.html 版本。
    // 检测到新版本后不提供“稍后再说”，直接刷新并保留当前 hash 页面，避免 iPad 后台长期运行旧代码。
    (function () {
      var CHECK_INTERVAL = 60 * 1000;
      var lastCheckAt = 0;
      var isReloading = false;

      function parseVersion(version) {
        return String(version || '0').split('.').map(function (part) {
          var number = parseInt(part, 10);
          return isNaN(number) ? 0 : number;
        });
      }

      function isNewer(remoteVersion, localVersion) {
        var remote = parseVersion(remoteVersion);
        var local = parseVersion(localVersion);
        for (var i = 0; i < 3; i += 1) {
          var remotePart = remote[i] || 0;
          var localPart = local[i] || 0;
          if (remotePart !== localPart) return remotePart > localPart;
        }
        return false;
      }

      function showUpdating(remoteVersion) {
        if (document.getElementById('app-force-update')) return;
        var overlay = document.createElement('div');
        overlay.id = 'app-force-update';
        overlay.style.cssText = 'position:fixed;z-index:2147483647;inset:0;display:flex;align-items:center;justify-content:center;background:rgba(255,255,255,.96);font-family:-apple-system,BlinkMacSystemFont,"PingFang SC",sans-serif;';
        overlay.innerHTML = '<div style="width:min(320px,82vw);padding:28px 24px;border-radius:22px;background:#fff;box-shadow:0 12px 40px rgba(0,0,0,.12);text-align:center;color:#1C1C1E;"><div style="font-size:30px;margin-bottom:12px;">↻</div><div style="font-size:18px;font-weight:650;">正在更新系统</div><div style="margin-top:8px;color:#8E8E93;font-size:13px;line-height:1.6;">检测到新版本 v' + String(remoteVersion || '') + '，请稍候…</div></div>';
        document.body.appendChild(overlay);
      }

      function reloadToVersion(remoteVersion) {
        if (isReloading) return;
        isReloading = true;
        showUpdating(remoteVersion);
        var hash = window.location.hash || '#home';
        var nextUrl = window.location.pathname + '?appVersion=' + encodeURIComponent(remoteVersion) + '&refresh=' + Date.now() + hash;
        window.setTimeout(function () { window.location.replace(nextUrl); }, 180);
      }

      function checkLatestVersion() {
        var now = Date.now();
        if (now - lastCheckAt < CHECK_INTERVAL) return;
        lastCheckAt = now;
        var url = new URL('/index.html', window.location.origin);
        url.searchParams.set('version_check', String(now));
        fetch(url.href, { cache: 'no-store', credentials: 'same-origin' })
          .then(function (response) {
            if (!response.ok) throw new Error('version check failed: ' + response.status);
            return response.text();
          })
          .then(function (html) {
            var match = html.match(/App\.VERSION\s*=\s*['"]([^'"]+)['"]/);
            var remoteVersion = match && match[1];
            if (remoteVersion && isNewer(remoteVersion, App.VERSION)) {
              console.info('[App.Update] 检测到新版本', App.VERSION, '→', remoteVersion);
              reloadToVersion(remoteVersion);
            }
          })
          .catch(function (error) {
            // 检查失败时保持当前页面，离线场景仍可继续使用本地缓存。
            console.debug('[App.Update] 版本检查暂不可用:', error.message);
          });
      }

      function registerServiceWorker() {
        if (!('serviceWorker' in navigator)) {
          checkLatestVersion();
          return;
        }
        navigator.serviceWorker.addEventListener('controllerchange', function () {
          if (isReloading) return;
          reloadToVersion('最新');
        });
        navigator.serviceWorker.register('sw.js', { updateViaCache: 'none' })
          .then(function (registration) { return registration.update(); })
          .catch(function (error) { console.warn('[App.Update] Service Worker 更新失败:', error); })
          .then(checkLatestVersion);
      }

      window.addEventListener('load', registerServiceWorker);
      window.addEventListener('pageshow', checkLatestVersion);
      document.addEventListener('visibilitychange', function () {
        if (document.visibilityState === 'visible') checkLatestVersion();
      });
    })();
  
