// ===== 启动入口：Notion 移动端编辑器与 Service Worker =====
window.initNotionMobileEditor = function (containerSelector, options) {
  return App.Components.initNotionMobileEditor(containerSelector, options);
};

  
;

    // 版本更新机制：Service Worker 负责缓存策略，页面负责确认线上 index.html 是否已经更新。
    // 仅关闭 iPad 后台不会清除 SW/网页缓存，因此不能只依赖 register() 的默认更新时机。
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

      function reloadToVersion(remoteVersion) {
        if (isReloading) return;
        isReloading = true;
        var hash = window.location.hash || '#home';
        var nextUrl = window.location.pathname + '?appVersion=' + encodeURIComponent(remoteVersion) + hash;
        window.location.replace(nextUrl);
      }

      function checkLatestVersion() {
        var now = Date.now();
        if (now - lastCheckAt < CHECK_INTERVAL) return;
        lastCheckAt = now;

        var url = new URL('/index.html', window.location.origin);
        url.searchParams.set('version_check', String(now));
        fetch(url.href, {
          cache: 'no-store',
          credentials: 'same-origin'
        })
          .then(function (response) {
            if (!response.ok) throw new Error('version check failed: ' + response.status);
            return response.text();
          })
          .then(function (html) {
            var match = html.match(/App\.VERSION\s*=\s*['\"]([^'\"]+)['\"]/);
            var remoteVersion = match && match[1];
            if (remoteVersion && isNewer(remoteVersion, App.VERSION)) {
              console.info('[App.Update] 检测到新版本', App.VERSION, '→', remoteVersion);
              reloadToVersion(remoteVersion);
            }
          })
          .catch(function (error) {
            // 版本检查失败时继续使用当前页面，不影响离线使用。
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
          isReloading = true;
          window.location.reload();
        });

        navigator.serviceWorker.register('sw.js', { updateViaCache: 'none' })
          .then(function (registration) {
            // 明确要求浏览器立即检查 sw.js，而不是等待默认的更新检查周期。
            return registration.update();
          })
          .catch(function (error) {
            console.warn('[App.Update] Service Worker 更新失败:', error);
          })
          .then(checkLatestVersion);
      }

      window.addEventListener('load', registerServiceWorker);
      window.addEventListener('pageshow', checkLatestVersion);
      document.addEventListener('visibilitychange', function () {
        if (document.visibilityState === 'visible') checkLatestVersion();
      });
    })();
  
