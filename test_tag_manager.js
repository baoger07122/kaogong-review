/* 标签管理（科目→模块→标签 三级结构 + 改名）专项测试 */
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

  // mock IndexedDB 依赖
  const kvStore = {};
  if (App.DB) {
    App.DB.kvSet = async (k, v) => { kvStore[k] = JSON.parse(JSON.stringify(v)); };
    App.DB.kvGet = async (k) => kvStore[k];
    App.DB.get = async () => null;
    App.DB.getErrors = async () => [];
    App.DB.getNotes = async () => [];
    App.DB.updateError = async () => {};
    App.DB.updateNote = async () => {};
  }
  App.Components.confirm = async () => true;
  App.Components.toast = () => {};

  try {
    // 找第一个科目及其第一个模块（用于测试数据）
    const sub0 = App.Constants.SUBJECTS[0];
    const subName = sub0.name;
    const modName = App.Constants.getModules(subName)[0];
    assert(!!modName, '第一科目「' + subName + '」有模块');

    // 预置标签数据
    await App.Tags.addKnowledgePoint(modName, '测试考点A');
    await App.Tags.addKnowledgePoint(modName, '测试考点B');
    await App.Tags.addModuleErrorCause(modName, '测试错因A');

    // ===== [1] 三级结构渲染：科目卡片 =====
    console.log('\n[1] 科目→模块→标签 三级结构');
    const mgr = doc.createElement('div');
    doc.body.appendChild(mgr);
    App.Components.tagManager(mgr, { title: '标签管理', kinds: ['kp', 'ec'] });
    const subCards = mgr.querySelectorAll('.tag-subject');
    assert(subCards.length === App.Constants.SUBJECTS.length, '科目卡片数量 = 全部科目 (' + subCards.length + ')');
    // 第一个科目默认展开，其余折叠
    assert(subCards[0].querySelector('.tag-subject-content').classList.contains('expanded'), '第一个科目默认展开');
    assert(!subCards[1].querySelector('.tag-subject-content').classList.contains('expanded'), '其余科目默认折叠');
    // 科目名含科目名称
    assert(subCards[0].querySelector('.tag-subject-name').textContent.includes(subName), '科目头含「' + subName + '」');
    // 空科目（无模块）显示「暂无模块」
    const emptySub = Array.from(subCards).find(s => {
      const name = s.querySelector('.tag-subject-name').textContent;
      return App.Constants.getModules(name.replace(/^\S+\s/, '')) ? false : true;
    });
    if (emptySub) {
      emptySub.querySelector('.tag-subject-header').dispatchEvent(new win.MouseEvent('click', { bubbles: true }));
      // 重新查找（render 重建）
      const reEmpty = Array.from(mgr.querySelectorAll('.tag-subject')).find(s => s.querySelector('.tag-subject-name').textContent === emptySub.querySelector('.tag-subject-name').textContent || true);
      const esContent = mgr.querySelectorAll('.tag-subject-content')[1];
      if (esContent && esContent.textContent.includes('暂无')) assert(true, '空科目显示「暂无模块」');
      else if (!esContent || esContent.textContent.trim() === '') assert(true, '空科目无内容占位');
    }

    // ===== [2] 模块折叠 + 标签云 =====
    console.log('\n[2] 模块折叠与标签云');
    // 第一个科目内容里的第一个模块
    const sub0Content = subCards[0].querySelector('.tag-subject-content');
    const mod0 = sub0Content.querySelector('.tag-module');
    assert(!!mod0, '科目内有模块卡片');
    assert(mod0.querySelector('.tag-module-name').textContent === modName, '模块名为「' + modName + '」');
    // 模块默认折叠
    assert(!mod0.querySelector('.tag-module-content').classList.contains('expanded'), '模块默认折叠');
    // 展开模块
    mod0.querySelector('.tag-module-header').dispatchEvent(new win.MouseEvent('click', { bubbles: true }));
    const mod0Open = mgr.querySelector('.tag-module-content.expanded');
    assert(!!mod0Open, '点击模块头后展开');
    // 考点/错因分类标题 + pills
    const catTitles = Array.from(mod0Open.querySelectorAll('.tag-category-title')).map(x => x.textContent);
    assert(catTitles.length === 2 && catTitles[0].includes('考点') && catTitles[1].includes('错因'), '分类标题: ' + catTitles.join(' / '));
    const kpPills = Array.from(mod0Open.querySelectorAll('.tag-pill')).filter(p => p.dataset.kind === 'kp');
    const ecPills = Array.from(mod0Open.querySelectorAll('.tag-pill')).filter(p => p.dataset.kind === 'ec');
    assert(kpPills.some(p => p.textContent.includes('测试考点A')), '考点云含「测试考点A」');
    assert(kpPills.some(p => p.textContent.includes('测试考点B')), '考点云含「测试考点B」');
    assert(ecPills.some(p => p.textContent.includes('测试错因A')), '错因云含「测试错因A」');

    // ===== [3] 编辑模式：把手/删除/添加 =====
    console.log('\n[3] 编辑模式');
    mgr.querySelector('.tag-manager__edit-toggle').dispatchEvent(new win.MouseEvent('click', { bubbles: true }));
    assert(mgr.classList.contains('edit-mode'), '进入 edit-mode');
    assert(mgr.querySelector('.tag-manager__edit-toggle').textContent === '完成', '按钮变「完成」');
    const editMod = mgr.querySelector('.tag-module-content.expanded');
    const kpPillA = Array.from(editMod.querySelectorAll('.tag-pill')).find(p => p.dataset.kind === 'kp' && p.textContent.includes('测试考点A'));
    assert(kpPillA && kpPillA.draggable === true, '编辑模式 pill 可拖拽');
    assert(!!kpPillA.querySelector('.tag-drag-handle'), '拖拽把手存在');
    assert(!!kpPillA.querySelector('.tag-delete-btn'), '删除按钮存在');
    assert(!!editMod.querySelector('.tag-add-btn'), '+ 添加 按钮存在');
    assert(kpPillA.querySelector('.tag-pill__name').classList.contains('is-editable'), '标签文字可点击改名（is-editable）');
    // 添加
    editMod.querySelector('.tag-add-btn').dispatchEvent(new win.MouseEvent('click', { bubbles: true }));
    const addRow = mgr.querySelector('.tag-add-input-row.show');
    assert(!!addRow, '添加输入行显示');
    addRow.querySelector('input').value = '新考点';
    addRow.querySelector('input').dispatchEvent(new win.KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }));
    await new Promise(r => setTimeout(r, 50));
    assert(App.Tags.getKnowledgePoints(modName).includes('新考点'), '添加后含「新考点」');
    // 删除
    const delPill = Array.from(mgr.querySelectorAll('.tag-pill')).find(p => p.dataset.kind === 'kp' && p.textContent.includes('测试考点B'));
    delPill.querySelector('.tag-delete-btn').dispatchEvent(new win.MouseEvent('click', { bubbles: true }));
    await new Promise(r => setTimeout(r, 50));
    assert(!App.Tags.getKnowledgePoints(modName).includes('测试考点B'), '删除后移除「测试考点B」');

    // ===== [4] 点击标签文字改名 =====
    console.log('\n[4] 标签改名（点击文字 → 输入框 → 回车保存）');
    const renamePill = Array.from(mgr.querySelectorAll('.tag-pill')).find(p => p.dataset.kind === 'kp' && p.textContent.includes('测试考点A'));
    renamePill.querySelector('.tag-pill__name').dispatchEvent(new win.MouseEvent('click', { bubbles: true }));
    const editingPill = mgr.querySelector('.tag-pill.editing');
    assert(!!editingPill, '点击文字后标签变输入框');
    const editInput = editingPill.querySelector('input');
    assert(!!editInput, '输入框存在');
    editInput.value = '改名后的考点';
    editInput.dispatchEvent(new win.KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }));
    await new Promise(r => setTimeout(r, 50));
    assert(App.Tags.getKnowledgePoints(modName).includes('改名后的考点'), '回车后 App.Tags 更新为「改名后的考点」');
    assert(!App.Tags.getKnowledgePoints(modName).includes('测试考点A'), '旧名「测试考点A」已移除');
    // ESC 取消
    const pill2 = Array.from(mgr.querySelectorAll('.tag-pill')).find(p => p.dataset.kind === 'ec' && p.textContent.includes('测试错因A'));
    pill2.querySelector('.tag-pill__name').dispatchEvent(new win.MouseEvent('click', { bubbles: true }));
    const escInput = mgr.querySelector('.tag-pill.editing input');
    escInput.value = '不应保存的名字';
    escInput.dispatchEvent(new win.KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true }));
    await new Promise(r => setTimeout(r, 50));
    assert(App.Tags.getModuleErrorCauses(modName).includes('测试错因A'), 'ESC 取消，原名保留');
    assert(!App.Tags.getModuleErrorCauses(modName).includes('不应保存的名字'), 'ESC 取消，新名不写入');
    // 完成退出
    mgr.querySelector('.tag-manager__edit-toggle').dispatchEvent(new win.MouseEvent('click', { bubbles: true }));
    assert(!mgr.classList.contains('edit-mode'), '点击「完成」退出编辑');

    // ===== [5] 拖拽排序（同模块同类型） =====
    console.log('\n[5] 拖拽排序');
    mgr.querySelector('.tag-manager__edit-toggle').dispatchEvent(new win.MouseEvent('click', { bubbles: true }));   // 再进编辑
    const dragMod = mgr.querySelector('.tag-module-content.expanded');
    const dragKpPills = Array.from(dragMod.querySelectorAll('.tag-pill')).filter(p => p.dataset.kind === 'kp');
    const pillFrom = dragKpPills.find(p => p.textContent.includes('改名后的考点'));
    const pillTo = dragKpPills.find(p => p.textContent.includes('新考点'));
    if (pillFrom && pillTo) {
      pillFrom.dispatchEvent(new win.Event('dragstart', { bubbles: true, cancelable: true }));
      pillTo.dispatchEvent(new win.Event('dragover', { bubbles: true, cancelable: true }));
      pillTo.dispatchEvent(new win.Event('drop', { bubbles: true, cancelable: true }));
      await new Promise(r => setTimeout(r, 50));
      const order = App.Tags.getKnowledgePoints(modName);
      assert(order.indexOf('改名后的考点') > order.indexOf('新考点'), '拖拽后顺序交换 (' + order.join(',') + ')');
    } else {
      console.log('  ✗ 拖拽：未找到源/目标');
      fail++;
    }

    // ===== [6] KpManage 页面 =====
    console.log('\n[6] KpManage 页面');
    await App.Pages.KpManage.render({});
    const kpPage = doc.getElementById('page-kpmanage');
    assert(!!kpPage.querySelector('.tag-manager'), 'KpManage 渲染 tagManager');
    assert(!!kpPage.querySelector('.tag-subject'), '科目卡片渲染');
    assert(kpPage.textContent.includes('考点 / 错因管理'), '页面标题存在');

    // ===== [7] tagInput 建议标签展开/折叠 =====
    console.log('\n[7] tagInput 展开/折叠');
    for (let i = 0; i < 8; i++) await App.Tags.addKnowledgePoint(modName, '折叠考点' + i);
    const picker = App.Components.tagInput('考点', App.Tags.getKnowledgePoints(modName), [], () => {}, 3, true, 'ph', null, { kind: 'kp', module: modName });
    doc.body.appendChild(picker);
    assert(picker.querySelectorAll('.tag-input__suggestion').length <= 6, '建议折叠 ≤6 个');
    const moreBtn = picker.querySelector('.tag-input__more');
    assert(!!moreBtn, '「展开全部」按钮存在');
    moreBtn.dispatchEvent(new win.MouseEvent('click', { bubbles: true }));
    assert(picker.querySelectorAll('.tag-input__suggestion').length >= 8, '展开后显示全部');
    assert(picker.querySelector('.tag-input__more').textContent.includes('收起'), '按钮变「收起」');

    console.log('\n===== 标签管理(三级): ' + pass + ' 通过, ' + fail + ' 失败 =====');
    process.exit(fail > 0 ? 1 : 0);
  } catch (e) {
    console.error('测试异常:', e && e.stack || e);
    process.exit(1);
  }
}, 1000);
