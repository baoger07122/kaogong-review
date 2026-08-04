/* Notion 式无模式就地编辑（笔记详情页）专项测试 */
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
    if (!w.Element.prototype.closest) w.Element.prototype.closest = function (s) { return null; };
    // 注入 marked（生产由 CDN 提供；测试用 node 版）
    w.marked = marked;
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
    assert(App.VERSION === '8.4.13', 'App.VERSION === 8.4.13（当前 ' + App.VERSION + '）');

    console.log('\n[2] 查看态渲染（JSON 块 → HTML；点击即编辑）');
    await Notes.renderDetail({ id: 'note1' });
    await wait(10);
    const titleEl = container.querySelector('.note-detail-title');
    const bodyEl = container.querySelector('.note-detail-body');
    assert(!!titleEl, '标题容器 .note-detail-title 存在');
    assert(!!bodyEl, '正文容器 .note-detail-body 存在');
    assert(titleEl.textContent === '**加粗标题**', '标题为纯文本显示（非 Markdown 二次渲染）');
    // 懒转换：历史 MD 字符串 → JSON 块数组（打开时自动迁移）
    assert(Array.isArray(store.notes.note1.content), '历史 Markdown 数据打开时已懒转换为 JSON 块数组');
    assert(store.notes.note1.content.some(b => b.type === 'heading1'), 'JSON 含 heading1 块（# 标题一 已解析）');
    assert(store.notes.note1.content.some(b => b.type === 'bulletList'), 'JSON 含 bulletList 块（- 项目甲 已解析）');
    assert(store.notes.note1.content.some(b => b.content && b.content.includes('重点')), 'JSON 含加粗内容块');
    assert(bodyEl.innerHTML.includes('<h1') && bodyEl.innerHTML.includes('标题一'), '正文 JSON→HTML 渲染 h1');
    assert(bodyEl.innerHTML.includes('md-preview-ul') && bodyEl.innerHTML.includes('项目甲'), '正文 JSON→HTML 渲染列表');
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
    // 容器复用：.card 卡片节点不被替换，仅内部换成块编辑器（修复切换闪烁）
    const cardEl = container.querySelector('.note-detail-body');
    assert(!!cardEl, '正文 .card 卡片容器仍在（未被替换）');
    assert(cardEl.classList.contains('card'), '卡片样式保留（白底/圆角/内边距不变）');
    assert(cardEl.classList.contains('note-detail-body--editing'), '进入编辑态标记 class 生效');
    const editorEl = cardEl.querySelector('.notion-editor');
    assert(!!editorEl, '块编辑器 .notion-editor 出现在卡片内部');
    assert(!cardEl.querySelector('textarea'), '不是 textarea 小窗口（保持块编辑器形态）');
    const blocks = cardEl.querySelectorAll('.notion-block');
    assert(blocks.length >= 3, '块编辑器含多个块（当前 ' + blocks.length + ' 个）');
    // 页脚隐藏：分割线/字数/保存状态（就地编辑场景不显示编辑器自带页脚）
    const editorFooter = cardEl.querySelector('.notion-editor__footer');
    assert(!!editorFooter && (editorFooter.style.display === 'none'), '编辑器页脚已隐藏（就地编辑）');
    // 字数整合到右上角 ⋮ 按钮区
    const countLabel = container.querySelector('.note-edit-count');
    assert(!!countLabel, '右上角字数标签存在');
    assert(/字$/.test(countLabel.textContent), '字数标签显示（' + countLabel.textContent + '）');
    assert(countLabel.textContent === App.Utils.countBlocks(store.notes.note1.content) + ' 字', '字数与内容一致');
    // 编辑器内容来自笔记 JSON 块（懒转换后）
    const inst = Notes._bodyEditor;
    assert(!!inst && !!inst.editor, '内部编辑实例已注册');
    const data0 = inst.editor.getEditorData();
    assert(Array.isArray(data0), '编辑器导出 JSON 块数组');
    assert(data0.some(b => b.type === 'heading1' && (b.content || '').includes('标题一')), '编辑器含 heading1 块（原文）');
    assert(data0.some(b => b.type === 'bulletList'), '编辑器含 bulletList 块');

    console.log('\n[5] 编辑块内容（input 事件）→ 失焦自动保存 + 恢复查看渲染');
    const firstEditable = cardEl.querySelector('.notion-editable');
    assert(!!firstEditable, '存在可编辑块');
    firstEditable.textContent = '新第一段内容';
    firstEditable.dispatchEvent(new win.Event('input', { bubbles: true }));
    await wait(700);   // 等块编辑器内部 onChange 防抖(600ms)
    const dataEdited = inst.editor.getEditorData();
    assert(JSON.stringify(dataEdited).includes('新第一段'), 'getEditorData 反映编辑内容');
    // 失焦（焦点移到编辑区外）→ 保存 + 恢复查看
    doc.dispatchEvent(new win.FocusEvent('focusout', { relatedTarget: doc.body, bubbles: true }));
    await wait(400);
    assert(JSON.stringify(store.notes.note1.content).includes('新第一段'), '失焦后 JSON 内容已写入 DB');
    assert(Array.isArray(store.notes.note1.content), 'DB 中 content 为 JSON 数组（不再是 Markdown 字符串）');
    const bodyEl3 = container.querySelector('.note-detail-body');
    assert(!!bodyEl3 && !bodyEl3.classList.contains('note-detail-body--editing'), '失焦退出编辑，恢复查看渲染');
    assert(!container.querySelector('.note-edit-count'), '退出编辑后右上角字数标签移除');
    assert(bodyEl3.classList.contains('card'), '恢复后卡片样式仍在');
    assert(bodyEl3.innerHTML.includes('新第一段'), '恢复的查看态渲染新内容');

    console.log('\n[6] 双保险：编辑中停顿 2 秒自动保存（不退出编辑）');
    bodyEl3.click();
    await wait(30);
    const inst2 = Notes._bodyEditor;
    const ed = container.querySelector('.note-detail-body .notion-editable');
    ed.textContent = '自动保存验证段落';
    ed.dispatchEvent(new win.Event('input', { bubbles: true }));
    await wait(3300);   // 块编辑器 600ms + 我们的 2000ms 防抖
    assert(JSON.stringify(store.notes.note1.content).includes('自动保存验证段落'), '停顿 2 秒后自动保存到 DB');
    assert(!!container.querySelector('.note-detail-body--editing'), '仍在编辑态（未因自动保存退出）');
    // 清理：退出编辑
    doc.dispatchEvent(new win.FocusEvent('focusout', { relatedTarget: doc.body, bubbles: true }));
    await wait(400);

    console.log('\n[7] 格式保存全链路：块编辑器 JSON → IndexedDB 存取 → renderBlocks 渲染不丢格式');
    const holder = doc.createElement('div');
    doc.body.appendChild(holder);
    const editor = App.Components.initEditor(holder, { initialData: '', dataMode: 'json', onChange: () => {} });
    editor.setEditorData([
      { type: 'heading2', content: '加粗标题', html: '<strong>加粗标题</strong>' },
      { type: 'bulletList', content: '粗体项目', html: '<strong>粗体项目</strong>' },
      { type: 'bulletList', content: '普通项目' },
      { type: 'quote', content: '引用代码', html: '引用<code>代码</code>' },
      { type: 'divider', content: '' }
    ]);
    const jsonData = editor.getEditorData();
    assert(Array.isArray(jsonData), 'getEditorData 返回 JSON 数组');
    assert(jsonData.some(b => b.type === 'heading2'), 'JSON 含 heading2 块');
    assert(jsonData.some(b => b.type === 'bulletList'), 'JSON 含 bulletList 块');
    assert(jsonData.some(b => b.type === 'quote'), 'JSON 含 quote 块');
    // 模拟 IndexedDB JSON 序列化存取
    const saved = JSON.parse(JSON.stringify(jsonData));
    assert(Array.isArray(saved), 'JSON 序列化存取后仍是数组');
    const rendered = App.Utils.renderBlocks(saved);
    assert(rendered.includes('<h2') && rendered.includes('加粗标题'), 'renderBlocks 渲染 h2');
    assert(rendered.includes('md-preview-ul') && rendered.includes('粗体项目'), 'renderBlocks 渲染列表');
    assert(rendered.includes('md-preview-blockquote') && rendered.includes('代码'), 'renderBlocks 渲染引用');
    assert(rendered.includes('<hr'), 'renderBlocks 渲染分割线');
    assert(App.Utils.renderBlocks('') === '' && App.Utils.renderBlocks(null) === '', 'renderBlocks 空值返回空');
    holder.remove();

    console.log('\n[8] 失焦排除：点击格式栏/工具栏不退出编辑，点击其他区域退出');
    // 重新获取当前查看态正文（[6] 退出后已重建）
    const bodyEl8 = container.querySelector('.note-detail-body');
    bodyEl8.click();
    await wait(30);
    assert(!!container.querySelector('.note-detail-body--editing'), '重新进入编辑态');
    // 模拟外部移动端工具栏按钮点击（data-mobile-toolbar）→ 不应退出
    const fakeToolbar = doc.createElement('div');
    fakeToolbar.setAttribute('data-mobile-toolbar', '1');
    doc.body.appendChild(fakeToolbar);
    fakeToolbar.dispatchEvent(new win.MouseEvent('mousedown', { bubbles: true }));
    await wait(100);
    assert(!!container.querySelector('.note-detail-body--editing'), '点击工具栏按钮不退出编辑');
    // 点击页面其他区域（面包屑）→ 退出
    const breadcrumbEl = container.querySelector('.breadcrumb');
    breadcrumbEl.dispatchEvent(new win.MouseEvent('mousedown', { bubbles: true }));
    await wait(400);
    assert(!container.querySelector('.note-detail-body--editing'), '点击编辑区外自动退出编辑');
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

    console.log('\n[11] 移动端格式栏：默认隐藏，仅块编辑器聚焦显示，其他编辑器不触发');
    const w0 = win.innerWidth;
    Object.defineProperty(win, 'innerWidth', { value: 375, configurable: true, writable: true });
    const mbar = App.Components._ensureMobileToolbar();
    assert(!!mbar && mbar.classList.contains('notion-mobile-toolbar'), '移动端单例工具栏可构建');
    assert(!mbar.classList.contains('is-visible'), '默认无 is-visible（隐藏，不再常驻）');
    // 块编辑器聚焦 → 显示
    const holder2 = doc.createElement('div');
    doc.body.appendChild(holder2);
    const ed2 = App.Components.initEditor(holder2, { initialData: '', dataMode: 'json', onChange: null });
    const editable2 = holder2.querySelector('.notion-editable');
    editable2.dispatchEvent(new win.FocusEvent('focusin', { bubbles: true }));
    assert(mbar.classList.contains('is-visible'), '块编辑器聚焦 → 工具栏显示');
    // 失焦 → 220ms 后隐藏
    editable2.dispatchEvent(new win.FocusEvent('focusout', { bubbles: true, relatedTarget: doc.body }));
    await wait(350);
    assert(!mbar.classList.contains('is-visible'), '块编辑器失焦 → 工具栏隐藏');
    // textarea 聚焦 → 不显示（非块编辑器）
    const taHolder = doc.createElement('div');
    doc.body.appendChild(taHolder);
    const mdEd = App.Components.markdownEditor('', '');
    taHolder.appendChild(mdEd.element);
    const ta2 = mdEd.element.querySelector('textarea');
    ta2.dispatchEvent(new win.FocusEvent('focusin', { bubbles: true }));
    await wait(30);
    assert(!mbar.classList.contains('is-visible'), 'textarea 聚焦不触发工具栏');
    Object.defineProperty(win, 'innerWidth', { value: w0, configurable: true, writable: true });
    holder2.remove(); taHolder.remove();

    console.log('\n总计: ' + pass + ' 通过, ' + fail + ' 失败');
    if (fail > 0) { console.error('✗✗ 存在失败用例'); process.exit(1); }
    else { console.log('✓✓ 全部通过'); process.exit(0); }
  } catch (e) {
    console.error('测试执行异常:', e && e.stack || e);
    process.exit(1);
  }
}, 300);
