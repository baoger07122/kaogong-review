/* 待办删除 UI 复现：渲染首页待办区块 → 新增 → 就地编辑删除 全流程 */
const { JSDOM } = require('jsdom');
const fs = require('fs');
const html = fs.readFileSync('index.html', 'utf8');
const { indexedDB, IDBKeyRange } = require('fake-indexeddb');

let pass = 0, fail = 0;
function assert(cond, msg) {
  if (cond) { pass++; console.log('  ✓ ' + msg); }
  else { fail++; console.log('  ✗ ' + msg); }
}

const dom = new JSDOM(html, {
  runScripts: 'dangerously', pretendToBeVisual: true, url: 'https://localhost/',
  beforeParse(w) {
    w.indexedDB = indexedDB;
    w.IDBKeyRange = IDBKeyRange;
    w.matchMedia = w.matchMedia || function () { return { matches: false, addListener() {}, removeListener() {}, addEventListener() {}, removeEventListener() {}, dispatchEvent() { return false; } }; };
    w.requestAnimationFrame = (cb) => setTimeout(cb, 0);
    w.cancelAnimationFrame = (id) => clearTimeout(id);
    w.getSelection = () => ({ rangeCount: 0 });
    w.scrollTo = () => {};
    w.document.execCommand = () => true;
  }
});
setTimeout(async () => {
  const win = dom.window, doc = win.document, App = win.App;
  const wait = (ms) => new Promise(r => setTimeout(r, ms));
  try {
    await App.DB.init();
    await App.DB.clearStore('todos');
    const container = doc.getElementById('page-home');
    doc.body.appendChild(container);

    console.log('[1] 渲染首页待办区块（空列表）');
    await App.Pages.Home.render({});
    await wait(100);
    assert(container.querySelector('.todo-item') === null, '空列表无待办项');

    console.log('\n[2] 新增待办（addTodo）→ 重新渲染出现');
    await App.DB.addTodo({ text: '新增加的待办', note: '备注内容' });
    await App.Pages.Home.render({});
    await wait(100);
    const item = container.querySelector('.todo-item');
    assert(!!item && item.textContent.includes('新增加的待办'), '新增待办出现在列表');

    console.log('\n[3] 点待办展开就地编辑区（v8.12.x：标题输入 + 备注输入行，失焦/回车保存，无删除按钮）');
    item.dispatchEvent(new win.MouseEvent('click', { bubbles: true, cancelable: true }));
    await wait(50);
    const editWrap3 = item.querySelector('.todo-inline-edit--apple');
    assert(!!editWrap3, '就地编辑区展开');
    assert(!!editWrap3.querySelector('.todo-inline-edit--apple__title'), '标题输入框存在（光标闪烁自动聚焦）');
    assert(!!editWrap3.querySelector('.todo-inline-edit--apple__note'), '备注输入行存在');
    assert(!item.querySelector('.todo-inline-edit__btn--del'), 'v8.12.x 就地编辑无删除按钮（删除在编辑弹窗）');
    // 回车保存（标题改名）
    const tInput3 = editWrap3.querySelector('.todo-inline-edit--apple__title');
    tInput3.value = '改名后的待办';
    tInput3.dispatchEvent(new win.KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }));
    await wait(120);
    assert(container.textContent.includes('改名后的待办'), '回车保存标题成功');

    console.log('\n[4] 就地编辑保存备注（v8.12.17 回退 8.6.41：保存后备注以 📝 折叠展示）');
    const item4 = container.querySelector('.todo-item');
    item4.dispatchEvent(new win.MouseEvent('click', { bubbles: true, cancelable: true }));
    await wait(50);
    const wrap4 = item4.querySelector('.todo-inline-edit--apple');
    const nInput4 = wrap4.querySelector('.todo-inline-edit--apple__note');
    nInput4.value = '这是新备注';
    // jsdom 下 blur 不转移焦点，用标题回车保存（save 读标题+备注）
    wrap4.querySelector('.todo-inline-edit--apple__title').dispatchEvent(new win.KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }));
    await wait(120);
    const tog4 = item4.querySelector('.todo-note__toggle');
    assert(!!tog4 && tog4.textContent.includes('📝'), '保存后备注以 📝 折叠开关展示');
    const note4 = item4.querySelector('.todo-note');
    assert(!!note4 && !note4.classList.contains('is-open'), '备注默认折叠');
    tog4.dispatchEvent(new win.MouseEvent('click', { bubbles: true, cancelable: true }));
    await wait(30);
    assert(item4.querySelector('.todo-note').classList.contains('is-open'), '点击 📝 展开备注');
    assert(item4.querySelector('.todo-note__body').textContent === '这是新备注', '备注内容正确');

    console.log('\n[5] 编辑保存后列表刷新（备注折叠态保持）');
    await wait(300);
    const itemAfter = container.querySelector('.todo-item');
    assert(!!itemAfter && itemAfter.textContent.includes('改名后的待办'), '编辑后列表正常显示（改名保留）');
    assert(!!itemAfter.querySelector('.todo-note__toggle'), '编辑保存后备注折叠开关保留');

    console.log('\n[6] v8.12.4 已移除折叠按钮：今日待办直出全部（含已完成）');
    // 准备数据：1 未完成 + 2 已完成
    await App.DB.addTodo({ text: '未完成事项', completed: false });
    await App.DB.addTodo({ text: '已完成A', completed: true, completedAt: new Date().toISOString() });
    await App.DB.addTodo({ text: '已完成B', completed: true, completedAt: new Date().toISOString() });
    await App.Pages.Home.render({});
    await wait(100);
    const collapseBtn = container.querySelector('#todo-collapse-btn');
    assert(!collapseBtn, 'v8.12.4 今日待办折叠按钮已移除');
    // v8.6.19 不再折叠已完成：全部待办直接显示（3 条，含 2 条已完成）
    assert(!container.querySelector('.todo-done-toggle'), '无「已完成 N 项」折叠行（已完成不折叠）');
    const allItems = container.querySelectorAll('.todo-item');
    assert(allItems.length >= 3 assert(allItems.length === 3 && container.querySelectorAll('.todo-item.completed').length === 2, '已完成项直接显示（3 条全渲染，含 2 条已完成）');assert(allItems.length === 3 && container.querySelectorAll('.todo-item.completed').length === 2, '已完成项直接显示（3 条全渲染，含 2 条已完成）'); container.querySelectorAll('.todo-item.completed').length === 2, '已完成项直接显示（>=3 条含 2 条已完成）');
    assert(!container.querySelector('#todo-stats-toggle'), 'v8.6.37 已去除统计按钮');

    console.log('\n[7] checklist 图标 + 备注折叠开关（v8.12.17 回退 8.6.41 展示）');
    const headTitle7 = Array.from(container.querySelectorAll('div')).find(d => /今日待办/.test(d.textContent));
    assert(!!headTitle7 && !headTitle7.textContent.includes('✅'), '今日待办标题为 checklist 图标（无 ✅ 旧图标）');
    // 备注折叠：准备一条带备注的待办
    await App.DB.addTodo({ text: '带备注的待办', note: '这是备注内容', completed: false });
    await App.Pages.Home.render({});
    await wait(100);
    const noteToggle7 = container.querySelector('.todo-note__toggle');
    assert(!!noteToggle7 && !noteToggle7.textContent.includes('备注'), '备注折叠开关无「备注」文字（只有图标+箭头）');
    const noteBody7 = container.querySelector('.todo-note');
    assert(!!noteBody7 && !noteBody7.classList.contains('is-open'), '备注默认折叠（is-open 未加）');
    noteToggle7.dispatchEvent(new win.MouseEvent('click', { bubbles: true, cancelable: true }));
    await wait(30);
    assert(noteBody7.classList.contains('is-open'), '点击备注开关展开备注');

    console.log('\n[8] v8.11.3+ 类型/日期行不挂载（新增走弹窗），防覆盖 CSS 保留');
    assert(!container.querySelector('.todo-type-row') && !container.querySelector('.todo-date-row'), 'v8.11.3 类型/日期筛选行不再挂载（走「＋新增」弹窗）');
    const built28 = fs.readFileSync('index.html', 'utf8');
    assert(built28.includes('.todo-type-row, .todo-date-row') && built28.includes('display: flex !important'), 'CSS !important 防覆盖规则仍注入');
    assert(built28.includes('todo-note__toggle') && built28.includes('.todo-note.is-open'), 'v8.12.17 备注折叠 CSS 已回退（📝 开关 + is-open）');

    console.log('\n[9] v8.6.37 未来日期待办不出现在今日 + 统计页新增科目标签');
    // 造一条未来日期待办 → 今日列表不应显示
    const futureIso = new Date(Date.now() + 2 * 24 * 60 * 60 * 1000).toISOString();
    await App.DB.addTodo({ text: 'FUTURE_TODO_TEST', type: 'ziliao', completed: false, createdAt: futureIso });
    delete App.Pages.Home.todoState;
    await App.Pages.Home.render({});
    await wait(100);
    assert(!container.textContent.includes('FUTURE_TODO_TEST'), '未来日期待办不显示在今日列表');
    // 统计页渲染
    App.Router.navigate('study-stats');
    await wait(100);
    const statsContainer = doc.getElementById('page-study-stats');
    assert(!!statsContainer && statsContainer.querySelectorAll('[class*=study-cal]').length >= 1, '统计页日历渲染');
    const built37 = fs.readFileSync('index.html', 'utf8');
    assert(built37.includes('ST_SUBJECTS') && built37.includes("'shenlun'"), 'v8.6.37 统计页新增待办弹窗含 6 科目标签');

    console.log('\n===== 待办删除 UI 复现: ' + pass + ' 通过, ' + fail + ' 失败 =====');
    if (fail > 0) { console.error('✗✗ 存在失败用例'); process.exit(1); }
    else { console.log('✓✓ 全部通过（删除 UI 全链路正常）'); process.exit(0); }
  } catch (e) {
    console.error('测试执行异常:', e && e.stack || e);
    process.exit(1);
  }
}, 400);
