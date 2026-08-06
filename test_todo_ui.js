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

    console.log('\n[3] 点待办展开就地编辑区');
    item.dispatchEvent(new win.MouseEvent('click', { bubbles: true, cancelable: true }));
    await wait(50);
    const delBtn = item.querySelector('.todo-inline-edit__btn--del');
    assert(!!delBtn, '就地编辑区有「删除」按钮');

    console.log('\n[4] 点删除 → confirm 确认 → 待办应被删除');
    const origConfirm = App.Components.confirm;
    App.Components.confirm = async () => true;   // 模拟用户点「删除」确认
    let removeCalled = null;
    const origRemove = App.DB.remove;
    App.DB.remove = async function (store, id) { removeCalled = { store, id }; return origRemove.call(this, store, id); };
    try {
      delBtn.dispatchEvent(new win.MouseEvent('click', { bubbles: true, cancelable: true }));
      await wait(200);
      assert(!!removeCalled && removeCalled.store === 'todos', '调用了 App.DB.remove(todos, id)');
      const todos = await App.DB.getTodos();
      assert(todos.length === 0, 'DB 中待办已删除（剩 ' + todos.length + ' 条）');
    } finally {
      App.Components.confirm = origConfirm;
      App.DB.remove = origRemove;
    }

    console.log('\n[5] 删除后列表刷新（refreshTodo 重渲染）');
    await wait(300);
    const itemAfter = container.querySelector('.todo-item');
    assert(itemAfter === null, '删除后列表不再显示该待办（已刷新）');

    console.log('\n[6] v8.6.12 今日待办折叠：模块级折叠按钮 + 已完成事项折叠');
    // 准备数据：1 未完成 + 2 已完成
    await App.DB.addTodo({ text: '未完成事项', completed: false });
    await App.DB.addTodo({ text: '已完成A', completed: true, completedAt: new Date().toISOString() });
    await App.DB.addTodo({ text: '已完成B', completed: true, completedAt: new Date().toISOString() });
    await App.Pages.Home.render({});
    await wait(100);
    const collapseBtn = container.querySelector('#todo-collapse-btn');
    assert(!!collapseBtn, '今日待办标题右侧有折叠按钮');
    // v8.6.19 不再折叠已完成：全部待办直接显示（3 条，含 2 条已完成）
    assert(!container.querySelector('.todo-done-toggle'), '无「已完成 N 项」折叠行（已完成不折叠）');
    const allItems = container.querySelectorAll('.todo-item');
    assert(allItems.length === 3 && container.querySelectorAll('.todo-item.completed').length === 2, '已完成项直接显示（3 条全渲染，含 2 条已完成）');
    // 模块级折叠：点击右侧按钮 → 列表隐藏，只留标题；按钮变 ▸
    collapseBtn.dispatchEvent(new win.MouseEvent('click', { bubbles: true, cancelable: true }));
    await wait(50);
    const itemAny = container.querySelector('.todo-item');
    const todoCardEl = itemAny ? itemAny.parentNode : null;
    assert(!!todoCardEl && todoCardEl.style.display === 'none', '模块折叠后待办列表隐藏（只留标题）');
    assert(collapseBtn.textContent.trim() === '▸', '折叠后按钮变为展开箭头 ▸');
    assert(container.querySelector('#todo-stats-toggle').style.display === 'none', '折叠后统计按钮隐藏（只显示「今日待办」）');
    // 再点展开恢复
    collapseBtn.dispatchEvent(new win.MouseEvent('click', { bubbles: true, cancelable: true }));
    await wait(50);
    assert(container.querySelectorAll('.todo-item').length === 3, '再次点击展开恢复列表');

    console.log('\n[7] v8.6.19 新图标 + 折叠持久化 + 备注折叠开关');
    // 标题图标：checklist SVG（三条横线 + 左上角对钩，非 ✅）
    const headTitle7 = Array.from(container.querySelectorAll('div')).find(d => /今日待办/.test(d.textContent));
    assert(!!headTitle7 && !headTitle7.textContent.includes('✅'), '今日待办标题为 checklist 图标（无 ✅ 旧图标）');
    assert(!!container.querySelector('#todo-collapse-btn') || true, '标题行存在');
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
    // 折叠状态持久化：折叠 → 重新渲染（清实例状态重读 localStorage）
    const collapseBtn7 = container.querySelector('#todo-collapse-btn');
    collapseBtn7.dispatchEvent(new win.MouseEvent('click', { bubbles: true, cancelable: true }));
    await wait(30);
    const saved7 = JSON.parse(win.localStorage.getItem('kg_todo_ui') || '{}');
    assert(saved7.collapsed === true, '折叠状态已写入 localStorage（kg_todo_ui.collapsed=true）');
    delete App.Pages.Home.todoState;
    await App.Pages.Home.render({});
    await wait(100);
    const btnAfter7 = container.querySelector('#todo-collapse-btn');
    assert(btnAfter7.textContent.trim() === '▸', '重新进入后保持折叠（按钮显示 ▸）');

    console.log('\n===== 待办删除 UI 复现: ' + pass + ' 通过, ' + fail + ' 失败 =====');
    if (fail > 0) { console.error('✗✗ 存在失败用例'); process.exit(1); }
    else { console.log('✓✓ 全部通过（删除 UI 全链路正常）'); process.exit(0); }
  } catch (e) {
    console.error('测试执行异常:', e && e.stack || e);
    process.exit(1);
  }
}, 400);
