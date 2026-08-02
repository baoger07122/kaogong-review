/* 考点/错因标签管理（tagManager + tagInput 展开折叠）专项测试 */
const { JSDOM } = require('jsdom');
const fs = require('fs');
const html = fs.readFileSync('index.html', 'utf8');

let pass = 0, fail = 0;
function assert(cond, msg) {
  if (cond) { pass++; console.log('  ✓ ' + msg); }
  else { fail++; console.log('  ✗ ' + msg); }
}

const dom = new JSDOM(html, {
  runScripts: 'dangerously', pretendToBeVisual: true, url: 'https://localhost/',
  beforeParse(w) {
    w.matchMedia = w.matchMedia || function () { return { matches: false, addListener() {}, removeListener() {}, addEventListener() {}, removeEventListener() {}, dispatchEvent() { return false; } }; };
    w.requestAnimationFrame = (cb) => setTimeout(cb, 0);
    w.cancelAnimationFrame = (id) => clearTimeout(id);
    w.getSelection = () => ({ rangeCount: 0, removeAllRanges() {}, addRange() {}, getRangeAt() { return { toString: () => '' }; }, isCollapsed: true });
    w.scrollTo = () => {};
  }
});

setTimeout(async () => {
  const win = dom.window, doc = win.document, App = win.App;

  // mock IndexedDB 依赖：App.DB.kvSet 直接改内存对象
  const kvStore = {};
  if (App.DB) {
    App.DB.kvSet = async (k, v) => { kvStore[k] = JSON.parse(JSON.stringify(v)); };
    App.DB.kvGet = async (k) => kvStore[k];
    App.DB.get = async () => null;
  }
  // App.Tags 的 confirm / toast 打桩
  App.Components.confirm = async () => true;
  App.Components.toast = () => {};

  try {
    // ===== [1] tagManager 渲染：模块折叠卡片 + 标签云 =====
    console.log('\n[1] tagManager 渲染');
    const mgrContainer = doc.createElement('div');
    doc.body.appendChild(mgrContainer);
    // 预置数据（绕过 App.Tags.load，直接写 cache 不可达 → 用 App.Tags 的公开 API 需 kvSet；
    // 简化：先检查初始 seed 数据是否可用）
    const mods = [];
    App.Constants.SUBJECTS.forEach(s => App.Constants.getModules(s.name).forEach(m => { if (!mods.includes(m)) mods.push(m); }));
    assert(mods.length > 0, '模块收集非空 (' + mods.length + ' 个)');
    // 给第一个模块加两个考点，验证标签云渲染
    const m0 = mods[0];
    await App.Tags.addKnowledgePoint(m0, '测试考点A');
    await App.Tags.addKnowledgePoint(m0, '测试考点B');
    await App.Tags.addModuleErrorCause(m0, '测试错因A');

    App.Components.tagManager(mgrContainer, { title: '标签管理', kinds: ['kp', 'ec'] });
    const modules = mgrContainer.querySelectorAll('.tag-module');
    assert(modules.length === mods.length, '模块卡片数量 = 全部模块 (' + modules.length + ')');
    assert(!!mgrContainer.querySelector('.tag-manager__edit-toggle'), '编辑/完成切换按钮存在');
    assert(mgrContainer.querySelector('.tag-manager__edit-toggle').textContent === '编辑', '初始为「编辑」');
    // 找到 m0 模块卡片并验证其考点/错因 pills
    const getM0Card = () => {
      const cards = mgrContainer.querySelectorAll('.tag-module');
      return Array.from(cards).find(m => m.querySelector('.tag-module-name').textContent === m0);
    };
    const m0Card = getM0Card();
    assert(!!m0Card, '模块卡片含「' + m0 + '」');
    const kpPills = Array.from(m0Card.querySelectorAll('.tag-pill')).filter(p => p.dataset.kind === 'kp');
    const ecPills = Array.from(m0Card.querySelectorAll('.tag-pill')).filter(p => p.dataset.kind === 'ec');
    assert(kpPills.some(p => p.textContent.includes('测试考点A')), '考点云含「测试考点A」');
    assert(kpPills.some(p => p.textContent.includes('测试考点B')), '考点云含「测试考点B」');
    assert(ecPills.some(p => p.textContent.includes('测试错因A')), '错因云含「测试错因A」');
    // 默认展开
    assert(m0Card.querySelector('.tag-module-content').classList.contains('expanded'), '默认展开');

    // ===== [2] 折叠/展开切换 =====
    console.log('\n[2] 折叠/展开');
    getM0Card().querySelector('.tag-module-header').dispatchEvent(new win.MouseEvent('click', { bubbles: true }));
    assert(!getM0Card().querySelector('.tag-module-content').classList.contains('expanded'), '点击头部后折叠');
    getM0Card().querySelector('.tag-module-header').dispatchEvent(new win.MouseEvent('click', { bubbles: true }));
    assert(getM0Card().querySelector('.tag-module-content').classList.contains('expanded'), '再次点击后展开');

    // ===== [3] 编辑模式：切换 + 拖拽把手 + 删除 + 添加 =====
    console.log('\n[3] 编辑模式');
    mgrContainer.querySelector('.tag-manager__edit-toggle').dispatchEvent(new win.MouseEvent('click', { bubbles: true }));
    assert(mgrContainer.classList.contains('edit-mode'), '容器进入 edit-mode');
    const editToggle = mgrContainer.querySelector('.tag-manager__edit-toggle');
    assert(editToggle.textContent === '完成', '按钮变为「完成」');
    const kpPillA = Array.from(mgrContainer.querySelectorAll('.tag-pill')).find(p => p.textContent.includes('测试考点A'));
    assert(kpPillA && kpPillA.draggable === true, '编辑模式下 pill 可拖拽 (draggable)');
    assert(!!kpPillA.querySelector('.tag-drag-handle'), '拖拽把手 ⋮⋮ 存在');
    assert(!!kpPillA.querySelector('.tag-delete-btn'), '删除 × 按钮存在');
    const m0Edit = getM0Card();
    assert(!!m0Edit.querySelector('.tag-add-btn'), '+ 添加 按钮存在');
    assert(!!mgrContainer.querySelector('.tag-manager__hint'), '编辑模式提示条存在');
    // 点击 + 添加 → 输入行显示
    m0Edit.querySelector('.tag-add-btn').dispatchEvent(new win.MouseEvent('click', { bubbles: true }));
    const inputRow = getM0Card().querySelector('.tag-add-input-row.show');
    assert(!!inputRow, '输入行显示');
    // 输入并回车添加
    const input = inputRow.querySelector('input');
    input.value = '新考点';
    input.dispatchEvent(new win.KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }));
    await new Promise(r => setTimeout(r, 50));
    const afterAdd = App.Tags.getKnowledgePoints(m0);
    assert(afterAdd.includes('新考点'), '添加后 App.Tags 含「新考点」');
    // 删除：confirm 已打桩为 true
    const kpPillB = Array.from(mgrContainer.querySelectorAll('.tag-pill')).find(p => p.textContent.includes('测试考点B'));
    kpPillB.querySelector('.tag-delete-btn').dispatchEvent(new win.MouseEvent('click', { bubbles: true }));
    await new Promise(r => setTimeout(r, 50));
    assert(!App.Tags.getKnowledgePoints(m0).includes('测试考点B'), '删除后 App.Tags 移除「测试考点B」');

    // ===== [4] 拖拽排序（同模块内） =====
    console.log('\n[4] 拖拽排序');
    // 重建组件（当前编辑态），模拟 dragstart 数据 + drop 到目标 pill
    const kpPills2 = Array.from(mgrContainer.querySelectorAll('.tag-pill')).filter(p => p.dataset.kind === 'kp');
    const pillFrom = kpPills2.find(p => p.textContent.includes('测试考点A'));
    const pillTo = kpPills2.find(p => p.textContent.includes('新考点'));
    if (pillFrom && pillTo) {
      // 拖拽数据经组件闭包传递（dragstart 设置），drop 直接用
      pillFrom.dispatchEvent(new win.Event('dragstart', { bubbles: true, cancelable: true }));
      pillTo.dispatchEvent(new win.Event('dragover', { bubbles: true, cancelable: true }));
      pillTo.dispatchEvent(new win.Event('drop', { bubbles: true, cancelable: true }));
      await new Promise(r => setTimeout(r, 50));
      const order = App.Tags.getKnowledgePoints(m0);
      assert(order.indexOf('测试考点A') > order.indexOf('新考点'), '拖拽后顺序交换（新考点在测试考点A 前面）(' + order.join(',') + ')');
    } else {
      console.log('  ✗ 拖拽排序：未找到拖拽源/目标 pill');
      fail++;
    }
    // 编辑模式 → 完成（退出）
    mgrContainer.querySelector('.tag-manager__edit-toggle').dispatchEvent(new win.MouseEvent('click', { bubbles: true }));
    assert(!mgrContainer.classList.contains('edit-mode'), '点击「完成」退出编辑模式');

    // ===== [5] KpManage 页面 =====
    console.log('\n[5] KpManage 页面');
    const page = doc.getElementById('page-kpmanage');
    if (!page) {
      const p = doc.createElement('div');
      p.id = 'page-kpmanage';
      doc.body.appendChild(p);
    }
    await App.Pages.KpManage.render({});
    const kpPage = doc.getElementById('page-kpmanage');
    assert(!!kpPage.querySelector('.tag-manager'), 'KpManage 渲染 tagManager');
    assert(!!kpPage.querySelector('.tag-module'), '模块折叠卡片渲染');
    assert(!!kpPage.querySelector('.tag-manager__edit-toggle'), '编辑/完成按钮渲染');
    assert(kpPage.textContent.includes('考点 / 错因管理'), '页面标题存在');

    // ===== [6] tagInput 建议标签展开/折叠 =====
    console.log('\n[6] tagInput 展开/折叠');
    // 造 8 个考点，验证折叠 + 展开
    for (let i = 0; i < 8; i++) await App.Tags.addKnowledgePoint(m0, '折叠考点' + i);
    const picker = App.Components.tagInput('考点', App.Tags.getKnowledgePoints(m0), [], () => {}, 3, true, 'ph', null, { kind: 'kp', module: m0 });
    doc.body.appendChild(picker);
    const suggestions = picker.querySelectorAll('.tag-input__suggestion');
    assert(suggestions.length <= 6, '建议折叠：显示 ≤6 个 (' + suggestions.length + ')');
    const moreBtn = picker.querySelector('.tag-input__more');
    assert(!!moreBtn, '「展开全部」按钮存在');
    moreBtn.dispatchEvent(new win.MouseEvent('click', { bubbles: true }));
    const afterExpand = picker.querySelectorAll('.tag-input__suggestion').length;
    assert(afterExpand >= 8, '展开后显示全部 (' + afterExpand + ')');
    assert(picker.querySelector('.tag-input__more').textContent.includes('收起'), '展开后按钮变「收起」');

    console.log('\n===== 标签管理: ' + pass + ' 通过, ' + fail + ' 失败 =====');
    process.exit(fail > 0 ? 1 : 0);
  } catch (e) {
    console.error('测试异常:', e && e.stack || e);
    process.exit(1);
  }
}, 1000);
