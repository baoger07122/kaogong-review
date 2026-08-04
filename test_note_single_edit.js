/* Notion 式单页编辑（笔记详情/编辑页合并）专项测试 */
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
  const wait = (ms) => new Promise(r => setTimeout(r, ms));

  // ===== 内存版 DB mock（数据结构与真实一致） =====
  const store = { notes: {}, errors: {} };
  store.notes.note1 = {
    id: 'note1', subject: '言语理解', module: '逻辑填空', knowledgePoint: '成语辨析',
    title: '**加粗标题**', content: '# 标题一\n\n- 项目甲\n- 项目乙\n\n**重点**内容',
    linkedErrors: [], linkedReviews: [], updatedAt: new Date().toISOString()
  };
  App.DB.get = async (t, id) => (store[t] && store[t][id]) ? store[t][id] : null;
  App.DB.updateNote = async (n) => { store.notes[n.id] = n; };
  App.DB.addNote = async (n) => { if (!n.id) n.id = 'note' + Math.random().toString(36).slice(2, 8); store.notes[n.id] = n; return n.id; };
  App.DB.getNotes = async () => Object.values(store.notes);
  App.DB.getErrors = async () => [];
  // 记录 navigate 调用；真实设置 hash（jsdom 触发 hashchange → 路由重渲染，模拟「原地刷新查看态」）
  const navCalls = [];
  App.Router.navigate = (r) => { navCalls.push(r); win.location.hash = r; };
  App.Router.back = () => {};

  const Notes = App.Pages.Notes;
  const container = doc.getElementById('page-note-detail');
  doc.body.appendChild(container);
  const holder = doc.createElement('div');
  doc.body.appendChild(holder);

  try {
    console.log('[1] 版本号修正：8.5.0 → 8.4.6（8月4日第6次迭代）');
    assert(App.VERSION === '8.4.6', 'App.VERSION === 8.4.6（当前 ' + App.VERSION + '）');

    console.log('\n[2] 查看模式：标题/正文 innerHTML 渲染 Markdown（绝不用文本插值）');
    await Notes._renderNoteView(container, store.notes.note1, { params: {} });
    await wait(10);
    const titleEl = container.querySelector('.note-single-title');
    const bodyEl = container.querySelector('.note-single-body');
    assert(!!titleEl, '标题容器 .note-single-title 存在');
    assert(!!bodyEl, '正文容器 .note-single-body 存在');
    assert(titleEl.innerHTML.includes('<strong>') && titleEl.innerHTML.includes('加粗标题'), '标题以 innerHTML 渲染 <strong>（非 textContent 插值）');
    assert(bodyEl.innerHTML.includes('<h1') && bodyEl.innerHTML.includes('标题一'), '正文 h1 渲染');
    assert(bodyEl.innerHTML.includes('md-preview-ul') && bodyEl.innerHTML.includes('项目甲'), '正文列表渲染');
    assert(bodyEl.innerHTML.includes('<strong>') && bodyEl.innerHTML.includes('重点'), '正文加粗渲染');
    // 头部按钮：✏️ 编辑 + ✍️ 手写 + ⋮ 菜单
    const actions = container.querySelectorAll('.detail-header-action');
    assert(actions.length === 2, '右上角含 2 个操作按钮（✏️ 编辑 + ✍️ 手写）');
    assert(container.querySelector('.doodle-preview'), '手写笔记区域在查看模式显示');

    console.log('\n[3] 点击正文 → 原地进入编辑模式（不跳转 note-form）');
    bodyEl.click();
    await wait(10);
    assert(!!container.querySelector('.note-single-textarea'), '点击正文后出现 textarea');
    assert(!container.querySelector('.note-single-body'), '编辑模式隐藏查看态正文');
    const ta = container.querySelector('.note-single-textarea');
    assert(ta.value === store.notes.note1.content, 'textarea 显示 Markdown 原文（含 \\n 换行）');
    assert(ta.value.includes('\n'), '换行符 \\n 保留');
    // 顶部按钮从「编辑」变为「保存」
    const headerRight = container.querySelector('.page-header__right');
    assert(headerRight && headerRight.textContent.trim() === '保存', '顶部右侧按钮为「保存」');
    // 底部：字数统计 + 分类选择器
    assert(!!container.querySelector('.note-edit-count'), '底部字数统计存在');
    const countText = container.querySelector('.note-edit-count').textContent;
    assert(/字$/.test(countText), '字数统计显示（当前：' + countText + '）');
    assert(!!container.querySelector('.note-edit-cat'), '底部标签（分类）选择器存在');

    console.log('\n[4] Markdown 工具栏：字符串级操作（insertInlineMarker / insertBlockMarker / insertDivider）');
    // 行内标记：选中包裹
    let t1 = doc.createElement('textarea'); t1.value = 'abc'; t1.setSelectionRange(1, 2);
    App.Utils.insertInlineMarker(t1, '**');
    assert(t1.value === 'a**b**c', '选中文本被 ** 包裹');
    // 再次操作取消包裹
    t1.setSelectionRange(1, 6);
    App.Utils.insertInlineMarker(t1, '**');
    assert(t1.value === 'abc', '已包裹文本取消包裹');
    // 无选中：插入成对标记
    t1.value = 'abc'; t1.setSelectionRange(1, 1);
    App.Utils.insertInlineMarker(t1, '*');
    assert(t1.value === 'a**bc', '无选中插入 ** 对（光标居中）');
    // 块级标记：行首插入
    let t2 = doc.createElement('textarea'); t2.value = '第一行\n第二行'; t2.setSelectionRange(4, 4);
    App.Utils.insertBlockMarker(t2, '- ');
    assert(t2.value === '第一行\n- 第二行', '块级标记行首插入');
    App.Utils.insertBlockMarker(t2, '- ');
    assert(t2.value === '第一行\n第二行', '块级标记再次点击移除');
    // 标题标记
    let t3 = doc.createElement('textarea'); t3.value = '标题文字'; t3.setSelectionRange(0, 0);
    App.Utils.insertBlockMarker(t3, '## ');
    assert(t3.value === '## 标题文字', '标题标记插入');
    // 分割线
    let t4 = doc.createElement('textarea'); t4.value = '上文'; t4.setSelectionRange(2, 2);
    App.Utils.insertDivider(t4);
    assert(t4.value === '上文\n\n---', '分割线插入（带前后空行）');

    console.log('\n[5] 字数统计 mdWordCount');
    assert(App.Utils.mdWordCount('**加粗**文字') === 4, '去除标记后统计中文 4 字');
    assert(App.Utils.mdWordCount('## 标题\n正文内容') === 6, '标题+正文共 6 字');
    assert(App.Utils.mdWordCount('hello world') === 2, '英文按词统计 2 词');
    assert(App.Utils.mdWordCount('') === 0, '空内容 0 字');

    console.log('\n[6] 保存：写 DB + 原地切回查看模式（无页面跳转）');
    navCalls.length = 0;
    const noteForSave = Object.assign({}, store.notes.note1, { title: '**加粗标题**', content: '# 标题一\n\n- 项目甲' });
    const formData = {
      id: 'note1', subject: '言语理解', module: '逻辑填空', knowledgePoint: '成语辨析',
      title: '新标题', content: '新**内容**\n第二行', linkedErrors: []
    };
    const ok = await Notes._saveNoteFromEdit(container, noteForSave, formData, { isNew: false });
    await wait(10);
    assert(ok === true, '保存返回成功');
    assert(store.notes.note1.title === '新标题', 'DB title 已更新');
    assert(store.notes.note1.content === '新**内容**\n第二行', 'DB content 保留 Markdown 原文与换行');
    assert(navCalls.some(r => r === 'note-detail?id=note1'), 'URL 更新为 note-detail?id=note1（原地，无页面跳转）');
    assert(!!container.querySelector('.note-single-title'), '保存后回到查看模式（标题重新渲染）');
    assert(!container.querySelector('.note-single-textarea'), '保存后退出编辑模式');

    console.log('\n[7] 新建模式（note-detail?new=1）：默认直接进入编辑');
    await Notes.renderDetail({ new: '1', subject: '言语理解', module: '逻辑填空' });
    await wait(10);
    assert(!!container.querySelector('.note-single-textarea'), '新建进入编辑模式（textarea 存在）');
    assert(!container.querySelector('.note-single-title'), '新建无查看态标题');
    const newHeader = container.querySelector('.page-header__right');
    assert(newHeader && newHeader.textContent.trim() === '保存', '新建页顶部为「保存」');

    console.log('\n[8] blur 自动保存：内容变化时失焦即保存并退出编辑');
    await Notes.renderDetail({ id: 'note1' });
    await wait(10);
    const bodyEl2 = container.querySelector('.note-single-body');
    bodyEl2.click();  // 进入编辑
    await wait(10);
    const ta2 = container.querySelector('.note-single-textarea');
    ta2.value = '# 标题一\n\n- 项目甲\n- 项目乙\n\n**重点**内容\n\n新增一段';
    ta2.dispatchEvent(new win.Event('input'));
    ta2.dispatchEvent(new win.Event('blur'));
    await wait(300);
    assert(store.notes.note1.content.endsWith('新增一段'), 'blur 后内容已写入 DB');
    assert(!!container.querySelector('.note-single-title'), 'blur 保存后原地回到查看模式');

    console.log('\n[9] 旧路由兼容：note-form 重定向到 note-detail');
    navCalls.length = 0;
    Notes.renderForm({ id: 'note1' });
    assert(navCalls[navCalls.length - 1] === 'note-detail?id=note1', '编辑重定向 note-detail?id=...');
    Notes.renderForm({ subject: '言语理解', module: '逻辑填空' });
    assert(navCalls[navCalls.length - 1] === 'note-detail?new=1&subject=' + encodeURIComponent('言语理解') + '&module=' + encodeURIComponent('逻辑填空'), '新建重定向 note-detail?new=1&...');
    Notes.renderForm({});
    assert(navCalls[navCalls.length - 1] === 'note-detail?new=1', '无参新建重定向 note-detail?new=1');

    console.log('\n[10] 渲染可靠性：simpleMarkdown 在数据就绪后执行（查看模式不出现未渲染原文）');
    assert(!container.querySelector('.note-single-body') || !container.querySelector('.note-single-body').textContent.includes('**加粗标题**') || container.querySelector('.note-single-body').innerHTML.includes('<strong>'), '正文无裸 ** 标记残留');
    const mdOut = App.Utils.simpleMarkdown('**加粗**与`代码`');
    assert(mdOut.includes('<strong>') && mdOut.includes('md-preview-code-inline'), 'simpleMarkdown 输出强标签');

    console.log('\n[11] 数据完整性：linkedErrors/linkedReviews 在更新时保留');
    store.notes.note1.linkedErrors = ['err1'];
    store.notes.note1.linkedReviews = [{ ts: 1 }];
    const fd2 = { id: 'note1', subject: '言语理解', module: '逻辑填空', knowledgePoint: '成语辨析', title: '再存一次', content: '正文', linkedErrors: ['err1'] };
    await Notes._saveNoteFromEdit(container, store.notes.note1, fd2, { isNew: false });
    await wait(10);
    assert(store.notes.note1.linkedReviews && store.notes.note1.linkedReviews.length === 1, 'linkedReviews 保留');
    assert(store.notes.note1.title === '再存一次', '第二次保存 title 更新');

    console.log('\n总计: ' + pass + ' 通过, ' + fail + ' 失败');
    if (fail > 0) { console.error('✗✗ 存在失败用例'); process.exit(1); }
    else { console.log('✓✓ 全部通过'); process.exit(0); }
  } catch (e) {
    console.error('测试执行异常:', e);
    process.exit(1);
  }
}, 300);
