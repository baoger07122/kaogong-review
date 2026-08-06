/* 待办删除问题排查：fake-indexeddb 真实跑「新增 → 查询 → 删除」链路 */
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
  const win = dom.window, App = win.App;
  try {
    console.log('[1] DB 初始化 + 云同步包装（复现真机环境）');
    await App.DB.init();
    if (App.DB.wrapDB && App.Cloud && App.Cloud.wrapDB) {
      try { App.Cloud.wrapDB(); } catch (e) { console.log('  (wrapDB 跳过: ' + (e && e.message) + ')'); }
    }

    console.log('\n[2] 新增待办（addTodo 生成 id）');
    const t1 = await App.DB.addTodo({ text: '测试待办A' });
    const t2 = await App.DB.addTodo({ text: '测试待办B', note: '备注' });
    assert(!!t1 && !!t2 && !!t1.id && !!t2.id, '新增 2 条待办均有 id（' + t1.id + ' / ' + t2.id + '）');
    let todos = await App.DB.getTodos();
    assert(todos.length === 2, 'getTodos 返回 2 条');

    console.log('\n[3] 删除待办（App.DB.remove / removeTodo 路径）');
    await App.DB.remove('todos', t1.id);
    todos = await App.DB.getTodos();
    assert(todos.length === 1 && todos[0].id === t2.id, 'remove(todos, id) 删除成功（剩 1 条）');
    assert(todos[0].text === '测试待办B' && todos[0].note === '备注', '剩余待办数据完整（text/note 保留）');

    console.log('\n[4] 反复增删（新增后立即删除）');
    const t3 = await App.DB.addTodo({ text: '临时待办' });
    const t3id = t3.id;
    await App.DB.remove('todos', t3id);
    todos = await App.DB.getTodos();
    assert(todos.length === 1, '新增后立即删除成功（剩 1 条）');

    console.log('\n[5] 检查待办类型字段（typeKeyOf 依赖）');
    const t4 = await App.DB.addTodo({ text: '类型待办' });
    assert(!!t4.type, 'addTodo 默认 type 已填（' + t4.type + '）');
    await App.DB.remove('todos', t4.id);

    console.log('\n===== 待办增删排查: ' + pass + ' 通过, ' + fail + ' 失败 =====');
    if (fail > 0) { console.error('✗✗ 存在失败用例'); process.exit(1); }
    else { console.log('✓✓ 全部通过（核心增删链路正常，问题应在 UI 交互层）'); process.exit(0); }
  } catch (e) {
    console.error('测试异常:', e && e.stack || e);
    process.exit(1);
  }
}, 400);
