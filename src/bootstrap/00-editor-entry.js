// ===== 启动入口：Notion 移动端编辑器与 Service Worker =====
window.initNotionMobileEditor = function (containerSelector, options) {
  return App.Components.initNotionMobileEditor(containerSelector, options);
};

  
;

    // 注册 Service Worker：联网优先策略，保证 iPad「添加到主屏幕」后每次打开都拉取最新版本，
    // 根治主屏幕图标一直显示旧版的问题。
    if ('serviceWorker' in navigator) {
      window.addEventListener('load', function () {
        navigator.serviceWorker.register('sw.js').catch(function (err) {
          console.warn('SW 注册失败:', err);
        });
      });
    }
  
