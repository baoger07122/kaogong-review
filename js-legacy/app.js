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
    const params = {};
    if (queryString) {
      queryString.split('&').forEach(pair => {
        const [k, v] = pair.split('=');
        if (k) params[k] = decodeURIComponent(v || '');
      });
    }

    // 隐藏所有页面
    document.querySelectorAll('.page').forEach(p => {
      p.style.display = 'none';
      p.classList.remove('active');
    });

    // 显示目标页面
    const pageEl = document.getElementById('page-' + base);
    if (pageEl) {
      pageEl.style.display = 'block';
      pageEl.classList.add('active');
    }

    // 离开表单页时清掉进行中的草稿，确保下次新建必为空白；
    // 但保留「目标即本表单」的情况（如刷新当前页），以支持续编恢复。
    try {
      if (App.Draft && App.Draft.clearForm) {
        ['note', 'error', 'exam'].forEach(function (p) {
          if (base !== p + '-form') App.Draft.clearForm(p);
        });
      }
    } catch (e) {}

    // 更新底部导航高亮
    this.updateNavHighlight(base);

    // 显示/隐藏 FAB
    this.updateFabVisibility(base);

    // 调用页面渲染
    try {
      await this.renderPage(base, params);
    } catch (err) {
      console.error('页面渲染错误:', err);
      App.Components.toast('页面加载失败，请重试', 'error');
    }

    // 滚动到顶部
    window.scrollTo(0, 0);

    this.currentPage = base;
    this.currentParams = params;

    // 更新导航角标
    this.updateNavBadges();
  },

  updateNavHighlight(currentPage) {
    document.querySelectorAll('#bottom-nav .nav-item').forEach(a => {
      a.classList.toggle('active', a.dataset.tab === currentPage);
    });
  },

  updateFabVisibility(currentPage) {
    const fab = document.getElementById('fab');
    if (!fab) return;

    const showPages = ['home', 'errors', 'notes', 'exams'];
    if (showPages.includes(currentPage)) {
      fab.classList.remove('fab--hidden');
    } else {
      fab.classList.add('fab--hidden');
    }
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
      case 'exams':
        if (App.Pages.Exams && App.Pages.Exams.render) await App.Pages.Exams.render(params);
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
    }
  },

  navigate(route) {
    location.hash = route;
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
    if (!isCloudPort) {
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

  // 初始化数据库
  try {
    await App.DB.init();
  } catch (e) {
    console.error('数据库初始化失败:', e);
    if (App.Components && App.Components.toast) {
      App.Components.toast('数据库不可用，部分功能受限', 'error');
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

  // 初始化路由
  App.Router.init();

  // 初始化 FAB 点击事件
  const fab = document.getElementById('fab');
  if (fab) {
    fab.addEventListener('click', () => {
      const page = App.Router.currentPage;
      // 点「新建」前清掉进行中的草稿，保证打开的是空白表单
      if (App.Draft && App.Draft.clearAllForms) App.Draft.clearAllForms();
      switch (page) {
        case 'home':
          // 首页 FAB 可添加待办
          App.Router.navigate('error-form');
          break;
        case 'errors':
          App.Router.navigate('error-form');
          break;
        case 'notes':
          App.Router.navigate('note-form');
          break;
        case 'exams':
          App.Router.navigate('exam-form');
          break;
      }
    });
  }
});
