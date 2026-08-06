/* v8.6.6 备份功能专项：验证修复「自动备份包污染 keyvalue 导致备份文件递归膨胀、无法备份」
   用 fake-indexeddb 真实跑 App.DB 备份链路 */
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
    w.URL.createObjectURL = () => 'blob:fake';
    w.URL.revokeObjectURL = () => {};
  }
});
setTimeout(async () => {
  const win = dom.window, App = win.App;
  try {
    console.log('[1] 版本号');
    assert(App.VERSION === '8.6.16', 'App.VERSION === 8.6.16（当前 ' + App.VERSION + '）');

    console.log('\n[2] DB 初始化 + 塞数据（100 笔记含 base64 图片）');
    await App.DB.init();
    const now = Date.now();
    for (let i = 0; i < 100; i++) {
      await App.DB.addNote({ id: 'n' + i, subject: 's', title: '笔记' + i, content: '<p>内容' + i + '</p>', doodle: 'data:image/png;base64,' + 'A'.repeat(5000), updatedAt: new Date().toISOString() });
    }
    for (let i = 0; i < 10; i++) {
      await App.DB.addError({ id: 'e' + i, subject: 's', module: 'm', knowledgePoints: [], errorCause: 'c', question: 'q' + i, images: ['data:image/png;base64,' + 'B'.repeat(3000)] });
    }
    await App.DB.addTodo({ id: 't1', text: '待办' });
    await App.DB.addSticky({ id: 'st1', content: '便签', color: '#FFFBEB', pinned: false });

    console.log('\n[3] 模拟自动备份 5 次（完整包进 keyvalue）→ 验证备份文件不再递归膨胀');
    for (let i = 0; i < 5; i++) {
      const data = await App.DB.buildBackupData();
      await App.DB.kvSet('auto_backup_' + (now + i), { ts: now + i, data });
    }
    const kvAll = await App.DB.getAll('keyvalue');
    assert(kvAll.filter(r => r.key && r.key.startsWith('auto_backup_')).length === 5, 'keyvalue 内有 5 个自动备份包（模拟真实场景）');

    console.log('\n[4] buildBackupData：不再包含自动备份包（防递归膨胀）');
    const data = await App.DB.buildBackupData();
    const json = JSON.stringify(data);
    const kb = (json.length / 1024).toFixed(0);
    const keyArr = Array.isArray(data.keyvalue) ? data.keyvalue : [];
    assert(!keyArr.some(r => r.key && r.key.startsWith('auto_backup_')), '备份包 keyvalue 不含 auto_backup_*（修复递归膨胀）');
    assert(parseInt(kb, 10) < 5000, '备份文件大小受控（' + kb + ' KB < 5000 KB，修复前同场景 17MB）');
    assert(data.notes.length === 100 && data.errors.length === 10, '正常数据完整（100 笔记 + 10 错题）');
    assert(!!data.stickies && data.stickies.length === 1, '便签包含在备份中');

    console.log('\n[5] exportAll 导出成功');
    try {
      const d = await App.DB.exportAll();
      assert(d.notes.length === 100 && Array.isArray(d.keyvalue) && !d.keyvalue.some(r => r.key && r.key.startsWith('auto_backup_')), 'exportAll 成功且不含自动备份包');
    } catch (e) {
      assert(false, 'exportAll 不抛错（' + (e && e.message) + '）');
    }

    console.log('\n===== 备份专项: ' + pass + ' 通过, ' + fail + ' 失败 =====');
    if (fail > 0) { console.error('✗✗ 存在失败用例'); process.exit(1); }
    else { console.log('✓✓ 全部通过'); process.exit(0); }
  } catch (e) {
    console.error('测试执行异常:', e && e.stack || e);
    process.exit(1);
  }
}, 400);
