// ===== 笔记类型数据服务（对齐画布「iPad-笔记类型管理」8:170 /「新增类型」10:1 / 弹窗 10:114） =====
window.App = window.App || {};
App.NoteTypes = (function () {
  const KEY = 'kg_note_types';
  const DEFAULT_TYPES = [
    { name: '技巧总结', color: '#0066CC' },
    { name: '解题方法', color: '#FF9500' },
    { name: '知识积累', color: '#34C759' },
    { name: '错题复盘', color: '#9B7BFF' }
  ];

  function getAll() {
    try {
      const raw = localStorage.getItem(KEY);
      if (!raw) return [];
      const arr = JSON.parse(raw);
      if (Array.isArray(arr)) return arr;
    } catch (e) { /* ignore */ }
    return [];
  }
  function ensureDefault() {
    if (getAll().length === 0) {
      try { localStorage.setItem(KEY, JSON.stringify(DEFAULT_TYPES)); } catch (e) { /* ignore */ }
    }
  }
  function saveAll(list) {
    try { localStorage.setItem(KEY, JSON.stringify(list)); } catch (e) { /* ignore */ }
  }
  function add(name, color) {
    ensureDefault();
    const list = getAll();
    if (list.some(t => t.name === name)) return false;
    list.push({ name, color: color || '#0066CC' });
    saveAll(list);
    return true;
  }
  function remove(name) {
    const list = getAll().filter(t => t.name !== name);
    saveAll(list);
  }
  function getColor(name) {
    const t = getAll().find(x => x.name === name);
    return t ? t.color : '#0066CC';
  }
  return { getAll, ensureDefault, add, remove, getColor, DEFAULT_COLORS: DEFAULT_TYPES.map(t => t.color) };
})();

