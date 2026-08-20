/* 云同步队列专项测试：连续保存同一条记录只上传最后一次，且不重复创建防抖定时器 */
const { JSDOM } = require('jsdom');
const fs = require('fs');
const html = fs.readFileSync('index.html', 'utf8');
const { indexedDB, IDBKeyRange } = require('fake-indexeddb');

let pass = 0, fail = 0;
function assert(cond, msg) {
  if (cond) { pass++; console.log('  ✓ ' + msg); }
  else { fail++; console.log('  ✗ ' + msg); }
}

const calls = [];
const dom = new JSDOM(html, {
  runScripts: 'dangerously', pretendToBeVisual: true, url: 'https://localhost/',
  beforeParse(w) {
    w.indexedDB = indexedDB;
    w.IDBKeyRange = IDBKeyRange;
    w.matchMedia = w.matchMedia || function () { return { matches: false, addListener() {}, removeListener() {}, addEventListener() {}, removeEventListener() {} }; };
    w.requestAnimationFrame = (cb) => setTimeout(cb, 0);
    w.cancelAnimationFrame = (id) => clearTimeout(id);
    w.getSelection = () => ({ rangeCount: 0 });
    w.scrollTo = () => {};
    w.document.execCommand = () => true;
    w.fetch = async (url, options) => {
      calls.push({ url: String(url), options: options || {} });
      return { ok: true, status: 200, json: async () => ({}) };
    };
  }
});

setTimeout(async () => {
  const win = dom.window;
  try {
    await win.App.DB.init();
    await win.App.DB.put('todos', { id: 'keep-before-import', text: '导入前数据' });
    let importRejected = false;
    try {
      await win.App.DB.importAll({
        version: 1,
        errors: [{}], notes: [], exams: [], todos: [], subjectReviews: [],
        keyvalue: [], words: [], stickies: []
      });
    } catch (e) {
      importRejected = true;
    }
    const preserved = await win.App.DB.get('todos', 'keep-before-import');
    assert(importRejected, '无效记录会拒绝导入');
    assert(preserved && preserved.text === '导入前数据', '导入失败后旧数据仍然保留');

    win.localStorage.setItem('kaogong_cloud_token', 'queue-test-token');
    win.App.Cloud.init();
    calls.length = 0;

    const id = 'queue-test-record';
    await win.App.DB.put('todos', { id, text: '第一次保存' });
    await win.App.DB.put('todos', { id, text: '第二次保存' });
    await win.App.DB.put('todos', { id, text: '最终保存' });
    await new Promise(resolve => setTimeout(resolve, 800));

    const uploads = calls.filter(c => c.url === '/api/todos');
    assert(uploads.length === 1, '同一记录连续保存只产生 1 次上传请求');
    assert(uploads[0] && JSON.parse(uploads[0].options.body).text === '最终保存', '上传内容为最后一次保存的数据');

    console.log('\n===== 云同步队列: ' + pass + ' 通过, ' + fail + ' 失败 =====');
    dom.window.close();
    process.exit(fail ? 1 : 0);
  } catch (e) {
    console.error('测试异常:', e && e.stack || e);
    dom.window.close();
    process.exit(1);
  }
}, 400);
