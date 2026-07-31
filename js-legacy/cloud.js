// ===== 考公笔试复盘系统 - 云端同步层 =====
// 与同源 /api 接口对接；登录后本地数据实时镜像到云端，可跨设备 / 跨版本访问。
// 同步集合：errors / notes / exams / todos / subject_reviews / words
// 说明：应用必须运行在提供 /api 的同源端口（沙箱内部署的 3000 端口）。
//       若页面跑在其它网关端口（如 8000），app.js 会在加载时自动重定向到 3000。
window.App = window.App || {};
App.Cloud = (function () {
  const COLLS = ['errors', 'notes', 'exams', 'todos', 'subject_reviews', 'words'];
  const KT = 'kaogong_cloud_token';
  const KE = 'kaogong_cloud_email';
  const KL = 'kaogong_cloud_last';

  let _token = '';
  let _email = '';
  let _last = 0;          // 上次成功同步时间戳
  let _suppress = false;  // 内部批量写入时抑制自动推送，避免回环
  let _queue = [];        // 待推送任务 {op, coll, item?, id?}
  let _flushing = false;

  // ---------- 基础 ----------
  function init() {
    _token = localStorage.getItem(KT) || '';
    _email = localStorage.getItem(KE) || '';
    _last = parseInt(localStorage.getItem(KL) || '0', 10) || 0;
  }

  function isLoggedIn() { return !!_token; }
  function getEmail() { return _email; }

  function authHeaders() {
    return { 'Authorization': 'Bearer ' + _token, 'Content-Type': 'application/json' };
  }

  function _setSession(token, email) {
    _token = token; _email = email;
    localStorage.setItem(KT, token);
    localStorage.setItem(KE, email);
  }

  function _touch() {
    _last = Date.now();
    localStorage.setItem(KL, String(_last));
  }

  function getLastSyncText() {
    if (!_last) return '尚未同步';
    const d = new Date(_last);
    const p = (n) => String(n).padStart(2, '0');
    return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}`;
  }

  // ---------- 网络 ----------
  async function postJSON(path, body) {
    try {
      const res = await fetch('/api' + path, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body)
      });
      let data = null;
      try { data = await res.json(); } catch (e) { data = null; }
      if (!res.ok) return { error: (data && data.error) || ('请求失败 (' + res.status + ')') };
      return data || {};
    } catch (e) {
      return { error: '网络错误，请检查连接' };
    }
  }

  async function pushRecord(coll, item) {
    if (!isLoggedIn() || !COLLS.includes(coll) || !item || !item.id) return;
    const res = await fetch('/api/' + coll, {
      method: 'POST', headers: authHeaders(), body: JSON.stringify(item)
    });
    if (!res.ok) throw new Error('上传 ' + coll + ' 失败(' + res.status + ')');
  }

  async function deleteRecord(coll, id) {
    if (!isLoggedIn() || !COLLS.includes(coll) || !id) return;
    const res = await fetch('/api/' + coll + '/' + encodeURIComponent(id), {
      method: 'DELETE', headers: authHeaders()
    });
    if (!res.ok && res.status !== 404) throw new Error('删除 ' + coll + ' 失败(' + res.status + ')');
  }

  // ---------- 队列（防抖批量推送）----------
  function queuePush(coll, item) { _queue.push({ op: 'put', coll, item }); scheduleFlush(); }
  function queueDelete(coll, id) { _queue.push({ op: 'del', coll, id }); scheduleFlush(); }

  function scheduleFlush() {
    if (_flushing) return;
    setTimeout(flush, 500);
  }

  async function flush() {
    if (_flushing) return;
    _flushing = true;
    const batch = _queue; _queue = [];
    for (const job of batch) {
      try {
        if (job.op === 'put') await pushRecord(job.coll, job.item);
        else await deleteRecord(job.coll, job.id);
      } catch (e) {
        _queue.push(job); // 失败重试
      }
    }
    if (_queue.length) setTimeout(flush, 2000);
    _flushing = false;
  }

  // ---------- 整库同步 ----------
  // 上传：每次保存通过 wrapDB 钩子自动推送（见 _onMutate），无需手动。
  // 下载：手动触发（syncNow）→ 先确保本地改动已上传，再按记录安全合并。
  // 安全原则：拉取绝不 clearStore、绝不因“云端没有”删除本地记录；
  // 仅做「云端新增→插入 / 云端更新(updatedAt 更新)→覆盖」，本地更新或更早则保留。
  async function pushAll() {
    if (!isLoggedIn()) return;
    for (const coll of COLLS) {
      const local = await App.DB.getAll(coll);
      for (const item of local) await pushRecord(coll, item);
    }
    _touch();
  }

  // 手动下载：安全合并（last-write-wins by updatedAt），不删本地、不整库清空
  async function pullMerge() {
    if (!isLoggedIn()) return;
    for (const coll of COLLS) {
      const res = await fetch('/api/' + coll, { headers: authHeaders() });
      if (!res.ok) continue;
      const remote = await res.json();
      const local = await App.DB.getAll(coll);
      const localMap = new Map();
      local.forEach(x => localMap.set(x.id, x));
      const t = (o) => new Date((o && (o.updatedAt || o.createdAt)) || 0).getTime();
      _suppress = true;
      for (const r of remote) {
        const l = localMap.get(r.id);
        if (!l) {
          await App.DB.add(coll, r);            // 云端新增 → 插入本地
        } else if (t(r) > t(l)) {
          await App.DB.put(coll, r);            // 云端更新 → 覆盖本地
        }
        // 本地更新/更早 → 保留本地（已在上一步推上云）
      }
      _suppress = false;
    }
    _touch();
    _refreshUI();
  }

  // 登录后首次协调：先上传本地，再安全合并云端（无需区分空/非空）
  async function reconcile() {
    if (!isLoggedIn()) return;
    try {
      await pushAll();
      await pullMerge();
      App.Components.toast('已同步云端数据 ☁️', 'success');
    } catch (e) {
      App.Components.toast('同步出错：' + (e.message || e), 'error');
    }
    _refreshUI();
  }

  // 手动下载（用户主动点击「立即同步」）：先上传本地改动，再安全合并云端
  async function syncNow() {
    if (!isLoggedIn()) { App.Components.toast('请先登录云同步', 'error'); return; }
    try {
      await pushAll();
      await pullMerge();
      App.Components.toast('同步完成 ☁️', 'success');
      safeRefresh();
    } catch (e) {
      App.Components.toast('同步失败：' + (e.message || e), 'error');
    }
  }

  // 同步后刷新当前页；若在录入表单页则跳过，避免丢失未提交的输入
  function safeRefresh() {
    const p = App.Router && App.Router.currentPage;
    if (p && p.indexOf('-form') !== -1) return;
    if (App.Router && App.Router.handleRoute) App.Router.handleRoute();
  }

  // 应用启动时校验 token 是否仍有效（不拉取数据，尊重本地）
  async function validate() {
    if (!isLoggedIn()) return false;
    try {
      const res = await fetch('/api/errors', { headers: authHeaders() });
      if (res.ok) return true;
      if (res.status === 401) {
        logout();
        App.Components.toast('登录已失效，请重新登录', 'error');
        return false;
      }
      return true;
    } catch (e) {
      return true; // 网络异常时保留 token，稍后重试
    }
  }

  // ---------- 登录 / 注册 / 退出 ----------
  async function login(email, password) {
    const data = await postJSON('/auth/login', { email, password });
    if (data.error) throw new Error(data.error);
    _setSession(data.token, data.email);
    App.Components.toast('登录成功', 'success');
    await reconcile();
    _refreshUI();
  }

  async function register(email, password) {
    const data = await postJSON('/auth/register', { email, password });
    if (data.error) throw new Error(data.error);
    _setSession(data.token, data.email);
    App.Components.toast('注册成功', 'success');
    await reconcile();
    _refreshUI();
  }

  function logout() {
    _token = ''; _email = '';
    localStorage.removeItem(KT);
    localStorage.removeItem(KE);
    App.Components.toast('已退出云同步', 'success');
    _refreshUI();
  }

  // ---------- 自动同步已取消（用户需求：自动上传 + 手动下载）----------
  // 上传：每次保存经 wrapDB 钩子自动推送，无需轮询。
  // 下载：仅用户点击「立即同步」时通过 syncNow() 手动执行，避免页面被自动刷新清空。

  // ---------- 挂载到 DB 写入钩子 ----------
  function wrapDB() {
    const orig = { add: App.DB.add, put: App.DB.put, remove: App.DB.remove };
    App.DB.add = async function (store, item) {
      const r = await orig.add(store, item);
      _onMutate(store, 'put', item);
      return r;
    };
    App.DB.put = async function (store, item) {
      const r = await orig.put(store, item);
      _onMutate(store, 'put', item);
      return r;
    };
    App.DB.remove = async function (store, id) {
      const r = await orig.remove(store, id);
      _onMutate(store, 'del', id);
      return r;
    };
  }

  function _onMutate(store, op, payload) {
    if (_suppress) return;
    if (!isLoggedIn()) return;
    if (!COLLS.includes(store)) return;
    if (op === 'put' && payload && payload.id) queuePush(store, payload);
    else if (op === 'del' && payload) queueDelete(store, payload);
  }

  // 重新渲染设置页（若在设置页）
  function _refreshUI() {
    try {
      if (App.Router && App.Router.currentPage === 'settings' && App.Pages.Settings) {
        App.Pages.Settings.render({});
      }
    } catch (e) { /* ignore */ }
  }

  return {
    init, wrapDB, validate,
    isLoggedIn, getEmail, getLastSyncText,
    login, register, logout,
    syncNow, reconcile,
    COLLS
  };
})();
