/* Notion 式无模式就地编辑（笔记详情页）专项测试 */
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
    w.document.execCommand = () => true;
    if (!w.Element.prototype.closest) w.Element.prototype.closest = function (s) { return null; };
  }
});
setTimeout(async () => {
  const win = dom.window, doc = win.document, App = win.App;
  const wait = (ms) => new Promise(r => setTimeout(r, ms));

  // ===== 内存版 DB mock =====
  const store = { notes: {}, errors: {} };
  store.notes.note1 = {
    id: 'note1', subject: '言语理解', module: '逻辑填空', knowledgePoint: '成语辨析',
    title: '**加粗标题**',
    content: '# 标题一\n\n- 项目甲\n- 项目乙\n\n**重点**内容',
    linkedErrors: [], linkedReviews: [], updatedAt: new Date().toISOString()
  };
  App.DB.get = async (t, id) => (store[t] && store[t][id]) ? store[t][id] : null;
  App.DB.updateNote = async (n) => { store.notes[n.id] = n; };
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
    assert(App.VERSION === '8.4.6', 'App.VERSION === 8.4.6（当前 ' + App.VERSION + '）');

    console.log('\n[2] 查看态渲染（无模式：无编辑按钮，点击即编辑）');
    await Notes.renderDetail({ id: 'note1' });
    await wait(10);
    const titleEl = container.querySelector('.note-detail-title');
    const bodyEl = container.querySelector('.note-detail-body');
    assert(!!titleEl, '标题容器 .note-detail-title 存在');
    assert(!!bodyEl, '正文容器 .note-detail-body 存在');
    assert(titleEl.innerHTML.includes('<strong>') && titleEl.innerHTML.includes('加粗标题'), '标题 innerHTML 渲染 Markdown（非文本插值）');
    assert(bodyEl.innerHTML.includes('<h1') && bodyEl.innerHTML.includes('md-preview-ul'), '正文 h1/列表渲染');
    const actions = container.querySelectorAll('.detail-header-action');
    assert(actions.length === 1 && actions[0].textContent === '✍️', '右上角仅 ✍️ 手写按钮（无「编辑」按钮）');
    assert(!!container.querySelector('.breadcrumb'), '面包屑保留');
    assert(!!container.querySelector('.doodle-preview'), '手写区保留');
    assert(!!container.querySelector('.note-detail-meta'), '编辑时间保留');

    console.log('\n[3] 点击标题 → 就地变 input，失焦自动保存并回查看');
    titleEl.click();
    await wait(10);
    const titleInput = container.querySelector('.note-detail-title-input');
    assert(!!titleInput, '标题变成 input.note-detail-title-input');
    assert(!container.querySelector('.note-detail-title'), '标题查看态暂时隐藏');
    titleInput.value = '新标题';
    titleInput.dispatchEvent(new win.Event('blur'));
    await wait(50);
    assert(store.notes.note1.title === '新标题', '标题已保存到 DB（新标题）');
    const restoredTitle = container.querySelector('.note-detail-title');
    assert(!!restoredTitle, '失焦后标题恢复查看渲染');
    assert(restoredTitle.textContent.includes('新标题'), '恢复显示新标题');

    console.log('\n[4] 点击正文 → 就地变块编辑器（块形态，非 textarea 小窗口）');
    const bodyEl2 = container.querySelector('.note-detail-body');
    bodyEl2.click();
    await wait(30);
    const inplace = container.querySelector('.note-inplace-editor');
    assert(!!inplace, '正文就地变 .note-inplace-editor 容器');
    const editorEl = inplace.querySelector('.notion-editor');
    assert(!!editorEl, '块编辑器 .notion-editor 出现');
    assert(!inplace.querySelector('textarea'), '不是 textarea 小窗口（保持块编辑器形态）');
    const blocks = inplace.querySelectorAll('.notion-block');
    assert(blocks.length >= 3, '块编辑器含多个块（当前 ' + blocks.length + ' 个）');
    // 编辑器内容来自笔记 MD 原文
    const inst = Notes._bodyEditor;
    assert(!!inst && !!inst.editor, '内部编辑实例已注册');
    const md0 = inst.editor.getContent();
    assert(md0.includes('# 标题一') || md0.includes('标题一'), '编辑器内容来自笔记原文');
    assert(md0.includes('项目甲'), '列表内容保留');

    console.log('\n[5] 编辑块内容（input 事件）→ 失焦自动保存 + 恢复查看渲染');
    const firstEditable = inplace.querySelector('.notion-editable');
    assert(!!firstEditable, '存在可编辑块');
    firstEditable.textContent = '**新第一段**内容';
    firstEditable.dispatchEvent(new win.Event('input', { bubbles: true }));
    await wait(700);   // 等块编辑器内部 onChange 防抖(600ms)
    const mdEdited = inst.editor.getContent();
    assert(mdEdited.includes('新第一段'), 'getContent 反映编辑内容');
    // 失焦（焦点移到编辑区外）→ 保存 + 恢复查看
    doc.dispatchEvent(new win.FocusEvent('focusout', { relatedTarget: doc.body, bubbles: true }));
    await wait(400);
    assert(store.notes.note1.content.includes('新第一段'), '失焦后内容已写入 DB');
    const bodyEl3 = container.querySelector('.note-detail-body');
    assert(!!bodyEl3 && !container.querySelector('.note-inplace-editor'), '失焦退出编辑，恢复查看渲染');
    assert(bodyEl3.innerHTML.includes('<strong>'), '恢复的查看态渲染加粗');

    console.log('\n[6] 双保险：编辑中停顿 2 秒自动保存（不退出编辑）');
    bodyEl3.click();
    await wait(30);
    const inst2 = Notes._bodyEditor;
    const ed = container.querySelector('.note-inplace-editor .notion-editable');
    ed.textContent = '自动保存验证段落';
    ed.dispatchEvent(new win.Event('input', { bubbles: true }));
    await wait(3300);   // 块编辑器 600ms + 我们的 2000ms 防抖
    assert(store.notes.note1.content.includes('自动保存验证段落'), '停顿 2 秒后自动保存到 DB');
    assert(!!container.querySelector('.note-inplace-editor'), '仍在编辑态（未因自动保存退出）');
    // 清理：退出编辑
    doc.dispatchEvent(new win.FocusEvent('focusout', { relatedTarget: doc.body, bubbles: true }));
    await wait(400);

    console.log('\n[7] 格式保存全链路：块编辑器导出 MD → JSON 存取 → simpleMarkdown 渲染不丢格式');
    const holder = doc.createElement('div');
    doc.body.appendChild(holder);
    const editor = App.Components.initEditor(holder, { initialData: '', dataMode: 'md', onChange: () => {} });
    editor.setEditorData([
      { type: 'heading2', content: '**加粗标题**' },
      { type: 'bullet', content: '**粗体项目**' },
      { type: 'bullet', content: '普通项目' },
      { type: 'quote', content: '引用`代码`' },
      { type: 'text', content: '行内**加粗**与*斜体*与公式 $x^2$' },
      { type: 'divider', content: '' }
    ]);
    const exportedMd = editor.getContent();
    assert(exportedMd.includes('**加粗标题**'), '导出 MD 含加粗标记');
    assert(exportedMd.includes('- '), '导出 MD 含列表标记');
    assert(exportedMd.includes('> '), '导出 MD 含引用标记');
    // 模拟 IndexedDB JSON 序列化存取（换行保留）
    const saved = JSON.parse(JSON.stringify(exportedMd));
    assert(saved.includes('\n'), 'JSON 序列化保留换行符');
    const rendered = App.Utils.simpleMarkdown(saved);
    assert(rendered.includes('<h2') && rendered.includes('<strong>'), '渲染 h2 + 加粗');
    assert(rendered.includes('md-preview-ul') && rendered.includes('粗体项目'), '渲染列表（不被吞进段落）');
    assert(rendered.includes('md-preview-blockquote') && rendered.includes('代码'), '渲染引用');
    assert(rendered.includes('md-preview-hr'), '渲染分割线');
    assert(rendered.includes('mformula') || rendered.includes('mf-'), '渲染公式');
    holder.remove();

    console.log('\n[8] 失焦排除：点击格式栏/工具栏不退出编辑，点击其他区域退出');
    // 重新获取当前查看态正文（[6] 退出后已重建）
    const bodyEl8 = container.querySelector('.note-detail-body');
    bodyEl8.click();
    await wait(30);
    assert(!!container.querySelector('.note-inplace-editor'), '重新进入编辑态');
    // 模拟外部移动端工具栏按钮点击（data-mobile-toolbar）→ 不应退出
    const fakeToolbar = doc.createElement('div');
    fakeToolbar.setAttribute('data-mobile-toolbar', '1');
    doc.body.appendChild(fakeToolbar);
    fakeToolbar.dispatchEvent(new win.MouseEvent('mousedown', { bubbles: true }));
    await wait(100);
    assert(!!container.querySelector('.note-inplace-editor'), '点击工具栏按钮不退出编辑');
    // 点击页面其他区域（面包屑）→ 退出
    const breadcrumbEl = container.querySelector('.breadcrumb');
    breadcrumbEl.dispatchEvent(new win.MouseEvent('mousedown', { bubbles: true }));
    await wait(400);
    assert(!container.querySelector('.note-inplace-editor'), '点击编辑区外自动退出编辑');
    assert(!!container.querySelector('.note-detail-body'), '退出后恢复查看渲染');
    fakeToolbar.remove();

    console.log('\n[9] 空内容笔记显示「点击开始编辑」提示');
    store.notes.note1.content = '';
    await Notes.renderDetail({ id: 'note1' });
    await wait(10);
    const emptyBody = container.querySelector('.note-detail-body');
    assert(emptyBody && emptyBody.textContent.includes('点击开始编辑'), '空正文显示点击编辑提示');
    // 恢复数据
    store.notes.note1.content = '# 标题一\n\n- 项目甲\n- 项目乙\n\n**重点**内容';

    console.log('\n[10] 标题回车键保存 + 数据完整性（linkedErrors 保留）');
    store.notes.note1.linkedErrors = ['err1'];
    store.notes.note1.linkedReviews = [{ ts: 1 }];
    await Notes.renderDetail({ id: 'note1' });
    await wait(10);
    container.querySelector('.note-detail-title').click();
    await wait(10);
    const ti2 = container.querySelector('.note-detail-title-input');
    ti2.value = '回车标题';
    ti2.dispatchEvent(new win.KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));
    await wait(50);
    assert(store.notes.note1.title === '回车标题', '回车触发保存');
    assert(store.notes.note1.linkedErrors.length === 1, 'linkedErrors 保留');
    assert(store.notes.note1.linkedReviews.length === 1, 'linkedReviews 保留');

    console.log('\n总计: ' + pass + ' 通过, ' + fail + ' 失败');
    if (fail > 0) { console.error('✗✗ 存在失败用例'); process.exit(1); }
    else { console.log('✓✓ 全部通过'); process.exit(0); }
  } catch (e) {
    console.error('测试执行异常:', e && e.stack || e);
    process.exit(1);
  }
}, 300);
