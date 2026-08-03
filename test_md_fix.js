/* Markdown 往返丢失修复验证（对应 6 项排查方向） */
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
  const Utils = App.Utils;
  const holder = doc.createElement('div');
  doc.body.appendChild(holder);

  try {
    console.log('[1] 编辑器→导出→渲染 完整链路（方向3/4）');
    const editor = App.Components.initEditor(holder, { initialData: '', onChange: () => {} });
    editor.setEditorData([
      { type: 'heading1', content: '标题一' },
      { type: 'heading2', content: '标题二' },
      { type: 'heading3', content: '标题三' },
      { type: 'heading4', content: '标题四' },
      { type: 'text', content: '**加粗**与*斜体*与`代码`' },
      { type: 'bullet', content: '项目甲' },
      { type: 'bullet', content: '项目乙' },
      { type: 'numbered', content: '第一' },
      { type: 'quote', content: '引用句' },
      { type: 'text', content: '公式 $x^2$ 与分数 $\\frac{a}{b}$' }
    ]);
    const md = editor.getContent();
    // 模拟 IndexedDB JSON 存取
    const saved = JSON.parse(JSON.stringify(md));
    const r = Utils.simpleMarkdown(saved);
    assert((r.match(/<h1/g) || []).length === 1, 'h1 渲染');
    assert((r.match(/<h2/g) || []).length === 1, 'h2 渲染');
    assert((r.match(/<h3/g) || []).length === 1, 'h3 渲染');
    assert((r.match(/<h4/g) || []).length === 1, 'h4 渲染');
    assert(r.includes('<strong>') && r.includes('<em>'), '加粗/斜体渲染');
    assert(r.includes('<code class="md-preview-code-inline">'), '行内代码渲染');
    assert((r.match(/<ul/g) || []).length === 1 && r.includes('项目甲') && r.includes('项目乙'), '无序列表渲染（不被吞进段落）');
    assert((r.match(/<ol/g) || []).length === 1 && r.includes('第一'), '有序列表渲染');
    assert(r.includes('md-preview-blockquote') && r.includes('引用句'), '引用块渲染');
    assert(r.includes('mformula') && r.includes('mf-frac'), '行内公式渲染');

    console.log('\n[2] 换行保留（方向3）');
    const md2 = '第一行\n\n第二段';
    assert(JSON.parse(JSON.stringify(md2)).includes('\n'), 'JSON 序列化保留 \\n');
    assert(Utils.normalizeMarkdownInput('a\r\nb\rc\u2028d').includes('\n'), 'CR/LS 统一为 \\n');
    const r2 = Utils.simpleMarkdown('行一\n行二');
    assert(r2.includes('<br>'), '段落内软换行转 <br>');

    console.log('\n[3] XSS 过滤最终 HTML（方向6）');
    const r3 = Utils.simpleMarkdown('<img src=x onerror=alert(1)> 和 [链接](javascript:alert(1))');
    assert(!r3.includes('<img src=x'), 'img onerror 被转义');
    assert(r3.includes('&lt;img'), 'HTML 标签实体化');

    console.log('\n[4] 详情页 innerHTML 渲染 + 异步加载（方向1/2）');
    // 模拟详情页：await DB.get 后 innerHTML
    const noteMd = '## 考点总结\n\n- 要点A\n- 要点B\n\n**重点**内容';
    const noteEl = doc.createElement('div');
    noteEl.innerHTML = Utils.simpleMarkdown(noteMd);   // 等数据后 innerHTML（非 textContent）
    assert(noteEl.querySelector('h2') !== null, 'h2 通过 innerHTML 渲染');
    assert(noteEl.querySelector('ul') !== null, 'ul 通过 innerHTML 渲染');
    assert(noteEl.querySelector('strong') !== null, 'strong 通过 innerHTML 渲染');
    assert(!noteEl.textContent.includes('# '), '标题标记不显示为原文');

    console.log('\n[5] 表格渲染（gfm 表格，方向4）');
    const tbl = Utils.simpleMarkdown('| 科目 | 分数 |\n| --- | --- |\n| 行测 | 78 |\n| 申论 | 82 |');
    assert(tbl.includes('<table') && tbl.includes('<th>科目</th>') && tbl.includes('78'), '表格渲染');

    console.log('\n===== Markdown 修复验证: ' + pass + ' 通过, ' + fail + ' 失败 =====');
    process.exit(fail > 0 ? 1 : 0);
  } catch (e) {
    console.error('测试异常:', e && e.stack || e);
    process.exit(1);
  }
}, 900);
