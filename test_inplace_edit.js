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
    assert(App.VERSION === '8.6.31', 'App.VERSION === 8.6.31（当前 ' + App.VERSION + '）');

    console.log('\n[2] 查看态渲染（JSON 块 → HTML；点击即编辑）');
    await Notes.renderDetail({ id: 'note1' });
    await wait(10);
    const titleEl = container.querySelector('.note-detail-title');
    const bodyEl = container.querySelector('.note-detail-body');
    assert(!!titleEl, '标题容器 .note-detail-title 存在');
    assert(!!bodyEl, '正文容器 .note-detail-body 存在');
    assert(titleEl.textContent === '**加粗标题**', '标题为纯文本显示（非 Markdown 二次渲染）');
    // v8.5.5 彻底去块：历史 MD 字符串打开时自动迁移为完整 HTML 字符串
    assert(typeof store.notes.note1.content === 'string' && store.notes.note1.content.indexOf('<') === 0, '历史 Markdown 数据打开时已迁移为完整 HTML 字符串');
    assert(store.notes.note1.content.includes('<h1'), 'HTML 含 h1（# 标题一 已解析）');
    assert(store.notes.note1.content.includes('<ul'), 'HTML 含 ul（- 项目甲 已解析）');
    assert(store.notes.note1.content.includes('重点'), 'HTML 含加粗内容块');
    assert(bodyEl.innerHTML.includes('<h1') && bodyEl.innerHTML.includes('标题一'), '查看态 HTML 直通渲染 h1');
    assert(bodyEl.innerHTML.includes('md-preview-ul') && bodyEl.innerHTML.includes('项目甲'), '查看态 HTML 直通渲染列表');
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
    // 容器复用：.card 卡片节点不被替换，仅内部换成 HTML 编辑器（修复切换闪烁）
    const cardEl = container.querySelector('.note-detail-body');
    assert(!!cardEl, '正文 .card 卡片容器仍在（未被替换）');
    assert(cardEl.classList.contains('card'), '卡片样式保留（白底/圆角/内边距不变）');
    assert(cardEl.classList.contains('note-detail-body--editing'), '进入编辑态标记 class 生效');
    // v8.5.5 去块：单连续富文本编辑区（无块、无 textarea）
    assert(!!cardEl.querySelector('.html-editor'), 'HTML 编辑器 .html-editor 出现在卡片内部');
    assert(!cardEl.querySelector('textarea'), '不是 textarea 小窗口');
    const htmlArea = cardEl.querySelector('.html-editor__area');
    assert(!!htmlArea && htmlArea.hasAttribute('contenteditable'), '单连续富文本编辑区（contenteditable）');
    assert(htmlArea.innerHTML.includes('<h1') && htmlArea.innerHTML.includes('<ul'), '编辑区直存 HTML（h1/ul 保留，格式保真）');
    // htmlEditor 无自带页脚（分割线/字数/保存状态都不需要）
    assert(!cardEl.querySelector('.notion-editor__footer'), 'HTML 编辑器无自带页脚（更简洁）');
    // 字数整合到右上角 ⋮ 按钮区
    const countLabel = container.querySelector('.note-edit-count');
    assert(!!countLabel, '右上角字数标签存在');
    assert(/字$/.test(countLabel.textContent), '字数标签显示（' + countLabel.textContent + '）');
    assert(countLabel.textContent === App.Utils.countHtmlText(store.notes.note1.content) + ' 字', '字数与内容一致');
    // 编辑器内容来自迁移后的 HTML（v8.5.5 去块后单富文本直存）
    const inst = Notes._bodyEditor;
    assert(!!inst && !!inst.editor, '内部编辑实例已注册');
    const data0 = inst.editor.getHtml();
    assert(typeof data0 === 'string' && data0.indexOf('<') === 0, '编辑器导出完整 HTML 字符串');
    assert(data0.includes('<h1') && data0.includes('标题一'), '编辑器 HTML 含 h1（原文）');
    assert(data0.includes('<ul'), '编辑器 HTML 含 ul（列表保留）');
    // A（v8.4.15 沿用）：聚焦经 rAF 延迟 + preventScroll（防自动滚动抖动）
    // jsdom 中 contenteditable 元素 focus 不生效（activeElement 仍为 BODY），故包装 focus 验证调用时机与参数
    let focusCnt = 0, focusInRaf = false, focusOpts = null, rafActive = false;
    const origRAF = win.requestAnimationFrame;
    const origFocus = win.HTMLElement.prototype.focus;
    win.requestAnimationFrame = (cb) => { rafActive = true; try { cb(); } finally { rafActive = false; } return 1; };
    win.HTMLElement.prototype.focus = function (opts) { focusCnt++; if (rafActive) focusInRaf = true; focusOpts = opts; };
    Notes._focusBlockAt(inst.editor, 0);
    assert(focusCnt >= 1, '聚焦被调用');
    assert(focusInRaf, '聚焦在 rAF 回调内执行（延迟到布局稳定）');
    assert(!!focusOpts && focusOpts.preventScroll === true, '聚焦带 preventScroll（阻止浏览器自动滚动）');
    win.HTMLElement.prototype.focus = origFocus;
    win.requestAnimationFrame = origRAF;
    // B（v8.5.5）：无块结构——编辑区无 .notion-block（去块验证）
    assert(cardEl.querySelectorAll('.notion-block').length === 0, '编辑区无块结构（彻底去块）');
    // v8.5.7：编辑态左内边距对齐查看态（.note-render-pad 20px）
    const editPad = win.getComputedStyle(cardEl.querySelector('.html-editor__area')).paddingLeft;
    assert(editPad === '0px', '编辑态左内边距 0px（当前 ' + editPad + '）');

    console.log('\n[5] 编辑内容（input 事件）→ 失焦自动保存 + 恢复查看渲染');
    const firstEditable = cardEl.querySelector('.html-editor__area');
    assert(!!firstEditable, '存在可编辑块');
    firstEditable.innerHTML = '<p>新第一段内容</p>';
    firstEditable.dispatchEvent(new win.Event('input', { bubbles: true }));
    await wait(700);   // 等编辑器内部 onChange 防抖(600ms)
    const dataEdited = inst.editor.getHtml();
    assert(dataEdited.includes('新第一段'), 'getHtml 反映编辑内容');
    // 失焦（焦点移到编辑区外）→ 保存 + 恢复查看
    doc.dispatchEvent(new win.FocusEvent('focusout', { relatedTarget: doc.body, bubbles: true }));
    await wait(400);
    assert(store.notes.note1.content.includes('新第一段'), '失焦后 HTML 内容已写入 DB');
    assert(typeof store.notes.note1.content === 'string' && store.notes.note1.content.indexOf('<') === 0, 'DB 中 content 为完整 HTML 字符串（不再 JSON/Markdown）');
    const bodyEl3 = container.querySelector('.note-detail-body');
    assert(!!bodyEl3 && !bodyEl3.classList.contains('note-detail-body--editing'), '失焦退出编辑，恢复查看渲染');
    assert(!container.querySelector('.note-edit-count'), '退出编辑后右上角字数标签移除');
    assert(bodyEl3.classList.contains('card'), '恢复后卡片样式仍在');
    assert(bodyEl3.innerHTML.includes('新第一段'), '恢复的查看态渲染新内容');

    console.log('\n[6] 双保险：编辑中停顿 2 秒自动保存（不退出编辑）');
    bodyEl3.click();
    await wait(30);
    const inst2 = Notes._bodyEditor;
    const ed = container.querySelector('.note-detail-body .html-editor__area');
    ed.innerHTML = '<p>自动保存验证段落</p>';
    ed.dispatchEvent(new win.Event('input', { bubbles: true }));
    await wait(3300);   // 编辑器内部 600ms + 我们的 2000ms 防抖
    assert(store.notes.note1.content.includes('自动保存验证段落'), '停顿 2 秒后自动保存到 DB');
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
    // v8.6.5 点格式/插入面板弹层（notion-mobile-sheet-overlay/sheet）不退出编辑（修复点段落格式跳段退出）
    const fakeSheet = doc.createElement('div');
    fakeSheet.className = 'notion-mobile-sheet-overlay';
    doc.body.appendChild(fakeSheet);
    fakeSheet.dispatchEvent(new win.MouseEvent('mousedown', { bubbles: true }));
    await wait(100);
    assert(!!container.querySelector('.note-detail-body--editing'), '点击格式面板弹层不退出编辑');
    fakeSheet.remove();
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

    console.log('\n[12] 无底部导航页面：笔记详情/编辑隐藏固定底栏');
    const nav = doc.getElementById('bottom-nav');
    assert(!!nav, '底部导航存在');
    App.Router.updateNavVisibility('note-detail');
    assert(nav.classList.contains('nav--hidden'), 'note-detail 隐藏导航');
    App.Router.updateNavVisibility('note-form');
    assert(nav.classList.contains('nav--hidden'), 'note-form 隐藏导航');
    App.Router.updateNavVisibility('notes');
    assert(!nav.classList.contains('nav--hidden'), 'notes 恢复导航');
    // handleRoute 集成：进入详情页 → 导航隐藏 + 页面带 nav-hidden class；返回列表 → 恢复
    win.location.hash = '#note-detail?id=note1';
    await App.Router.handleRoute();
    await wait(50);
    assert(nav.classList.contains('nav--hidden'), 'handleRoute 到 note-detail 隐藏导航');
    assert(doc.getElementById('page-note-detail').classList.contains('nav-hidden'), 'page-note-detail 带 nav-hidden class');
    assert(App.Components._navVisible === false, '移动端工具栏收到导航隐藏状态');
    win.location.hash = '#notes';
    await App.Router.handleRoute();
    await wait(50);
    assert(!nav.classList.contains('nav--hidden'), 'handleRoute 回 notes 恢复导航');
    assert(!doc.getElementById('page-note-detail').classList.contains('nav-hidden'), '回列表后移除 nav-hidden class');
    assert(App.Components._navVisible === true, '移动端工具栏收到导航恢复状态');

    console.log('\n[13] v8.4.17 格式栏选区保持 + 空白段占位符移除');
    // 13.1 占位符：placeholder:false → 空块不设置 data-placeholder（不再显示「点击输入内容…」）
    const holder3 = doc.createElement('div');
    doc.body.appendChild(holder3);
    App.Components.initEditor(holder3, {
      initialData: [{ type: 'text', content: '' }], dataMode: 'json', placeholder: false
    });
    const ed3First = holder3.querySelector('.notion-editable');
    assert(!!ed3First, '空块存在');
    assert(!ed3First.hasAttribute('data-placeholder'), '占位符移除：空块不再设置 data-placeholder');
    // 13.2 工具栏按钮 mousedown 被 wrapper 委托阻止默认（保住焦点与选区，execCommand 才能生效）
    const tb3 = holder3.querySelector('.notion-toolbar');
    assert(!!tb3, '桌面工具栏已构建（jsdom 桌面视口）');
    const bBtn3 = tb3 ? tb3.querySelector('.notion-tool-btn--sm') : null;
    assert(!!bBtn3, '工具栏加粗按钮存在');
    if (bBtn3) {
      const md3 = new win.MouseEvent('mousedown', { bubbles: true, cancelable: true });
      bBtn3.dispatchEvent(md3);
      assert(md3.defaultPrevented === true, '工具栏按钮 mousedown 已阻止默认（防止清选区）');
    }
    // 13.3 选区兜底：先记录编辑器内选区（savedRange），清空当前选区后点加粗 → applyFormat 用 savedRange 重建选区
    let programRange = null, addedRange = null;
    const origGetSel = win.getSelection;
    win.getSelection = () => ({ rangeCount: programRange ? 1 : 0, getRangeAt: () => programRange, removeAllRanges() {}, addRange(r) { addedRange = r; } });
    try {
      const ed3With = doc.createElement('div');
      doc.body.appendChild(ed3With);
      App.Components.initEditor(ed3With, {
        initialData: [{ type: 'text', content: '测试加粗文本' }], dataMode: 'json', placeholder: false
      });
      const editable3 = ed3With.querySelector('.notion-editable');
      programRange = doc.createRange();
      programRange.selectNodeContents(editable3);
      editable3.dispatchEvent(new win.MouseEvent('mouseup', { bubbles: true }));   // 触发 captureSel 保存 savedRange
      programRange = null;                                                          // 模拟点击按钮后当前选区被清
      const bBtn3b = ed3With.querySelector('.notion-tool-btn--sm');
      bBtn3b.dispatchEvent(new win.MouseEvent('click', { bubbles: true, cancelable: true }));
      assert(!!addedRange && addedRange.toString() === '测试加粗文本', '选区兜底：applyFormat 用 savedRange 重建选区');
      ed3With.remove();
    } finally {
      win.getSelection = origGetSel;
    }
    holder3.remove();

    console.log('\n[14] v8.4.18 列表行为（回车/删除/重编号/光标布局）');
    // 14.1 G：列表行尾回车 → 新项保持列表类型
    const h41 = doc.createElement('div'); doc.body.appendChild(h41);
    const ed41 = App.Components.initEditor(h41, { initialData: [{ type: 'bullet', content: '项目甲' }], dataMode: 'json', placeholder: false });
    const bl41 = h41.querySelector('.notion-block--bullet .notion-editable');
    bl41.dispatchEvent(new win.KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }));
    const d41 = ed41.getEditorData();
    assert(d41.length === 2 && d41[1].type === 'bulletList', 'G: 列表行尾回车 → 新项保持列表类型（' + (d41[1] || {}).type + '）');
    // 14.2 G：空列表项回车 → 退出列表变普通文本
    const bl42 = h41.querySelectorAll('.notion-block--bullet .notion-editable')[1];
    bl42.dispatchEvent(new win.KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }));
    const d42 = ed41.getEditorData();
    assert(d42.length === 2 && d42[1].type === 'text', 'G: 空列表项回车 → 退出列表变普通文本（' + d42[1].type + '）');
    h41.remove();
    // 14.3 E：有序列表空白行后重新成为段起点（is-list-start）
    const h43 = doc.createElement('div'); doc.body.appendChild(h43);
    App.Components.initEditor(h43, { initialData: [
      { type: 'numbered', content: '甲' },
      { type: 'numbered', content: '乙' },
      { type: 'text', content: '' },
      { type: 'numbered', content: '丙' }
    ], dataMode: 'json', placeholder: false });
    const nums43 = h43.querySelectorAll('.notion-block--numbered');
    assert(nums43.length === 3, 'E: 3 个有序块渲染');
    assert(nums43[0].classList.contains('is-list-start'), 'E: 第 1 个有序块为列表段起点');
    assert(!nums43[1].classList.contains('is-list-start'), 'E: 第 2 个有序块同段连续（非起点）');
    assert(nums43[2].classList.contains('is-list-start'), 'E: 空白行后第 3 个有序块重新为段起点');
    // 14.4 B：列表编辑框不再是 flex 布局（光标不再飘到最前）
    const ed44 = h43.querySelector('.notion-block--numbered .notion-editable');
    const disp44 = win.getComputedStyle(ed44).display;
    assert(disp44 !== 'flex', 'B: 列表编辑框非 flex 布局（' + disp44 + '，光标不再飘到最前）');
    h43.remove();
    // 14.5 H：光标在格式块最前按删除 → 降级为普通文本且内容保留
    const h45 = doc.createElement('div'); doc.body.appendChild(h45);
    const ed45 = App.Components.initEditor(h45, { initialData: [{ type: 'numbered', content: '甲' }], dataMode: 'json', placeholder: false });
    const bl45 = h45.querySelector('.notion-block--numbered .notion-editable');
    const origSel45 = win.getSelection;
    win.getSelection = () => ({ rangeCount: 1, isCollapsed: true, getRangeAt: () => ({ startContainer: bl45, startOffset: 0 }), removeAllRanges() {}, addRange() {} });
    try {
      bl45.dispatchEvent(new win.KeyboardEvent('keydown', { key: 'Backspace', bubbles: true, cancelable: true }));
      const d45 = ed45.getEditorData();
      assert(d45[0].type === 'text', 'H: 块首按删除 → 格式块降级为普通文本（' + d45[0].type + '）');
      assert(d45[0].content === '甲', 'H: 降级后内容保留');
    } finally { win.getSelection = origSel45; }
    h45.remove();

    console.log('\n总计: ' + pass + ' 通过, ' + fail + ' 失败');
    if (fail > 0) { console.error('✗✗ 存在失败用例'); process.exit(1); }
    else { console.log('✓✓ 全部通过'); process.exit(0); }
  } catch (e) {
    console.error('测试执行异常:', e && e.stack || e);
    process.exit(1);
  }
}, 300);
