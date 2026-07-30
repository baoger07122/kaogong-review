// ===== 考公笔试复盘系统 - 标签库（考点按模块 / 错因全局，均可增删、持久化） =====
// 知识点以「模块」为维度分别管理，确保行测每个模块的考点互不相同；
// 错因为全局维度。预设值仅作为首次种子，之后用户对标签的增删都会持久化保存。
window.App = window.App || {};

App.Tags = (function() {
  const KEY_KP = 'kp_library';        // { 模块名: [考点, ...] }
  const KEY_EC = 'ec_library';         // [错因, ...]
  const KEY_MIGRATED = 'taglib_migrated_v2';

  // 内存缓存
  const cache = {
    knowledgePoints: {},   // module -> array
    errorCauses: []
  };
  let loaded = false;

  // 从预设深拷贝知识点库
  function seedKnowledgePoints() {
    const out = {};
    Object.keys(App.Constants.KNOWLEDGE_POINTS).forEach(m => {
      out[m] = App.Constants.KNOWLEDGE_POINTS[m].slice();
    });
    return out;
  }
  function seedErrorCauses() {
    return App.Constants.ERROR_CAUSES.map(c => (typeof c === 'string' ? c : c.name));
  }

  // 启动时加载 / 初始化标签库（含旧数据迁移）
  async function init() {
    try {
      let kp = await App.DB.kvGet(KEY_KP);
      let ec = await App.DB.kvGet(KEY_EC);
      const migrated = await App.DB.kvGet(KEY_MIGRATED);

      if (!kp) {
        kp = seedKnowledgePoints();
        // 首次迁移：把数据中已使用的自定义考点，按所属模块并入对应模块库
        if (!migrated) {
          const [errs, notes] = await Promise.all([App.DB.getErrors(), App.DB.getNotes()]);
          errs.forEach(e => (e.knowledgePoints || []).forEach(name => {
            if (e.module && kp[e.module] && !kp[e.module].includes(name)) kp[e.module].push(name);
          }));
          notes.forEach(n => {
            if (n.module && n.knowledgePoint && kp[n.module] && !kp[n.module].includes(n.knowledgePoint)) {
              kp[n.module].push(n.knowledgePoint);
            }
          });
        }
        await App.DB.kvSet(KEY_KP, kp);
        await App.DB.kvSet(KEY_MIGRATED, true);
      }

      if (!ec) {
        ec = seedErrorCauses();
        const legacyEc = await App.DB.kvGet('custom_error_causes');
        if (Array.isArray(legacyEc)) legacyEc.forEach(c => { if (!ec.includes(c)) ec.push(c); });
        await App.DB.kvSet(KEY_EC, ec);
      }

      cache.knowledgePoints = kp || {};
      cache.errorCauses = ec || [];
    } catch (e) {
      cache.knowledgePoints = seedKnowledgePoints();
      cache.errorCauses = seedErrorCauses();
    }
    loaded = true;
  }

  // ===== 读取 =====
  function getKnowledgePoints(module) {
    return (cache.knowledgePoints[module] || []).slice();
  }
  function getErrorCauses() {
    return cache.errorCauses.slice();
  }

  // ===== 知识点（按模块）增删 =====
  async function addKnowledgePoint(module, kp) {
    kp = (kp || '').trim();
    if (!kp || !module) return;
    if (!cache.knowledgePoints[module]) cache.knowledgePoints[module] = [];
    if (cache.knowledgePoints[module].includes(kp)) return;
    cache.knowledgePoints[module].push(kp);
    await App.DB.kvSet(KEY_KP, cache.knowledgePoints);
  }
  async function removeKnowledgePoint(module, kp) {
    if (!cache.knowledgePoints[module]) return;
    cache.knowledgePoints[module] = cache.knowledgePoints[module].filter(k => k !== kp);
    await App.DB.kvSet(KEY_KP, cache.knowledgePoints);
  }

  // ===== 错因（全局）增删 =====
  async function addErrorCause(ec) {
    ec = (ec || '').trim();
    if (!ec) return;
    if (cache.errorCauses.includes(ec)) return;
    cache.errorCauses.push(ec);
    await App.DB.kvSet(KEY_EC, cache.errorCauses);
  }
  async function removeErrorCause(ec) {
    cache.errorCauses = cache.errorCauses.filter(k => k !== ec);
    await App.DB.kvSet(KEY_EC, cache.errorCauses);
  }

  // ===== 重命名（同步更新标签库与已录入数据） =====
  async function renameKnowledgePoint(module, oldName, newName) {
    newName = (newName || '').trim();
    if (!newName || !module || oldName === newName) return;
    if (!cache.knowledgePoints[module] || !cache.knowledgePoints[module].includes(oldName)) return;
    if (cache.knowledgePoints[module].includes(newName)) {
      App.Components.toast('该模块已存在同名考点', 'error');
      return;
    }
    cache.knowledgePoints[module] = cache.knowledgePoints[module].map(k => k === oldName ? newName : k);
    await App.DB.kvSet(KEY_KP, cache.knowledgePoints);

    const errs = await App.DB.getErrors();
    for (const e of errs) {
      if ((e.knowledgePoints || []).includes(oldName)) {
        e.knowledgePoints = e.knowledgePoints.map(k => k === oldName ? newName : k);
        await App.DB.updateError(e);
      }
    }
    const notes = await App.DB.getNotes();
    for (const n of notes) {
      if (n.knowledgePoint === oldName) { n.knowledgePoint = newName; await App.DB.updateNote(n); }
    }
  }

  async function renameErrorCause(oldName, newName) {
    newName = (newName || '').trim();
    if (!newName || oldName === newName) return;
    if (!cache.errorCauses.includes(oldName)) return;
    if (cache.errorCauses.includes(newName)) {
      App.Components.toast('已存在同名错因', 'error');
      return;
    }
    cache.errorCauses = cache.errorCauses.map(c => c === oldName ? newName : c);
    await App.DB.kvSet(KEY_EC, cache.errorCauses);

    const errs = await App.DB.getErrors();
    for (const e of errs) {
      if (e.errorCause === oldName) { e.errorCause = newName; await App.DB.updateError(e); }
    }
  }

  // ===== 表单建议（仅本模块库 / 全局错因库） =====
  function getKnowledgePointSuggestions(module) {
    return getKnowledgePoints(module);
  }
  function getErrorCauseSuggestions() {
    return cache.errorCauses.slice();
  }

  function getAllModules() {
    return Object.keys(cache.knowledgePoints);
  }

  return {
    init,
    getKnowledgePoints,
    getErrorCauses,
    addKnowledgePoint,
    removeKnowledgePoint,
    renameKnowledgePoint,
    addErrorCause,
    removeErrorCause,
    renameErrorCause,
    getKnowledgePointSuggestions,
    getErrorCauseSuggestions,
    getAllModules,
    isLoaded: () => loaded
  };
})();
