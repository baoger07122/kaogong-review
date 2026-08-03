/* v8.3.8 综合验证：图片置顶/错因标签/行距/下键导航/本行换行/缩进图标/h4渲染 */
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
  }
});

setTimeout(async () => {
  const win = dom.window, doc = win.document, App = win.App;
  if (App.DB) {
    App.DB.get = async (t, id) => {
      if (t === 'errors') return { id, subject: '言语理解', module: '逻辑填空', knowledgePoints: ['语境分析'], errorCause: '词义偏差', question: '测试题干', image: 'data:image/png;base64,AAAA', status: '未掌握', createdAt: new Date().toISOString() };
      return null;
    };
    App.DB.getErrors = async () => [];
    App.DB.getNotes = async () => [];
  }
  App.Components.confirm = async () => true;
  App.Components.toast = () => {};

  try {
    console.log('[1] 详情页图片位于题目上方');
    const page = doc.getElementById('page-error-detail');
    await App.Pages.Errors.renderDetail.call(App.Pages.Errors, { id: 'e1' });
    await new Promise(r => setTimeout(r, 100));
    const imgEl = page.querySelector('.error-detail-image');
    const qEl = Array.from(page.querySelectorAll('div')).find(d => d.textContent === '测试题干');
    assert(!!imgEl, '详情页展示图片');
    assert(!!qEl, '题干存在');
    if (imgEl && qEl) {
      const imgPos = imgEl.compareDocumentPosition(qEl);
      assert((imgPos & win.Node.DOCUMENT_POSITION_FOLLOWING) !== 0, '图片在题干之前（上方）');
    }

    console.log('\n[2] 画廊卡片：错因标签展示、无掌握标签、图片置顶');
    const card = App.Components.galleryErrorCard({
      knowledgePoints: ['语境分析', '主体排除'],
      errorCause: '词义偏差',
      question: '测试题',
      image: 'data:image/png;base64,AAAA',
      status: '未掌握',
      createdAt: new Date().toISOString()
    }, () => {});
    assert(!!card.querySelector('.error-gallery-card__img'), '卡片展示图片');
    const tagRow = card.querySelector('.error-gallery-card__tagrow');
    assert(!!tagRow, '考点+错因标签行存在');
    assert(tagRow.textContent.includes('词义偏差'), '错因标签内容正确');
    assert(!card.textContent.includes('未掌握') && !card.textContent.includes('已掌握'), '不显示掌握状态标签');
    // 考点在前、错因在后（同行）
    const tagTags = Array.from(tagRow.querySelectorAll('.tag'));
    const kpIdx = tagTags.findIndex(t => t.textContent === '语境分析');
    const causeIdx = tagTags.findIndex(t => t.textContent === '词义偏差');
    assert(kpIdx >= 0 && causeIdx >= 0 && kpIdx < causeIdx, '考点在前、错因在后');

    console.log('\n[3] 编辑器：下键切换下一行');
    const holder = doc.createElement('div');
    doc.body.appendChild(holder);
    const editor = App.Components.initEditor(holder, { initialData: '第一行\n第二行', onChange: () => {} });
    await new Promise(r => setTimeout(r, 50));
    const wrap = editor.element;
    const editables = wrap.querySelectorAll('.notion-editable');
    assert(editables.length >= 2, '有两个可编辑块');
    // jsdom 不跟踪 contenteditable 的真实焦点；验证 keydown handler 拦截了事件（preventDefault）
    const first = editables[0];
    const ev = new win.KeyboardEvent('keydown', { key: 'ArrowDown', bubbles: true, cancelable: true });
    first.dispatchEvent(ev);
    assert(ev.defaultPrevented === true, '下键被拦截（触发跳块逻辑）');
    // 上键
    const ev2 = new win.KeyboardEvent('keydown', { key: 'ArrowUp', bubbles: true, cancelable: true });
    editables[1].dispatchEvent(ev2);
    assert(ev2.defaultPrevented === true, '上键被拦截（触发跳块逻辑）');
    // 事件在块内中部（模拟有选区、光标不在边界）时不应拦截
    // （jsdom 无真实选区，rangeCount=0 时按实现会跳块——此处验证默认行为不拦截的补充：
    //  通过构造 rangeCount>0 的 mock 确认中部不跳）
    const mockSel = {
      rangeCount: 1,
      getRangeAt: () => ({ startOffset: 1 })
    };
    const origSel = win.getSelection;
    win.getSelection = () => mockSel;
    const ev3 = new win.KeyboardEvent('keydown', { key: 'ArrowDown', bubbles: true, cancelable: true });
    first.dispatchEvent(ev3);
    win.getSelection = origSel;
    assert(ev3.defaultPrevented === false, '光标在块中时下键不拦截（默认行内移动）');

    console.log('\n[4] 格式栏：本行换行按钮 + 缩进图标区分');
    const toolbar = wrap.querySelector('.notion-toolbar');
    assert(!!toolbar, '格式栏存在');
    // 缩进按钮（SVG）
    const svgBtns = toolbar.querySelectorAll('.notion-tool-btn--svg');
    assert(svgBtns.length >= 3, '有 3 个以上 SVG 按钮（缩进/缩出/换行）');
    const titles = Array.from(toolbar.querySelectorAll('button')).map(b => b.title);
    assert(titles.includes('增加缩进'), '增加缩进按钮存在');
    assert(titles.includes('减少缩进（后退）'), '减少缩进按钮存在');
    assert(titles.includes('本行换行（不新建段落）'), '本行换行按钮存在');
    // 缩进与缩出图标不同
    const indentBtn = toolbar.querySelector('button[title="增加缩进"]');
    const outdentBtn = toolbar.querySelector('button[title="减少缩进（后退）"]');
    assert(!!indentBtn && !!outdentBtn, '缩进/缩出按钮都存在');
    if (indentBtn && outdentBtn) {
      assert(indentBtn.innerHTML !== outdentBtn.innerHTML, '两个图标 SVG 不同（可区分）');
      assert(indentBtn.innerHTML.includes('<svg') && outdentBtn.innerHTML.includes('<svg'), '均为 SVG 图标');
    }

    console.log('\n[5] h4 富文本换行渲染修复');
    const editor2 = App.Components.initEditor(doc.createElement('div'), { initialData: '', onChange: () => {} });
    editor2.setEditorData([
      { type: 'heading4', content: '', html: '<div>富文本四级标题</div>' },
      { type: 'heading4', content: '普通四级' },
      { type: 'heading3', content: '', html: '<p>三级标题</p>' }
    ]);
    const md = editor2.getContent();
    const rendered = App.Utils.simpleMarkdown(md);
    assert(rendered.includes('<h4') && (rendered.match(/<h4/g) || []).length === 2, '两个 h4 都渲染');
    assert(rendered.includes('<h3') && (rendered.match(/<h3/g) || []).length === 1, 'h3 渲染');
    assert(!md.split('\n').some(l => /^#{1,4}\s*$/.test(l)), '导出无空标题行');
    const texts = rendered.replace(/<[^>]+>/g, '');
    assert(texts.includes('富文本四级标题') && texts.includes('普通四级') && texts.includes('三级标题'), '标题文本完整保留');

    console.log('\n[6] 行间距 CSS（段落内 23px）');
    const css = Array.from(doc.styleSheets[0].cssRules || []).map(r => r.cssText).join('\n');
    assert(css.includes('line-height: 23px') && css.includes('.notion-editable'), '编辑器行高 23px');
    assert(css.includes('.md-preview-p') && css.includes('line-height: 23px'), '详情页段落行高 23px');

    console.log('\n===== v8.3.8 综合验证: ' + pass + ' 通过, ' + fail + ' 失败 =====');
    process.exit(fail > 0 ? 1 : 0);
  } catch (e) {
    console.error('测试异常:', e && e.stack || e);
    process.exit(1);
  }
}, 1000);
