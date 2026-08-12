/* v8.4.0 待办科目分类 + 统计 + 信息图标 + 学习统计新建 + 错题卡片 专项测试 */
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
    w.prompt = () => null;
    w.confirm = () => true;
    w.FileReader = class { readAsDataURL(f) { const s = this; setTimeout(() => { s.result = 'data:image/png;base64,AAAA'; s.onload && s.onload(); }, 10); } readAsText() {} };
  }
});

setTimeout(async () => {
  const win = dom.window, doc = win.document, App = win.App;

  const dbStore = {};
  const today = new Date();
  const pad2 = (n) => String(n).padStart(2, '0');
  const todayISO = today.toISOString();
  const oldISO = new Date(today.getTime() - 3 * 86400000).toISOString();

  if (App.DB) {
    App.DB.get = async () => null;
    App.DB.getErrors = async () => [];
    App.DB.getNotes = async () => [];
    App.DB.getStats = async () => ({ subjectStats: {}, totalErrors: 0, unmasteredErrors: 0 });
    App.DB.getReviewQueue = async () => [];
    App.DB.getTodos = async () => Object.values(dbStore.todos || {}).sort((a, b) => {
      if (a.completed !== b.completed) return a.completed ? 1 : -1;
      return new Date(b.createdAt) - new Date(a.createdAt);
    });
    App.DB.addTodo = async (t) => { t.id = 't' + Math.random().toString(36).slice(2, 8); if (!dbStore.todos) dbStore.todos = {}; dbStore.todos[t.id] = t; return t; };
    App.DB.updateTodo = async (t) => { if (dbStore.todos && dbStore.todos[t.id]) dbStore.todos[t.id] = t; };
    App.DB.remove = async (table, id) => { if (dbStore.todos) delete dbStore.todos[id]; };
    App.DB.kvSet = async () => {};
    App.DB.kvGet = async () => null;
  }
  App.Components.confirm = async () => true;
  App.Components.toast = () => {};

  try {
    console.log('[1] 今日待办：科目分类');
    const page = doc.getElementById('page-home');
    await App.Pages.Home.render.call(App.Pages.Home, {});
    await new Promise(r => setTimeout(r, 300));
    // v8.11.3+ 类型快捷栏不挂载：科目分类在「＋新增」弹窗内（7 个单字）
    const addBtn840 = page.querySelector('#todo-add-btn');
    assert(!!addBtn840, '今日待办「＋新增」按钮存在');
    addBtn840.dispatchEvent(new win.MouseEvent('click', { bubbles: true, cancelable: true }));
    await new Promise(r => setTimeout(r, 120));
    const typeChips = Array.from(doc.querySelectorAll('.todo-modal__chips span, .todo-modal__chips div'));
    const labels = typeChips.map(c => (c.textContent || '').trim());
    const expects = ['言', '资', '判', '数', '常', '政', '申'];
    assert(typeChips.length === 7, '新增弹窗 7 个科目分类');
    expects.forEach(e => assert(labels.some(l => l.includes(e)), '包含「' + e + '」分类'));
    // 关闭弹窗（恢复页面状态，供后续段使用）
    const ov840 = doc.querySelector('.todo-modal-overlay');
    if (ov840) ov840.remove();

    console.log('\n[2] 右侧统计只统计今日');
    // 造数据：今日 2 个（1 完成）+ 昨天 3 个
    dbStore.todos = {};
    await App.DB.addTodo({ text: '今日1', type: 'yanyu', completed: true, createdAt: todayISO });
    await App.DB.addTodo({ text: '今日2', type: 'ziliao', completed: false, createdAt: todayISO });
    await App.DB.addTodo({ text: '昨日1', type: 'panduan', completed: true, createdAt: oldISO });
    await App.DB.addTodo({ text: '昨日2', type: 'shuliang', completed: true, createdAt: oldISO });
    await App.DB.addTodo({ text: '昨日3', type: 'changshi', completed: false, createdAt: oldISO });
    await App.Pages.Home.render.call(App.Pages.Home, {});
    await new Promise(r => setTimeout(r, 300));
    const cntText = page.querySelector('#todo-count-text');
    assert(!cntText, 'v8.12.13 标题区统计数字已移除');
    assert(page.querySelectorAll('.todo-item').length === 2, '今日待办 2 条（不含昨天 3 条）');

    console.log('\n[3] 点击待办就地编辑（标题+备注输入，v8.12.x；原 ⓘ 信息面板已并入弹窗）');
    // 今日待办列表应有 2 个 item
    const todoItems = page.querySelectorAll('.todo-item');
    assert(todoItems.length === 2, '今日待办 2 条（已完成下沉在后）');
    assert(page.querySelectorAll('.todo-info-btn').length === 0, 'v8.12.13 ⓘ 信息按钮已移除（编辑走弹窗/就地编辑）');
    // 点击第一项 → 就地编辑区（标题 + 备注输入）
    const firstTodo = todoItems[0];
    firstTodo.dispatchEvent(new win.MouseEvent('click', { bubbles: true, cancelable: true }));
    await new Promise(r => setTimeout(r, 80));
    const ewrap3 = firstTodo.querySelector('.todo-inline-edit--apple');
    assert(!!ewrap3, '就地编辑区展开');
    assert(!!ewrap3.querySelector('.todo-inline-edit--apple__title'), '标题输入框存在');
    assert(!!ewrap3.querySelector('.todo-inline-edit--apple__note'), '备注输入行存在');
    // 关闭编辑（Escape）
    ewrap3.querySelector('.todo-inline-edit--apple__title').dispatchEvent(new win.KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true }));
    await new Promise(r => setTimeout(r, 40));

    console.log('\n[4] 已完成事项默认移到最下方');
    // 检查 item 顺序：未完成在前，已完成在后
    const texts = Array.from(page.querySelectorAll('.todo-title')).map(t => t.textContent);
    const doneIdx = texts.findIndex(t => t.includes('今日1'));
    const pendingIdx = texts.findIndex(t => t.includes('今日2'));
    assert(pendingIdx < doneIdx, '未完成在前、已完成在后');

    console.log('\n[5] 学习统计页：点击日期新建待办');
    const statsPage = doc.getElementById('page-study-stats');
    await App.Pages.StudyStats.render.call(App.Pages.StudyStats, {});
    await new Promise(r => setTimeout(r, 200));
    const cells = statsPage.querySelectorAll('.study-cal__cell:not(.study-cal__cell--blank)');
    assert(cells.length >= 28, '日历格子渲染');
    // 有数据日期格子（今日有 2 条）
    const todayCell = Array.from(cells).find(c => c.classList.contains('is-today'));
    assert(!!todayCell, '今日格子高亮');
    assert(todayCell.querySelectorAll('.study-cal__todo').length === 2, '今日格子显示 2 条待办');
    // prompt 返回文本 → 点击空白处新建
    const origPrompt = App.Components.prompt;
    let prompted = false;
    App.Components.prompt = async () => { prompted = true; return '新待办'; };
    const before = Object.keys(dbStore.todos).length;
    todayCell.dispatchEvent(new win.MouseEvent('click', { bubbles: true }));
    await new Promise(r => setTimeout(r, 200));
    assert(prompted === true, '点击日期弹出输入框');
    assert(Object.keys(dbStore.todos).length === before + 1, '新建待办成功');
    const newTodo = Object.values(dbStore.todos).find(t => t.text === '新待办');
    assert(!!newTodo, '新待办内容正确');
    App.Components.prompt = origPrompt;

    console.log('\n[6] 错题卡片：考点+错因同行，日期末行');
    const card = App.Components.galleryErrorCard({
      knowledgePoints: ['考点A', '考点B'], errorCause: '错因X', question: '题',
      status: '未掌握', createdAt: new Date().toISOString()
    }, () => {});
    const tagRow = card.querySelector('.error-gallery-card__tagrow');
    assert(!!tagRow, '标签行存在');
    assert(tagRow.querySelectorAll('.tag').length === 3, '考点2个+错因1个同行');
    const tags = Array.from(tagRow.querySelectorAll('.tag'));
    assert(tags[0].textContent === '考点A' && tags[1].textContent === '考点B' && tags[2].textContent === '错因X', '考点在前错因在后');
    const dateEl = card.querySelector('.error-gallery-card__date');
    assert(!!dateEl, '日期元素存在');
    const children = Array.from(card.children);
    const dateIdx = children.indexOf(dateEl);
    assert(dateIdx === children.length - 1, '日期在最后一行');
    // 挖坑点在日期之前
    if (card.querySelector('.error-gallery-card__pitfall')) {
      assert(children.indexOf(card.querySelector('.error-gallery-card__pitfall')) < dateIdx, '挖坑点在日期前');
    }

    console.log('\n===== v8.4.0 专项: ' + pass + ' 通过, ' + fail + ' 失败 =====');
    process.exit(fail > 0 ? 1 : 0);
  } catch (e) {
    console.error('测试异常:', e && e.stack || e);
    process.exit(1);
  }
}, 1000);
