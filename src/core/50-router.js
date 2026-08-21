// ===== 考公笔试复盘系统 - 路由与初始化 =====
window.App = window.App || {};

App.Pages = App.Pages || {};

App.Router = {
  currentPage: 'home',
  currentParams: {},

  init() {
    window.addEventListener('hashchange', () => this.handleRoute());

    // 首次加载
    if (!location.hash) {
      location.replace('#home');
    } else {
      this.handleRoute();
    }
  },

  async handleRoute() {
    const hash = location.hash.slice(1) || 'home';
    const [base, queryString] = hash.split('?');
    // 新信息架构使用 library；保留旧链接别名，避免收藏的旧错题/笔记入口失效。
    const routeAliases = { 'wrong-question': 'library', 'note': 'library' };
    const pageBase = routeAliases[base] || base;
    const params = {};
    if (queryString) {
      queryString.split('&').forEach(pair => {
        const [k, v] = pair.split('=');
        if (k) params[k] = decodeURIComponent(v || '');
      });
    }

    // 关闭所有标签筛选面板（避免残留监听拦截后续页面点击）
    try {
      document.querySelectorAll('.tag-select').forEach(el => {
        if (el._tsClose) { try { el._tsClose(); } catch (e) {} }
      });
    } catch (e) {}

    // 隐藏所有页面
    document.querySelectorAll('.page').forEach(p => {
      p.style.display = 'none';
      p.classList.remove('active');
    });

    // v8.15.35 统一恢复 body/html 滚动 + 移除 sc-lock（速算做题页会临时锁定；切到任意其他页面时兜底解锁，防残留锁死）
    document.body.classList.remove('sc-lock');
    document.body.style.overflow = '';
    document.documentElement.style.overflow = '';

    // 离开错题本时销毁瀑布流实例（解绑 resize 监听，防内存泄漏）
    if (pageBase !== 'errors' && App.Pages.Errors && App.Pages.Errors._masonryInst) {
      try { App.Pages.Errors._masonryInst.destroy(); } catch (e) {}
      App.Pages.Errors._masonryInst = null;
    }

    // 显示目标页面
    const pageEl = document.getElementById('page-' + pageBase);
    if (pageEl) {
      pageEl.style.display = 'block';
      pageEl.classList.add('active');
    }

    // 无底部导航页面（笔记详情/笔记编辑）：隐藏固定底栏 + 内容底部不预留 nav 空间 + 通知移动端工具栏贴底
    // 先清除所有页面的 nav-hidden，再只给当前页设置（避免残留 class 影响后续切换）
    const navHiddenPages = ['note-detail', 'note-form', 'error-detail', 'error-form'];
    const navHidden = navHiddenPages.indexOf(pageBase) >= 0;
    document.querySelectorAll('.page.nav-hidden').forEach(function (p) { p.classList.remove('nav-hidden'); });
    if (pageEl) pageEl.classList.toggle('nav-hidden', navHidden);
    if (App.Components && App.Components._setNavVisible) App.Components._setNavVisible(!navHidden);

    // 离开表单页时清掉进行中的草稿，确保下次新建必为空白；
    // 但保留「目标即本表单」的情况（如刷新当前页），以支持续编恢复。
    try {
      if (App.Draft && App.Draft.clearForm) {
        ['note', 'error', 'exam'].forEach(function (p) {
      if (pageBase !== p + '-form') App.Draft.clearForm(p);
        });
      }
    } catch (e) {}

    // 更新底部导航高亮
    this.updateNavHighlight(pageBase);

    this.updateNavVisibility(pageBase);

    // 调用页面渲染
    try {
      await this.renderPage(pageBase, params);
    } catch (err) {
      console.error('页面渲染错误:', err);
      App.Components.toast('页面加载失败，请重试', 'error');
    }

    // 滚动到顶部
    window.scrollTo(0, 0);

    this.currentPage = pageBase;
    this.currentParams = params;

    // 更新导航角标
    this.updateNavBadges();
  },

  updateNavHighlight(currentPage) {
    document.querySelectorAll('#bottom-nav .nav-item').forEach(a => {
      a.classList.toggle('active', a.dataset.tab === currentPage);
    });
  },

  // v8.12.19 移除右下角悬浮 FAB（用户决定删除一键添加错题按钮）

  // 无底部导航页面（笔记详情/笔记编辑）：隐藏固定底栏
  updateNavVisibility(currentPage) {
    const nav = document.getElementById('bottom-nav');
    if (!nav) return;
    const hidePages = ['note-detail', 'note-form', 'error-detail', 'error-form'];
    nav.classList.toggle('nav--hidden', hidePages.indexOf(currentPage) >= 0);
  },

  async updateNavBadges() {
    try {
      // 注：错题不再显示红点角标（按需求移除未掌握数量提示）

      const exams = await App.DB.getExams();
      const today = new Date().toISOString().slice(0, 10);
      const todayExams = exams.filter(e => e.examDate === today).length;
      const examBadge = document.querySelector('[data-tab="exams"] .nav-badge');
      if (examBadge) {
        if (todayExams > 0) {
          examBadge.textContent = todayExams;
          examBadge.style.display = 'block';
        } else {
          examBadge.style.display = 'none';
        }
      }
    } catch (e) {
      // 静默处理
    }
  },

  async renderPage(pageName, params) {
    switch (pageName) {
      case 'home':
        if (App.Pages.Home && App.Pages.Home.render) await App.Pages.Home.render(params);
        break;
      case 'errors':
        if (App.Pages.Errors && App.Pages.Errors.render) await App.Pages.Errors.render(params);
        break;
      case 'notes':
        if (App.Pages.Notes && App.Pages.Notes.render) await App.Pages.Notes.render(params);
        break;
      case 'library':
        if (App.Pages.Library && App.Pages.Library.render) await App.Pages.Library.render(params);
        break;
      case 'review':
        if (App.Pages.Review && App.Pages.Review.render) await App.Pages.Review.render(params);
        break;
      case 'exams':
        if (App.Pages.Exams && App.Pages.Exams.render) await App.Pages.Exams.render(params);
        break;
      case 'kpmanage':
        if (App.Pages.KpManage && App.Pages.KpManage.render) await App.Pages.KpManage.render(params);
        break;
      case 'study-stats':
        if (App.Pages.StudyStats && App.Pages.StudyStats.render) await App.Pages.StudyStats.render(params);
        break;
      case 'stickies':
        if (App.Pages.Stickies && App.Pages.Stickies.render) await App.Pages.Stickies.render(params);
        break;
      case 'workspace':
        if (App.Pages.Workspace && App.Pages.Workspace.render) await App.Pages.Workspace.render(params);
        break;
      case 'error-detail':
        if (App.Pages.Errors && App.Pages.Errors.renderDetail) await App.Pages.Errors.renderDetail(params);
        break;
      case 'error-form':
        if (App.Pages.Errors && App.Pages.Errors.renderForm) App.Pages.Errors.renderForm(params);
        break;
      case 'note-detail':
        if (App.Pages.Notes && App.Pages.Notes.renderDetail) await App.Pages.Notes.renderDetail(params);
        break;
      case 'note-form':
        if (App.Pages.Notes && App.Pages.Notes.renderForm) App.Pages.Notes.renderForm(params);
        break;
      case 'note-type-manage':
        if (App.Pages.Notes && App.Pages.Notes.renderTypeManage) App.Pages.Notes.renderTypeManage(params);
        break;
      case 'note-type-form':
        if (App.Pages.Notes && App.Pages.Notes.renderTypeForm) App.Pages.Notes.renderTypeForm(params);
        break;
      case 'exam-detail':
        if (App.Pages.Exams && App.Pages.Exams.renderDetail) await App.Pages.Exams.renderDetail(params);
        break;
      case 'exam-form':
        if (App.Pages.Exams && App.Pages.Exams.renderForm) App.Pages.Exams.renderForm(params);
        break;
      case 'settings':
        if (App.Pages.Settings && App.Pages.Settings.render) App.Pages.Settings.render(params);
        break;
      case 'worddb':
        if (App.Pages.WordDB && App.Pages.WordDB.render) await App.Pages.WordDB.render(params);
        break;
      case 'speed-calc':
        if (App.Pages.SpeedCalc && App.Pages.SpeedCalc.render) await App.Pages.SpeedCalc.render(params);
        break;
    }
  },

  navigate(route) {
    location.hash = route;
  },
  // 内部链接（note:// / error://）点击跳转到详情页
  initInternalLinks() {
    document.addEventListener('click', (e) => {
      const a = e.target.closest && e.target.closest('a[href^="note://"], a[href^="error://"]');
      if (!a) return;
      e.preventDefault();
      const href = a.getAttribute('href') || '';
      const m = href.match(/^(note|error):\/\/([\s\S]+)$/);
      if (!m) return;
      const page = m[1] === 'note' ? 'note-detail' : 'error-detail';
      App.Router.navigate(page + '?id=' + encodeURIComponent(m[2]));
    });
  },

  back() {
    window.history.back();
  }
};

