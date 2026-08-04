/* 笔记系统重构 v8.4.8 专项测试：marked.js 渲染 + 重合层编辑 + 格式栏字符串操作 */
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
    // 注入 marked（生产由 CDN 提供；测试用 node 版）
    w.marked = marked;
  }
});
setTimeout(async () => {
  const win = dom.window, doc = win.document, App = win.App;
  const wait = (ms) => new Promise(r => setTimeout(r, ms));

  // ===== 内存版 DB mock（数据结构与真实 IndexedDB 一致） =====
  const store = { notes: {}, errors: {} };
  store.notes.note1 = {
    id: 'note1', subject: '言语理解', module: '逻辑填空', knowledgePoint: '成语辨析',
    title: '**加粗标题**',
    content: '# 标题一\n\n- 项目甲\n- 项目乙\n\n**重点**内容\n\n公式 $x^2$',
    linkedErrors: [], linkedReviews: [], updatedAt: new Date().toISOString()
  };
  App.DB.get = async (t, id) => (store[t] && store[t][id]) ? store[t][id] : null;
  // updateNote 模拟 IndexedDB put：覆盖记录字段（保持页面内对象引用一致，与真实 IDB 行为对齐）
  App.DB.updateNote = async (n) => {
    if (store.notes[n.id]) Object.assign(store.notes[n.id], n);
    else store.notes[n.id] = n;
  };
  App.DB.addNote = async (n) => { if (!n.id) n.id = 'note' + Math.random().toString(36).slice(2, 8); store.notes[n.id] = n; return n.id; };
  App.DB.getNotes = async () => Object.values(store.notes);
  App.DB.getErrors = async () => [];
  App.Router.navigate = (r) => {};
  App.Router.back = () => {};

  const Notes = App.Pages.Notes;
  const container = doc.getElementById('page-note-detail');
  doc.body.appendChild(container);

  try {
    console.log('[1] 版本号');
    assert(App.VERSION === '8.4.8', 'App.VERSION === 8.4.8（当前 ' + App.VERSION + '）');

    console.log('\n[2] 查看层：marked.js 渲染（废弃 simpleMarkdown，读取现有数据不硬编码）');
    await Notes.renderDetail({ id: 'note1' });
    await wait(10);
    const stack = container.querySelector('.note-editor-stack');
    const renderLayer = container.querySelector('.render-layer');
    assert(!!stack, '重合层容器 .note-editor-stack 存在');
    assert(!!renderLayer, '查看层 .render-layer 存在');
    assert(renderLayer.classList.contains('markdown-body'), '查看层带 markdown-body 类（github-markdown-css）');
    const titleEl2 = container.querySelector('.note-detail-title');
    assert(!!titleEl2 && titleEl2.innerHTML.includes('<strong>') && titleEl2.innerHTML.includes('加粗标题'), '标题 marked 渲染加粗（innerHTML 非文本插值）');
    assert(renderLayer.innerHTML.includes('<h1') && renderLayer.innerHTML.includes('标题一'), '正文 marked 渲染 h1');
    assert(renderLayer.innerHTML.includes('<ul>') && renderLayer.innerHTML.includes('项目甲'), '正文 marked 渲染列表');
    assert(!renderLayer.innerHTML.includes('md-preview-'), '渲染不使用 simpleMarkdown 的 md-preview 类（已切换 marked）');
    assert(renderLayer.innerHTML.includes('mformula'), '公式扩展渲染 $x^2$ → mformula');
    // 编辑层初始隐藏（CSS 控制 display，jsdom 检查结构）
    const editLayer = container.querySelector('.edit-layer');
    assert(!!editLayer, '编辑层 textarea 存在（与查看层重合）');
    assert(editLayer.value === store.notes.note1.content, '编辑层显示现有笔记 Markdown 原文');
    assert(editLayer.classList.contains('edit-layer'), '编辑层带 edit-layer 类');
    assert(!stack.classList.contains('editing'), '初始为查看态（非编辑态）');
    // 顶部按钮为 ✏️ + ✍️ + ⋮
    const actions = container.querySelectorAll('.note-detail-actions .detail-header-action');
    assert(actions.length === 3, '右上角 3 个按钮（✏️ 编辑 + ✍️ 手写 + ⋮ 菜单）');
    assert(container.querySelector('.note-edit-toggle').textContent === '✏️', '切换按钮初始为 ✏️');

    console.log('\n[3] 点击查看层 → 进入编辑态（isEditing 切换，无页面跳转）');
    renderLayer.click();
    await wait(10);
    assert(stack.classList.contains('editing'), '点击后 stack 进入 editing 态');
    assert(container.querySelector('.note-edit-toggle').textContent === '完成', '顶部按钮变「完成」');
    const toolbar = container.querySelector('.note-edit-toolbar--float');
    assert(!!toolbar && toolbar.classList.contains('visible'), '底部格式栏编辑态显示');
    assert(toolbar.querySelectorAll('button').length >= 8, '格式栏按钮保持原样（B/I/H2/H3/•/1./>/--- 等）');

    console.log('\n[4] 编辑：修改 textarea → 内容同步 + 字数更新');
    const ta = container.querySelector('.edit-layer');
    ta.value = ta.value + '\n新增段落';
    ta.dispatchEvent(new win.Event('input', { bubbles: true }));
    await wait(10);
    assert(Notes._noteEditing === true, '仍在编辑态');
    const countEl = container.querySelector('.note-meta-count');
    assert(!!countEl && countEl.textContent.includes('字'), '字数统计显示');
    assert(parseInt(countEl.textContent) === store.notes.note1.content.length, '字数实时更新（' + countEl.textContent + ' = ' + store.notes.note1.content.length + ' 字）');
    assert(store.notes.note1.content.endsWith('新增段落'), 'note.content 同步编辑内容');

    console.log('\n[5] 失焦自动保存（blur）');
    ta.dispatchEvent(new win.Event('blur'));
    await wait(100);
    assert(store.notes.note1.content.endsWith('新增段落'), 'blur 后内容已写入 DB');
    const statusEl = container.querySelector('.note-meta-status');
    assert(statusEl && statusEl.textContent.includes('已保存'), '保存状态显示「已保存」');

    console.log('\n[6] 点「完成」→ 保存 + 退出编辑 + 查看层重渲染最新内容');
    container.querySelector('.note-edit-toggle').click();
    await wait(150);
    assert(!stack.classList.contains('editing'), '退出编辑态');
    assert(container.querySelector('.note-edit-toggle').textContent === '✏️', '按钮恢复 ✏️');
    assert(!toolbar.classList.contains('visible'), '格式栏隐藏');
    const renderLayer2 = container.querySelector('.render-layer');
    assert(renderLayer2.innerHTML.includes('新增段落'), '查看层用最新内容重渲染（marked）');
    assert(renderLayer2.innerHTML.includes('<p>') || renderLayer2.innerHTML.includes('<strong>'), '查看层为 HTML 渲染');
    const timeEl = container.querySelector('.note-meta-time');
    assert(!!timeEl && timeEl.textContent.includes('最后编辑于'), '最后编辑时间保留');

    console.log('\n[7] 标题就地编辑（点击 → input → 失焦保存）');
    container.querySelector('.note-detail-title').click();
    await wait(10);
    const ti = container.querySelector('.note-detail-title-input');
    assert(!!ti, '标题变成 input');
    ti.value = '新标题';
    ti.dispatchEvent(new win.Event('blur'));
    await wait(50);
    assert(store.notes.note1.title === '新标题', '标题已保存到 DB');
    const restoredTitle = container.querySelector('.note-detail-title');
    assert(!!restoredTitle && restoredTitle.textContent.includes('新标题'), '标题恢复查看渲染');

    console.log('\n[8] 格式栏字符串级操作（保持现有实现：选中包裹、无选插入标记光标居中、行首标记、分割线）');
    // 重新进入编辑态（真实使用场景：格式栏在编辑态操作）
    container.querySelector('.render-layer').click();
    await wait(10);
    assert(container.querySelector('.note-editor-stack').classList.contains('editing'), '已进入编辑态');
    const tb = container.querySelector('.note-edit-toolbar--float');
    const ta2 = container.querySelector('.edit-layer');
    // 选中文本包裹 **（现有格式栏行为：始终包裹）
    ta2.focus();
    ta2.value = 'abc'; ta2.setSelectionRange(1, 2);
    const btnB = tb.querySelectorAll('button')[0];
    btnB.click();
    assert(ta2.value === 'a**b**c', 'B 按钮选中包裹 **');
    assert(ta2.selectionStart === 3 && ta2.selectionEnd === 4, '包裹后选区保留在文本上');
    // 无选中：插入成对标记，光标居中（现有实现插入 ****，光标落两星之间）
    ta2.value = 'abc'; ta2.setSelectionRange(1, 1);
    btnB.click();
    assert(ta2.value === 'a****bc', '无选中插入标记对（光标居中）');
    assert(ta2.selectionStart === 3, '光标居中（标记之间）');
    // 行首标记（H2）
    ta2.value = '标题文字'; ta2.setSelectionRange(0, 0);
    const btnH2 = tb.querySelectorAll('button')[2];
    btnH2.click();
    assert(ta2.value === '## 标题文字', 'H2 行首插入');
    // 分割线
    ta2.value = '上文'; ta2.setSelectionRange(2, 2);
    const btnDiv = tb.querySelectorAll('button')[7];
    btnDiv.click();
    assert(ta2.value === '上文\n---\n', '分割线插入');
    // 操作后同步编辑内容（input 事件 → note.content，字符串级格式不丢）
    assert(store.notes.note1.content === '上文\n---\n', '格式栏操作同步到编辑内容（当前: ' + JSON.stringify(store.notes.note1.content) + '）');
    // 退出编辑态收尾
    container.querySelector('.note-edit-toggle').click();
    await wait(100);

    console.log('\n[9] renderMarkdown：marked 与公式扩展');
    const md1 = App.Utils.renderMarkdown('**加粗**与`代码`');
    assert(md1.includes('<strong>') && md1.includes('<code>'), 'marked 渲染加粗/行内代码');
    const md2 = App.Utils.renderMarkdown('公式 $\\frac{a}{b}$ 与块级 $$x^2$$');
    assert(md2.includes('mformula'), '行内+块级公式均渲染为 mformula');
    assert(md2.includes('mf-frac'), '分数公式渲染');
    assert(App.Utils.renderMarkdown('') === '', '空内容返回空');

    console.log('\n[10] 新建笔记页：正文换成 markdownEditor（textarea + 字符串级格式栏）');
    const noteFormPage = doc.getElementById('page-note-form');
    doc.body.appendChild(noteFormPage);
    await App.Pages.Notes.renderForm.call(Notes, { subject: '资料分析' });
    await wait(50);
    const mdEditor = noteFormPage.querySelector('.md-editor');
    assert(!!mdEditor, '新建页出现 .md-editor（markdownEditor）');
    const formTa = noteFormPage.querySelector('.md-editor textarea');
    assert(!!formTa, '正文为 textarea（字符串级编辑）');
    const formTb = noteFormPage.querySelector('.md-editor__toolbar');
    assert(!!formTb && formTb.querySelectorAll('button').length >= 8, '新建页格式栏存在（B/I/H2/...原样）');
    // 输入 → onChange 同步（防抖保存需分类，此处验证内容同步）
    formTa.value = '新建**内容**';
    formTa.dispatchEvent(new win.Event('input', { bubbles: true }));
    await wait(10);
    assert(store.notes.note1.title === '新标题', '已有笔记数据未被覆盖（兼容现有数据）');

    console.log('\n[11] 数据兼容：未硬编码示例内容，读取现有笔记');
    assert(store.notes.note1 && store.notes.note1.id === 'note1' && !!store.notes.note1.title && store.notes.note1.content !== undefined, 'note 数据结构完整（id/title/content 保留，未初始化覆盖）');
    assert(store.notes.note1.linkedErrors && Array.isArray(store.notes.note1.linkedErrors), 'linkedErrors 字段保留');

    console.log('\n总计: ' + pass + ' 通过, ' + fail + ' 失败');
    if (fail > 0) { console.error('✗✗ 存在失败用例'); process.exit(1); }
    else { console.log('✓✓ 全部通过'); process.exit(0); }
  } catch (e) {
    console.error('测试执行异常:', e && e.stack || e);
    process.exit(1);
  }
}, 300);
