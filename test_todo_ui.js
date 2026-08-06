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
    // 已完成默认折叠：仅未完成项渲染为 todo-item，另有一行折叠行
    const doneToggle = container.querySelector('.todo-done-toggle');
    assert(!!doneToggle && doneToggle.textContent.includes('已完成 2 项'), '已完成折叠行存在（已完成 2 项）');
    const activeOnly = container.querySelectorAll('.todo-item');
    assert(activeOnly.length === 1 && !activeOnly[0].classList.contains('completed'), '已完成默认折叠：只显示未完成项（' + activeOnly.length + ' 条）');
    // 点击折叠行 → 展开已完成项
    doneToggle.dispatchEvent(new win.MouseEvent('click', { bubbles: true, cancelable: true }));
    await wait(200);
    const afterOpen = container.querySelectorAll('.todo-item');
    assert(afterOpen.length === 3 && !!container.querySelector('.todo-item.completed'), '点击折叠行展开已完成项（3 条全显示）');
    // 模块级折叠：点击右侧按钮 → 列表隐藏，只留标题；按钮变 ▸
    collapseBtn.dispatchEvent(new win.MouseEvent('click', { bubbles: true, cancelable: true }));
    await wait(50);
    const newToggle = container.querySelector('.todo-done-toggle');
    const todoCardEl = newToggle ? newToggle.parentNode : null;
    assert(!!todoCardEl && todoCardEl.style.display === 'none', '模块折叠后待办列表隐藏（只留标题）');
    assert(collapseBtn.textContent.trim() === '▸', '折叠后按钮变为展开箭头 ▸');
    assert(container.querySelector('#todo-stats-toggle').style.display === 'none', '折叠后统计按钮隐藏（只显示「今日待办」）');
    // 再点展开恢复
    collapseBtn.dispatchEvent(new win.MouseEvent('click', { bubbles: true, cancelable: true }));
    await wait(50);
    assert(!!container.querySelector('.todo-done-toggle') && container.querySelector('.todo-done-toggle').parentNode.style.display !== 'none', '再次点击展开恢复列表');

    console.log('\n===== 待办删除 UI 复现: ' + pass + ' 通过, ' + fail + ' 失败 =====');
    if (fail > 0) { console.error('✗✗ 存在失败用例'); process.exit(1); }
    else { console.log('✓✓ 全部通过（删除 UI 全链路正常）'); process.exit(0); }
  } catch (e) {
    console.error('测试执行异常:', e && e.stack || e);
    process.exit(1);
  }
}, 400);
