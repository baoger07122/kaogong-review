// ===== 考公笔试复盘系统 - 标签库（考点按模块 / 错因全局，均可增删、持久化） =====
// 知识点以「模块」为维度分别管理，确保行测每个模块的考点互不相同；
// 错因为全局维度。预设值仅作为首次种子，之后用户对标签的增删都会持久化保存。
window.App = window.App || {};

App.Tags = (function() {
  const KEY_KP = 'kp_library';        // { 模块名: [考点, ...] }
  const KEY_KPEC = 'kp_ec_library';    // { 模块名: [错因, ...] }（每模块专属错因）
  const KEY_MIGRATED = 'taglib_migrated_v2';

  // 内存缓存
  const cache = {
    knowledgePoints: {},   // module -> array
    kpErrorCauses: {}      // module -> [reason]
  };
  let loaded = false;

  // 从预设深拷贝知识点库
  function seedKnowledgePoints() {
    const out = {};
    const defaultTag = App.Constants.DEFAULT_REVIEW_TAG || '待复盘';
    Object.keys(App.Constants.KNOWLEDGE_POINTS).forEach(m => {
      out[m] = [defaultTag].concat(App.Constants.KNOWLEDGE_POINTS[m].filter(k => k !== defaultTag));
    });
    return out;
  }

  // 系统默认标签：确保已有用户标签库也能在选择器中使用「待复盘」。
  async function ensureDefaultReviewTags() {
    const defaultTag = App.Constants.DEFAULT_REVIEW_TAG || '待复盘';
    const modules = Object.keys(App.Constants.MODULES || {});
    let kpChanged = false;
    let ecChanged = false;
    modules.forEach(module => {
      if (!cache.knowledgePoints[module]) cache.knowledgePoints[module] = [];
      if (!cache.knowledgePoints[module].includes(defaultTag)) {
        cache.knowledgePoints[module].unshift(defaultTag);
        kpChanged = true;
      }
      if (!cache.kpErrorCauses[module]) cache.kpErrorCauses[module] = [];
      if (!cache.kpErrorCauses[module].includes(defaultTag)) {
        cache.kpErrorCauses[module].unshift(defaultTag);
        ecChanged = true;
      }
    });
    if (kpChanged) await App.DB.kvSet(KEY_KP, cache.knowledgePoints);
    if (ecChanged) await App.DB.kvSet(KEY_KPEC, cache.kpErrorCauses);
  }

  // 启动时加载 / 初始化标签库（含旧数据迁移）
  async function init() {
    try {
      let kp = await App.DB.kvGet(KEY_KP);
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

      cache.knowledgePoints = kp || {};
      cache.kpErrorCauses = (await App.DB.kvGet(KEY_KPEC)) || {};

      // 迁移：把旧「共同错因」平铺到每个已存在的模块中
      const legacyEc = await App.DB.kvGet('ec_library');
      if (legacyEc && Array.isArray(legacyEc) && legacyEc.length > 0) {
        const allMods = Object.keys(cache.knowledgePoints);
        allMods.forEach(mod => {
          if (!cache.kpErrorCauses[mod]) cache.kpErrorCauses[mod] = [];
          legacyEc.forEach(ec => {
            if (!cache.kpErrorCauses[mod].includes(ec)) cache.kpErrorCauses[mod].push(ec);
          });
        });
        await App.DB.kvSet(KEY_KPEC, cache.kpErrorCauses);
        await App.DB.kvSet('ec_library', null);  // 清掉老的全局错因
      }

      // 迁移：旧版「模块::考点」维度 → 新版「模块」维度
      if (cache.kpErrorCauses && Object.keys(cache.kpErrorCauses).some(k => k.indexOf('::') !== -1)) {
        const migrated = {};
        Object.keys(cache.kpErrorCauses).forEach(key => {
          const mod = key.split('::')[0];
          if (!migrated[mod]) migrated[mod] = [];
          (cache.kpErrorCauses[key] || []).forEach(r => { if (!migrated[mod].includes(r)) migrated[mod].push(r); });
        });
        cache.kpErrorCauses = migrated;
        await App.DB.kvSet(KEY_KPEC, migrated);
      }

      await ensureDefaultReviewTags();
    } catch (e) {
      cache.knowledgePoints = seedKnowledgePoints();
      cache.kpErrorCauses = {};
      Object.keys(App.Constants.MODULES || {}).forEach(module => {
        cache.kpErrorCauses[module] = [App.Constants.DEFAULT_REVIEW_TAG || '待复盘'];
      });
    }
    loaded = true;
  }

  // ===== 读取 =====
  function getKnowledgePoints(module) {
    return (cache.knowledgePoints[module] || []).slice();
  }
  // 全局错因：所有模块错因的并集（仅用于跨模块筛选 / 统计，不再作为可共享池）
  function getErrorCauses() {
    const set = new Set();
    Object.keys(cache.kpErrorCauses).forEach(mod => {
      (cache.kpErrorCauses[mod] || []).forEach(r => set.add(r));
    });
    return Array.from(set);
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
  // 考点排序：dir = -1 上移 / 1 下移（不在库中则先加入库再移动）
  async function moveKnowledgePoint(module, kp, dir) {
    if (!module || !kp) return;
    if (!cache.knowledgePoints[module]) cache.knowledgePoints[module] = [];
    const arr = cache.knowledgePoints[module];
    if (!arr.includes(kp)) arr.push(kp);
    const i = arr.indexOf(kp);
    const j = i + dir;
    if (j < 0 || j >= arr.length) return;
    arr.splice(i, 1);
    arr.splice(j, 0, kp);
    await App.DB.kvSet(KEY_KP, cache.knowledgePoints);
  }
  // 彻底删除考点：标签库 + 所有引用它的错题 / 笔记
  async function purgeKnowledgePoint(module, kp) {
    if (!module || !kp) return;
    if (cache.knowledgePoints[module]) {
      cache.knowledgePoints[module] = cache.knowledgePoints[module].filter(k => k !== kp);
      await App.DB.kvSet(KEY_KP, cache.knowledgePoints);
    }
    const errs = await App.DB.getErrors();
    for (const e of errs) {
      if ((e.knowledgePoints || []).includes(kp)) {
        e.knowledgePoints = e.knowledgePoints.filter(k => k !== kp);
        await App.DB.updateError(e);
      }
    }
    const notes = await App.DB.getNotes();
    for (const n of notes) {
      if (n.knowledgePoint === kp) { n.knowledgePoint = ''; await App.DB.updateNote(n); }
    }
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

  // ===== 每模块专属错因（key = 模块名）=====
  function getModuleErrorCauses(module) {
    return (cache.kpErrorCauses[module] || []).slice();
  }

  async function addModuleErrorCause(module, reason) {
    reason = (reason || '').trim();
    if (!reason || !module) return;
    if (!cache.kpErrorCauses[module]) cache.kpErrorCauses[module] = [];
    if (cache.kpErrorCauses[module].includes(reason)) return;
    cache.kpErrorCauses[module].push(reason);
    await App.DB.kvSet(KEY_KPEC, cache.kpErrorCauses);
  }

  async function removeModuleErrorCause(module, reason) {
    if (!cache.kpErrorCauses[module]) return;
    cache.kpErrorCauses[module] = cache.kpErrorCauses[module].filter(r => r !== reason);
    await App.DB.kvSet(KEY_KPEC, cache.kpErrorCauses);
  }
  // 错因排序：dir = -1 上移 / 1 下移
  async function moveModuleErrorCause(module, reason, dir) {
    if (!module || !reason) return;
    if (!cache.kpErrorCauses[module]) cache.kpErrorCauses[module] = [];
    const arr = cache.kpErrorCauses[module];
    if (!arr.includes(reason)) arr.push(reason);
    const i = arr.indexOf(reason);
    const j = i + dir;
    if (j < 0 || j >= arr.length) return;
    arr.splice(i, 1);
    arr.splice(j, 0, reason);
    await App.DB.kvSet(KEY_KPEC, cache.kpErrorCauses);
  }
  // 彻底删除错因：标签库 + 该模块所有引用它的错题
  async function purgeModuleErrorCause(module, reason) {
    if (!module || !reason) return;
    if (cache.kpErrorCauses[module]) {
      cache.kpErrorCauses[module] = cache.kpErrorCauses[module].filter(r => r !== reason);
      await App.DB.kvSet(KEY_KPEC, cache.kpErrorCauses);
    }
    const errs = await App.DB.getErrors();
    for (const e of errs) {
      if (e.errorCause === reason && e.module === module) { e.errorCause = ''; await App.DB.updateError(e); }
    }
  }

  async function renameModuleErrorCause(module, oldName, newName) {
    newName = (newName || '').trim();
    if (!newName || oldName === newName) return;
    if (!cache.kpErrorCauses[module] || !cache.kpErrorCauses[module].includes(oldName)) return;
    if (cache.kpErrorCauses[module].includes(newName)) {
      App.Components.toast('该模块已存在同名错因', 'error');
      return;
    }
    cache.kpErrorCauses[module] = cache.kpErrorCauses[module].map(r => r === oldName ? newName : r);
    await App.DB.kvSet(KEY_KPEC, cache.kpErrorCauses);
    // 同步已录入错题中、且命中该模块的同一错因
    const errs = await App.DB.getErrors();
    for (const e of errs) {
      if (e.errorCause === oldName && e.module === module) {
        e.errorCause = newName;
        await App.DB.updateError(e);
      }
    }
  }

  // 录题时合并「共同错因 + 该模块的专属错因」
  // 录题时可用错因：仅该模块专属错因（模块间不互通）
  function getMergedErrorCauses(module) {
    return getModuleErrorCauses(module);
  }

  // ===== 扁平科目（仅科目层，无模块细分；如资料分析） =====
  // 该科目所有模块的考点并集（保序去重）
  function getSubjectKnowledgePoints(subject) {
    const out = [];
    (App.Constants.getModules(subject) || []).forEach(m => {
      getKnowledgePoints(m).forEach(k => { if (out.indexOf(k) === -1) out.push(k); });
    });
    return out;
  }
  // 该科目所有模块的错因并集（保序去重）
  function getSubjectErrorCauses(subject) {
    const out = [];
    (App.Constants.getModules(subject) || []).forEach(m => {
      getModuleErrorCauses(m).forEach(c => { if (out.indexOf(c) === -1) out.push(c); });
    });
    return out;
  }
  // 添加考点：同步到该科目所有模块
  async function addSubjectKnowledgePoint(subject, kp) {
    for (const m of (App.Constants.getModules(subject) || [])) await addKnowledgePoint(m, kp);
  }
  // 添加错因：同步到该科目所有模块
  async function addSubjectErrorCause(subject, reason) {
    for (const m of (App.Constants.getModules(subject) || [])) await addModuleErrorCause(m, reason);
  }

  // 用新顺序覆盖标签库顺序（kind: 'kp' | 'ec'），拖拽排序后调用
  async function setOrder(module, kind, orderedNames) {
    if (!module) return; // 全部视图下错因/考点无归属模块，跳过排序持久化，避免写入 null 键污染标签库
    const names = (orderedNames || []).filter(Boolean);
    if (kind === 'kp') {
      if (!cache.knowledgePoints[module]) cache.knowledgePoints[module] = [];
      const rest = cache.knowledgePoints[module].filter(x => !names.includes(x));
      cache.knowledgePoints[module] = names.concat(rest);
      await App.DB.kvSet(KEY_KP, cache.knowledgePoints);
    } else if (kind === 'ec') {
      if (!cache.kpErrorCauses[module]) cache.kpErrorCauses[module] = [];
      const rest = cache.kpErrorCauses[module].filter(x => !names.includes(x));
      cache.kpErrorCauses[module] = names.concat(rest);
      await App.DB.kvSet(KEY_KPEC, cache.kpErrorCauses);
    }
  }

  // ===== 表单建议（仅本模块库 / 全局错因库） =====
  function getKnowledgePointSuggestions(module) {
    return getKnowledgePoints(module);
  }
  function getErrorCauseSuggestions() {
    return getErrorCauses();
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
    moveKnowledgePoint,
    renameKnowledgePoint,
    purgeKnowledgePoint,
    getModuleErrorCauses,
    addModuleErrorCause,
    removeModuleErrorCause,
    moveModuleErrorCause,
    setOrder,
    renameModuleErrorCause,
    purgeModuleErrorCause,
    getMergedErrorCauses,
    getKnowledgePointSuggestions,
    getErrorCauseSuggestions,
    getSubjectKnowledgePoints,
    getSubjectErrorCauses,
    addSubjectKnowledgePoint,
    addSubjectErrorCause,
    getAllModules,
    isLoaded: () => loaded
  };
})();


