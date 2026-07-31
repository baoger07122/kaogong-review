// ===== 考公笔试复盘系统 - 表单草稿自动暂存 =====
// 解决 iPad 分屏切换 / app 被系统回收 / 任何原因导致页面重建时，未保存的输入丢失问题。
// 原则：边填边存 localStorage（纯本地，不上云）；提交成功后清除；重新打开表单时静默恢复。
// 覆盖页面：error-form / note-form / exam-form（所有录入表单）
window.App = window.App || {};

App.Draft = (function () {
  const PREFIX = 'kaogong_draft_';
  const DEBOUNCE_MS = 800;

  // 内部：取 key
  function _key(pageName) { return PREFIX + pageName; }

  // 保存草稿
  function save(pageName, data) {
    try {
      localStorage.setItem(_key(pageName), JSON.stringify({ data, savedAt: Date.now() }));
    } catch (e) { /* 存满时静默失败 */ }
  }

  // 加载草稿（返回 data 或 null）
  function load(pageName) {
    try {
      const raw = localStorage.getItem(_key(pageName));
      if (!raw) return null;
      const parsed = JSON.parse(raw);
      return parsed && parsed.data ? parsed.data : null;
    } catch (e) { return null; }
  }

  // 清除草稿（提交成功后调用）
  function clear(pageName) {
    try { localStorage.removeItem(_key(pageName)); } catch (e) {}
  }

  // 是否有草稿
  function has(pageName) {
    return !!load(pageName);
  }

  // 自动绑定：监听容器内所有输入变化，防抖后保存草稿
  //   container: 表单容器元素
  //   pageName: 草稿 key（如 'error-form'）
  //   getFormData: 返回当前完整 formData 的函数
  // 返回：取消绑定的函数（用于表单销毁时清理）
  function autoSave(container, pageName, getFormData) {
    if (!container || typeof getFormData !== 'function') return function () {};
    let timer = null;
    const handler = function () {
      clearTimeout(timer);
      timer = setTimeout(function () {
        try {
          const d = getFormData();
          if (d) save(pageName, d);
        } catch (e) {}
      }, DEBOUNCE_MS);
    };
    // 监听 input / change 事件（覆盖 text/textarea/select/radio/checkbox/contenteditable）
    container.addEventListener('input', handler);
    container.addEventListener('change', handler);
    // 也监听 blur（某些富编辑器用 blur 触发更新）
    container.addEventListener('blur', handler, true);
    return function () {
      clearTimeout(timer);
      container.removeEventListener('input', handler);
      container.removeEventListener('change', handler);
      container.removeEventListener('blur', handler, true);
    };
  }

  // ===== 进行中表单的「续编」恢复（按真实记录 id，杜绝旧草稿串入） =====
  // 设计要点：
  //  1) 新建笔记一律空白；只有「同一篇正在录入」的会话（sessionStorage 里的当前记录 id）才续编。
  //  2) 续编来源优先取 DB 里的真实记录（权威、不会重复建记录）；建记录前的极短窗口才用 localStorage 草稿兜底。
  //  3) 一旦离开表单页（返回/切换/iPad 切窗），路由会清掉 sessionStorage 的当前 id，
  //     于是下次点「新建」必为空白——彻底解决「打开新笔记却冒出旧内容」。
  const FORM_SS = 'kaogong_form_';
  function formDraftKey(page, id) { return 'form_' + page + '_' + id; }

  function getFormId(page) {
    try { return sessionStorage.getItem(FORM_SS + page) || null; } catch (e) { return null; }
  }
  function setFormId(page, id) {
    try { sessionStorage.setItem(FORM_SS + page, id); } catch (e) {}
  }
  function clearForm(page) {
    try {
      const id = sessionStorage.getItem(FORM_SS + page);
      if (id) clear(formDraftKey(page, id));
      sessionStorage.removeItem(FORM_SS + page);
    } catch (e) {}
  }
  function clearDraftKey(page, id) {
    if (id) clear(formDraftKey(page, id));
  }
  function clearAllForms() {
    ['note', 'error', 'exam'].forEach(function (p) { clearForm(p); });
  }
  function saveForm(page, id, data) {
    if (!id) return;
    save(formDraftKey(page, id), data);
  }
  function loadForm(page, id) {
    return id ? load(formDraftKey(page, id)) : null;
  }
  // 与 autoSave 同逻辑，但键名用「表单类型 + 记录 id」
  function autoSaveForm(page, id, container, getFormData) {
    return autoSave(container, formDraftKey(page, id), getFormData);
  }
  function formIdIsTemp(id) { return !id || String(id).charAt(0) === 't'; }
  // 生成「临时表单 id」（以 t 开头，便于 formIdIsTemp 识别）；仅用于草稿键名，非 DB 记录。
  function newTempId() {
    return 't' + Date.now().toString(36) + Math.random().toString(36).slice(2, 5);
  }

  // 清除所有草稿（调试/重置用）
  function clearAll() {
    const keys = [];
    for (let i = 0; i < localStorage.length; i++) {
      const k = localStorage.key(i);
      if (k && k.indexOf(PREFIX) === 0) keys.push(k);
    }
    keys.forEach(function (k) { localStorage.removeItem(k); });
    clearAllForms();
  }

  return {
    save: save,
    load: load,
    clear: clear,
    has: has,
    autoSave: autoSave,
    clearAll: clearAll,
    getFormId: getFormId,
    setFormId: setFormId,
    clearForm: clearForm,
    clearDraftKey: clearDraftKey,
    clearAllForms: clearAllForms,
    saveForm: saveForm,
    loadForm: loadForm,
    autoSaveForm: autoSaveForm,
    formIdIsTemp: formIdIsTemp,
    newTempId: newTempId
  };
})();