// ===== 应用初始化 =====
document.addEventListener('DOMContentLoaded', async () => {
  // 云同步后端只在提供 /api 的同源端口（沙箱 3000）可用。
  // 若经其它网关端口（如 8000 的静态服务）打开，探针会失败，此时自动重定向到 3000。
  // 重定向只需带 x-cs-sandbox-port=3000，浏览器会自动附带 x-cs-sandbox-id cookie，无需硬编码。
  try {
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), 4000);
    const probe = await fetch('/api/health', { signal: ctrl.signal });
    clearTimeout(t);
    const txt = await probe.text();
    const isCloudPort = probe.ok && txt.indexOf('"ok"') !== -1;
    // 静态托管下 /api/health 会兜底返回 index.html（HTTP 200 但为 HTML，不含 "ok"）。
    // 此时绝不能重定向，否则会无限跳转导致页面打不开。
    // 仅当确认当前源提供真实 API（非 HTML 兜底）但不在云端端口时才跳转（沙箱网关场景）。
    const isHtmlFallback = txt.indexOf('<html') !== -1 || txt.indexOf('<!DOCTYPE') !== -1;
    if (!isCloudPort && !isHtmlFallback) {
      const u = new URL(location.href);
      u.searchParams.set('x-cs-sandbox-port', '3000');
      location.replace(u.toString());
      return;
    }
  } catch (e) {
    // 探针异常（网络/超时）：保守不重定向，避免离线时误跳转；云同步将在网络恢复后由登录流程检测。
  }

  // 初始化主题
  App.Utils.Theme.init();

  // ===== iPad 分屏检测（全局级，启动即执行，不依赖编辑器初始化） =====
  // 分屏/Stage Manager 下 iPad 系统「三点」多任务条位于左上角，会压住页面返回按钮。
  // 检测到分屏时给 body 加 ipad-split class → 返回按钮 margin-left 右移避开（见 styles.css）。
  // 之前该检测放在移动端工具栏构建内（惰性），详情页/编辑页无编辑器时不执行 → 分屏下返回键被遮挡。
  // 判定（方向感知，v8.15.23）：横屏分屏沿「长边」方向压缩、最多占到 ~75%（25/75 档），
  // 横屏全屏 w≈长边，故用「w < 长边×0.92」判定横屏分屏——同时覆盖 50% 与 75%(2/3) 分屏、全屏不误判；
  // 竖屏全屏 w≈短边、上下分屏宽度不变，沿用「w < 短边-80」兜底（Slide Over/窄窗口）。
  const _detectIpadSplitGlobal = () => {
    try {
      const isIpad = /iPad/.test(navigator.userAgent) ||
        (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
      if (!isIpad) { document.body.classList.remove('ipad-split'); return; }
      const w = window.innerWidth;
      const h = window.innerHeight;
      const sw = (screen && screen.width) || 0;
      const sh = (screen && screen.height) || 0;
      let isSplit = false;
      if (sw > 0 && sh > 0) {
        const longEdge = Math.max(sw, sh);
        const shortEdge = Math.min(sw, sh);
        if (w > h) {
          isSplit = w < longEdge * 0.92;
        } else {
          isSplit = w < shortEdge - 80;
        }
      } else {
        isSplit = w < 1024;   // screen 不可用时兜底
      }
      if (isSplit) document.body.classList.add('ipad-split');
      else document.body.classList.remove('ipad-split');
    } catch (e) {}
  };
  _detectIpadSplitGlobal();
  let _splitGlobalTimer = null;
  window.addEventListener('resize', () => {
    clearTimeout(_splitGlobalTimer);
    _splitGlobalTimer = setTimeout(_detectIpadSplitGlobal, 100);
  }, { passive: true });
  window.addEventListener('orientationchange', () => setTimeout(_detectIpadSplitGlobal, 300), { passive: true });

  // 初始化数据库。iPad PWA 从后台返回时 IndexedDB 偶尔会无限等待；超时后继续渲染首页，
  // 避免整个应用只剩静态导航。数据库稍后恢复时会自动刷新当前路由。
  let dbInitTask = null;
  let dbInitDelayed = false;
  try {
    dbInitTask = App.DB.init();
    await Promise.race([
      dbInitTask,
      new Promise((_, reject) => setTimeout(() => reject(new Error('数据库初始化超时')), 6000))
    ]);
  } catch (e) {
    dbInitDelayed = true;
    console.error('数据库初始化失败:', e);
    if (App.Components && App.Components.toast) {
      App.Components.toast('数据加载较慢，页面已恢复；请稍候或重新打开', 'error');
    }
  }

  // 加载自定义标签库（考点 / 错因）
  try {
    if (App.Tags && App.Tags.init) await App.Tags.init();
  } catch (e) {
    console.error('标签库加载失败:', e);
  }

  // 初始化云端同步（挂载 DB 钩子 + 校验登录态）
  // 上传为自动（每次保存经 wrapDB 钩子推送）；下载为手动（设置页点「立即同步」）。
  try {
    if (App.Cloud) {
      App.Cloud.init();
      App.Cloud.wrapDB();
      App.Cloud.validate();
    }
  } catch (e) {
    console.error('云同步初始化失败:', e);
  }

  // 初始化内部链接点击监听
  App.Router.initInternalLinks();

  // 初始化路由
  App.Router.init();

  // 超时不代表数据库一定失败：若 iPad 随后释放了旧连接，重新渲染即可恢复完整数据。
  if (dbInitDelayed && dbInitTask) {
    dbInitTask.then(() => {
      try { if (App.Router && App.Router.handleRoute) App.Router.handleRoute(); } catch (e) {}
    }).catch(() => {});
  }
});

