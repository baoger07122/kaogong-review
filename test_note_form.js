/* 笔记表单：关联错题局部刷新与富文本保真专项测试 */
const { JSDOM } = require('jsdom');
const fs = require('fs');
const { marked } = require('marked');

const html = fs.readFileSync('index.html', 'utf8');
const dom = new JSDOM(html, {
  runScripts: 'dangerously',
  pretendToBeVisual: true,
  url: 'https://localhost/',
  beforeParse(w) {
    w.matchMedia = w.matchMedia || function () { return { matches: false, addListener() {}, removeListener() {}, addEventListener() {}, removeEventListener() {} }; };
    w.requestAnimationFrame = (cb) => setTimeout(cb, 0);
    w.cancelAnimationFrame = (id) => clearTimeout(id);
    w.getSelection = () => ({ rangeCount: 0, removeAllRanges() {}, addRange() {}, getRangeAt() { return { toString: () => '' }; }, isCollapsed: true });
    w.scrollTo = () => {};
    w.document.execCommand = () => true;
    w.marked = marked;
  }
});

let pass = 0, fail = 0;
function assert(cond, msg) {
  if (cond) { pass++; console.log('  ✓ ' + msg); }
  else { fail++; console.error('  ✗ ' + msg); }
}

setTimeout(async () => {
  const win = dom.window;
  const doc = win.document;
  const App = win.App;
  const wait = (ms) => new Promise(resolve => setTimeout(resolve, ms));
  try {
    App.Draft.clearForm('note');
    App.DB.getErrors = async () => [{ id: 'err1', question: '测试错题' }];
    App.DB.get = async () => null;
    App.DB.updateNote = async () => {};
    App.Components.actionSheet = async () => 'err1';

    const container = doc.getElementById('page-note-form');
    App.Pages.Notes.renderForm({ subject: '言语理解' });
    await wait(40);

    const title = container.querySelector('.note-title-input');
    const area = container.querySelector('.html-editor__area');
    const linkButton = Array.from(container.querySelectorAll('button')).find(btn => btn.textContent === '选择错题');
    assert(!!title && !!area && !!linkButton, '笔记表单、富文本编辑区和关联按钮均存在');

    title.value = '关联测试';
    title.dispatchEvent(new win.Event('input', { bubbles: true }));
    area.innerHTML = '<strong>开头加粗</strong><span style="color:red">颜色</span><p>正文</p>';
    area.dispatchEvent(new win.Event('input', { bubbles: true }));
    const originalArea = area;

    linkButton.dispatchEvent(new win.MouseEvent('click', { bubbles: true }));
    await wait(50);
    assert(container.querySelector('.html-editor__area') === originalArea, '关联错题只刷新关联区域，不销毁编辑器');
    assert(originalArea.innerHTML.includes('<strong>开头加粗</strong>') && originalArea.innerHTML.includes('颜色'), '关联错题后富文本格式和内容保持不变');
    assert(container.textContent.includes('关联错题 err1'), '关联错题列表已显示');

    const removeButton = Array.from(container.querySelectorAll('button')).find(btn => btn.textContent === '移除');
    removeButton.dispatchEvent(new win.MouseEvent('click', { bubbles: true }));
    await wait(20);
    assert(container.querySelector('.html-editor__area') === originalArea, '移除关联也不销毁编辑器');
    assert(originalArea.innerHTML.includes('<strong>开头加粗</strong>'), '移除关联后富文本仍保持');

    console.log('\n===== 笔记表单专项: ' + pass + ' 通过, ' + fail + ' 失败 =====');
    process.exit(fail > 0 ? 1 : 0);
  } catch (e) {
    console.error('测试异常:', e && e.stack || e);
    process.exit(1);
  }
}, 700);
