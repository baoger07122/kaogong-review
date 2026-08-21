// ===== 笔记类型数据服务 =====
// 全局默认类型只作为旧数据兼容和新模块首次初始化的模板；
// 实际使用的类型按「科目 + 模块」独立保存。
window.App = window.App || {};
App.NoteTypes = (function () {
  const KEY = 'kg_note_types';
  const CONTEXT_KEY = 'kg_note_types_by_context';
  const UNCLASSIFIED = '未分类';
  const DEFAULT_TYPES = [
    { name: '技巧总结', color: '#0066CC' },
    { name: '解题方法', color: '#FF9500' },
    { name: '知识积累', color: '#34C759' },
    { name: '错题复盘', color: '#9B7BFF' }
  ];

  function clone(list) {
    return (Array.isArray(list) ? list : []).map((item) => ({
      name: String(item && item.name || '').trim(),
      color: item && item.color || '#0066CC',
      enabled: item && item.enabled !== false
    })).filter(item => item.name);
  }

  function readLegacy() {
    try {
      const raw = localStorage.getItem(KEY);
      if (!raw) return [];
      const arr = JSON.parse(raw);
      return Array.isArray(arr) ? clone(arr) : [];
    } catch (e) { return []; }
  }

  function saveLegacy(list) {
    try { localStorage.setItem(KEY, JSON.stringify(clone(list))); } catch (e) { /* ignore */ }
  }

  function readContexts() {
    try {
      const raw = localStorage.getItem(CONTEXT_KEY);
      if (!raw) return {};
      const obj = JSON.parse(raw);
      if (!obj || typeof obj !== 'object' || Array.isArray(obj)) return {};
      const result = {};
      Object.keys(obj).forEach(key => { result[key] = clone(obj[key]); });
      return result;
    } catch (e) { return {}; }
  }

  function saveContexts(contexts) {
    try { localStorage.setItem(CONTEXT_KEY, JSON.stringify(contexts || {})); } catch (e) { /* ignore */ }
  }

  function normalizeScope(subject, module) {
    const s = String(subject || '').trim();
    if (!s) return null;
    const isFlat = App.Constants && typeof App.Constants.isFlatSubject === 'function' && App.Constants.isFlatSubject(s);
    return { subject: s, module: isFlat ? '' : String(module || '').trim() };
  }

  function getKey(subject, module) {
    const scope = normalizeScope(subject, module);
    return scope ? JSON.stringify([scope.subject, scope.module]) : '';
  }

  function ensureDefault() {
    if (!readLegacy().length) saveLegacy(DEFAULT_TYPES);
  }

  function getAll(subject, module) {
    if (subject) return getForContext(subject, module);
    ensureDefault();
    return readLegacy().filter(item => item.enabled !== false);
  }

  function getForContextAll(subject, module) {
    const key = getKey(subject, module);
    if (!key) return [];
    const contexts = readContexts();
    if (!Object.prototype.hasOwnProperty.call(contexts, key)) {
      ensureDefault();
      contexts[key] = clone(readLegacy());
      saveContexts(contexts);
    }
    return clone(contexts[key]);
  }

  function getForContext(subject, module) {
    return getForContextAll(subject, module).filter(item => item.enabled !== false);
  }

  function saveContext(subject, module, list) {
    const key = getKey(subject, module);
    if (!key) return false;
    const contexts = readContexts();
    contexts[key] = clone(list);
    saveContexts(contexts);
    return true;
  }

  function add(name, color) {
    ensureDefault();
    const list = readLegacy();
    const nm = String(name || '').trim();
    if (!nm || list.some(t => t.name === nm)) return false;
    list.push({ name: nm, color: color || '#0066CC', enabled: true });
    saveLegacy(list);
    return true;
  }

  function remove(name) {
    saveLegacy(readLegacy().filter(t => t.name !== name));
  }

  function addForContext(subject, module, name, color) {
    const list = getForContextAll(subject, module);
    const nm = String(name || '').trim();
    if (!nm || list.some(t => t.name === nm)) return false;
    list.push({ name: nm, color: color || '#0066CC', enabled: true });
    return saveContext(subject, module, list);
  }

  function removeForContext(subject, module, name) {
    const list = getForContextAll(subject, module);
    const next = list.filter(item => item.name !== name);
    if (next.length === list.length) return false;
    return saveContext(subject, module, next);
  }

  function renameForContext(subject, module, oldName, newName, color) {
    const list = getForContextAll(subject, module);
    const nm = String(newName || '').trim();
    const item = list.find(t => t.name === oldName);
    if (!item || !nm || (nm !== oldName && list.some(t => t.name === nm))) return false;
    item.name = nm;
    if (color) item.color = color;
    return saveContext(subject, module, list);
  }

  function updateForContext(subject, module, name, changes) {
    const list = getForContextAll(subject, module);
    const item = list.find(t => t.name === name);
    if (!item) return false;
    if (changes && changes.color) item.color = changes.color;
    if (changes && typeof changes.enabled === 'boolean') item.enabled = changes.enabled;
    return saveContext(subject, module, list);
  }

  function setEnabledForContext(subject, module, name, enabled) {
    return updateForContext(subject, module, name, { enabled: !!enabled });
  }

  function moveForContext(subject, module, name, direction) {
    const list = getForContextAll(subject, module);
    const index = list.findIndex(t => t.name === name);
    if (index < 0) return false;
    const target = direction === 'up' ? index - 1 : index + 1;
    if (target < 0 || target >= list.length) return false;
    const item = list.splice(index, 1)[0];
    list.splice(target, 0, item);
    return saveContext(subject, module, list);
  }

  function getColor(name, subject, module) {
    const list = subject ? getForContextAll(subject, module) : (ensureDefault(), readLegacy());
    const item = list.find(t => t.name === name);
    return item ? item.color : '#0066CC';
  }

  function exportData() {
    return { legacy: readLegacy(), contexts: readContexts() };
  }

  function importData(data) {
    if (!data || typeof data !== 'object') return;
    if (Array.isArray(data.legacy)) saveLegacy(data.legacy);
    if (data.contexts && typeof data.contexts === 'object' && !Array.isArray(data.contexts)) {
      const contexts = {};
      Object.keys(data.contexts).forEach(key => { contexts[key] = clone(data.contexts[key]); });
      saveContexts(contexts);
    } else {
      try { localStorage.removeItem(CONTEXT_KEY); } catch (e) { /* ignore */ }
    }
    ensureDefault();
  }

  return {
    getAll,
    ensureDefault,
    getKey,
    getForContext,
    getForContextAll,
    UNCLASSIFIED,
    add,
    remove,
    addForContext,
    removeForContext,
    renameForContext,
    updateForContext,
    setEnabledForContext,
    moveForContext,
    getColor,
    exportData,
    importData,
    DEFAULT_COLORS: DEFAULT_TYPES.map(t => t.color)
  };
})();
