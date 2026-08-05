/* v8.5.5 彻底去块：toNoteHtml 迁移工具 + HTML 编辑器 专项测试 */
const { JSDOM } = require('jsdom');
const fs = require('fs');
const html = fs.readFileSync('index.html', 'utf8');
const { marked } = require('marked');

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
    w.document.execCommand = () => true;
    w.marked = marked;
  }
});
setTimeout(async () => {
  const win = dom.window, doc = win.document, App = win.App;
  try {
    console.log('[1] toNoteHtml：任意形态 → 完整 HTML');
    // 1.1 JSON 块数组 → HTML
    const h1 = App.Utils.toNoteHtml([
      { type: 'heading2', content: '标题', html: '标题' },
      { type: 'text', content: '加粗', html: '<b>加粗</b>' },
      { type: 'bulletList', content: '甲', html: '甲' },
      { type: 'bulletList', content: '乙', html: '乙' }
    ]);
    assert(!!h1 && h1.indexOf('<h2') >= 0 && h1.indexOf('<b>加粗</b>') >= 0, 'JSON 块数组 → HTML（h2/加粗）');
    assert((h1.match(/<ul/g) || []).length === 1 && (h1.match(/<li/g) || []).length === 2, '连续列表合并为一个 <ul>（2 项）');
    // 1.2 已是 HTML → 幂等原样
    const srcHtml = '<p>已有<b>格式</b></p><h2>标题</h2>';
    assert(App.Utils.toNoteHtml(srcHtml) === srcHtml, 'HTML 字符串幂等（原样返回不二次转换）');
    // 1.3 纯文本 → <p>（renderBlocks 输出带 md-preview-p class）
    const h3 = App.Utils.toNoteHtml('纯文本内容');
    assert(!!h3 && h3.indexOf('<p') === 0 && h3.indexOf('纯文本内容') >= 0, '纯文本 → <p>纯文本内容</p>（' + h3 + '）');
    // 1.4 旧 Markdown → HTML
    const md = '# 一级\n\n**加粗**\n\n- 甲\n- 乙';
    const h4 = App.Utils.toNoteHtml(md);
    assert(!!h4 && h4.indexOf('<h1') >= 0, '旧 MD 标题 → <h1>');
    assert(!!h4 && (h4.indexOf('<strong>') >= 0 || h4.indexOf('<b>') >= 0), '旧 MD 加粗 → <strong>/<b>');
    assert(!!h4 && h4.indexOf('<ul') >= 0, '旧 MD 列表 → <ul>');
    // 1.5 空 → ''
    assert(App.Utils.toNoteHtml('') === '' && App.Utils.toNoteHtml(null) === '' && App.Utils.toNoteHtml([]) === '', '空值 → 空串');

    console.log('\n[2] htmlEditor 组件（单连续富文本，HTML 直通）');
    const holder = doc.createElement('div'); doc.body.appendChild(holder);
    const he = App.Components.htmlEditor('<p>第一段</p><p>第二段</p>', { placeholder: false });
    assert(!!he.element.querySelector('.html-editor__area'), '编辑区存在');
    assert(he.getHtml() === '<p>第一段</p><p>第二段</p>', 'getHtml 直通（格式保真，无二次转换）');
    // blockFormat：可编程选区（每次点击前更新指向当前段落）→ 点 H2 → h2；点正文 → p
    const area2 = he.area;
    let programRange = null;
    const origSel2 = win.getSelection;
    win.getSelection = () => ({ rangeCount: programRange ? 1 : 0, isCollapsed: false, anchorNode: programRange ? programRange.startContainer : null, startContainer: programRange ? programRange.startContainer : null, startOffset: 0, getRangeAt: () => programRange, removeAllRanges() {}, addRange() {} });
    try {
      const btns = Array.from(he.element.querySelectorAll('.notion-tool-btn'));
      const h2Btn = btns.find(b => b.textContent === 'H2');
      assert(!!h2Btn, '工具栏有 H2 按钮');
      programRange = doc.createRange();
      programRange.selectNodeContents(area2.querySelector('p'));
      h2Btn.dispatchEvent(new win.MouseEvent('click', { bubbles: true, cancelable: true }));
      const h2 = area2.querySelector('h2');
      assert(!!h2 && h2.textContent === '第一段', '段落 → h2 转换成功');
      // 正文按钮：重建选区指向新 h2 → p
      const pBtn = btns.find(b => b.textContent === '正文');
      programRange = doc.createRange();
      programRange.selectNodeContents(h2);
      pBtn.dispatchEvent(new win.MouseEvent('click', { bubbles: true, cancelable: true }));
      assert(!!area2.querySelector('p') && area2.querySelector('p').textContent === '第一段', 'h2 → 正文 p 转换成功');
    } finally { win.getSelection = origSel2; }
    // setHtml/getHtml 往返
    he.setHtml('<b>加粗内容</b>');
    assert(he.getHtml() === '<b>加粗内容</b>', 'setHtml/getHtml 往返（HTML 直通）');
    holder.remove();

    console.log('\n总计: ' + pass + ' 通过, ' + fail + ' 失败');
    if (fail > 0) { console.error('✗✗ 存在失败用例'); process.exit(1); }
    else { console.log('✓✓ 全部通过'); process.exit(0); }
  } catch (e) {
    console.error('测试执行异常:', e && e.stack || e);
    process.exit(1);
  }
}, 300);
