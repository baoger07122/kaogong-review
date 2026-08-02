/**
 * 块编辑器升级验证脚本（Node + jsdom 模拟浏览器环境）
 * 验证：
 *  1. initEditor / notionEditor 能正常创建
 *  2. getEditorData / setEditorData JSON 往返
 *  3. Slash 菜单过滤
 *  4. 类型映射（heading1 -> h1 等）
 * 运行：node test_editor_upgrade.js
 */
const { JSDOM } = require('jsdom');
const fs = require('fs');
const path = require('path');

// 读取构建产物 index.html，用 jsdom 加载（内联 script 会自动执行）
const html = fs.readFileSync(path.join(__dirname, 'index.html'), 'utf8');
const dom = new JSDOM(html, {
  runScripts: 'dangerously',
  pretendToBeVisual: true,
  url: 'https://localhost/',
  beforeParse(window) {
    // jsdom 缺少的浏览器 API polyfill
    window.matchMedia = window.matchMedia || function (q) {
      return {
        matches: false, media: q, addListener() {}, removeListener() {},
        addEventListener() {}, removeEventListener() {}, dispatchEvent() { return false; },
      };
    };
    window.requestAnimationFrame = (cb) => setTimeout(cb, 0);
    window.cancelAnimationFrame = (id) => clearTimeout(id);
    window.getSelection = () => ({
      rangeCount: 0, removeAllRanges() {}, addRange() {}, getRangeAt() { return { toString: () => '' }; }, isCollapsed: true,
    });
    window.innerWidth = 375;
    window.innerHeight = 812;
  },
});

let pass = 0, fail = 0;
function assert(cond, msg) {
  if (cond) { pass++; console.log('  ✓ ' + msg); }
  else { fail++; console.error('  ✗ ' + msg); }
}

const win = dom.window;
const doc = win.document;

// 等脚本执行完
setTimeout(() => {
  try {
    const App = win.App;
    if (!App) { console.error('App 未定义'); process.exit(1); }

    // ===== 1. 基础 API 存在 =====
    console.log('\n[1] 基础 API');
    assert(typeof App.Components.notionEditor === 'function', 'notionEditor 存在');
    assert(typeof App.Components.initEditor === 'function', 'initEditor 存在');

    // ===== 2. JSON 数据往返 =====
    console.log('\n[2] JSON 数据往返');
    const container = doc.createElement('div');
    doc.body.appendChild(container);
    const jsonData = [
      { id: 'a1', type: 'heading1', content: '标题一', indent: 0, props: { color: '' } },
      { id: 'a2', type: 'text', content: '普通文本 **加粗**', indent: 1, props: { color: '#E03131' } },
      { id: 'a3', type: 'bulletList', content: '列表项', indent: 0, props: {} },
      { id: 'a4', type: 'todo', content: '待办', checked: true, indent: 0, props: {} },
      { id: 'a5', type: 'toggle', content: '折叠标题', detail: '折叠详情内容', collapsed: true, indent: 0, props: {} },
      { id: 'a6', type: 'quote', content: '引用内容', indent: 0, props: {} },
      { id: 'a7', type: 'divider', content: '', indent: 0, props: {} },
      { id: 'a8', type: 'code', content: 'const x = 1;', indent: 0, props: {} },
    ];
    const editor = App.Components.initEditor(container, {
      initialData: jsonData,
      dataMode: 'json',
      onChange: () => {},
    });
    assert(!!editor, 'initEditor 返回编辑器对象');
    assert(typeof editor.getEditorData === 'function', 'getEditorData 可用');
    assert(typeof editor.setEditorData === 'function', 'setEditorData 可用');

    const dataOut = editor.getEditorData();
    assert(Array.isArray(dataOut), 'getEditorData 返回数组');
    assert(dataOut.length === 8, '块数量正确 (' + dataOut.length + ' 个)');
    const h1 = dataOut.find(b => b.id === 'a1');
    assert(h1 && h1.type === 'heading1' && h1.content === '标题一', 'heading1 往返正确');
    const todo = dataOut.find(b => b.id === 'a4');
    assert(todo && todo.checked === true, 'todo checked 往返正确');
    const toggle = dataOut.find(b => b.id === 'a5');
    assert(toggle && toggle.type === 'toggle' && toggle.collapsed === true, 'toggle collapsed 往返正确');
    assert(toggle && toggle.content === '折叠标题' && toggle.detail === '折叠详情内容', 'toggle summary/detail 往返正确');
    const textB = dataOut.find(b => b.id === 'a2');
    assert(textB && textB.indent === 1, 'indent 往返正确');
    const codeB = dataOut.find(b => b.id === 'a8');
    assert(codeB && codeB.content === 'const x = 1;', 'code 往返正确');

    // ===== 3. Markdown 兼容（旧接口） =====
    console.log('\n[3] Markdown 兼容');
    const md = editor.getContent();
    assert(typeof md === 'string' && md.indexOf('# 标题一') === 0, 'getContent 导出 Markdown: ' + JSON.stringify(md.slice(0, 20)));
    assert(md.indexOf('- [x] 待办') >= 0, 'todo 导出为 - [x]');
    assert(md.indexOf('> ▸ 折叠标题') >= 0, 'toggle 导出为 > ▸');

    // ===== 4. Slash 菜单过滤逻辑（直接调用内部函数不方便，改为验证 DOM 结构） =====
    console.log('\n[4] DOM 结构');
    const editable = container.querySelector('.notion-editable');
    assert(!!editable, '存在可编辑块');
    const blocks = container.querySelectorAll('.notion-block');
    assert(blocks.length === 8, '渲染 8 个块 DOM');
    const handles = container.querySelectorAll('.notion-block__handle');
    assert(handles.length === 8, '每个块都有手柄');

    // ===== 5. onChange 回调（md 模式） =====
    console.log('\n[5] onChange 回调');
    let cbGot = null;
    const ed2 = App.Components.initEditor(doc.createElement('div'), {
      initialData: '# 测试',
      onChange: (d) => { cbGot = d; },
    });
    doc.body.appendChild(ed2.element);
    assert(!!ed2.element, 'md 模式编辑器创建成功');

    // ===== 6. 拖拽排序模拟 =====
    console.log('\n[6] 拖拽排序模拟');
    // jsdom 无布局引擎，getBoundingClientRect 全为 0，需 mock 每个块的 y 坐标
    const blockEls = Array.from(container.querySelectorAll('.notion-block'));
    blockEls.forEach((b, i) => {
      b.getBoundingClientRect = () => ({ top: 40 + i * 60, bottom: 100 + i * 60, left: 0, right: 720, width: 720, height: 60 });
    });
    // 用 pointer 事件模拟拖拽第一块到第三块位置
    const firstBlock = container.querySelector('.notion-block[data-index="0"]');
    const firstHandle = firstBlock.querySelector('.notion-block__handle');
    firstHandle.dispatchEvent(new win.PointerEvent('pointerdown', { bubbles: true, clientX: 10, clientY: 40 }));
    // 移动超过阈值到第三块区域 (y≈160)
    win.dispatchEvent(new win.PointerEvent('pointermove', { clientX: 12, clientY: 160 }));
    const placeholder = container.querySelector('.notion-drag-placeholder');
    assert(!!placeholder, '拖拽中显示占位线');
    win.dispatchEvent(new win.PointerEvent('pointerup', { clientX: 12, clientY: 160 }));
    assert(!container.querySelector('.notion-drag-placeholder'), '松开后占位线消失');
    const afterDrag = editor.getEditorData();
    assert(afterDrag[0].id !== 'a1' || afterDrag[2].id === 'a1', '拖拽后顺序改变: ' + afterDrag.map(b => b.id).join(','));

    // ===== 7. Slash 菜单键盘导航 =====
    console.log('\n[7] Slash 菜单键盘导航');
    const ed3 = App.Components.initEditor(doc.createElement('div'), {
      initialData: '',
      onChange: () => {},
    });
    const ed3Wrap = doc.createElement('div');
    doc.body.appendChild(ed3Wrap);
    ed3Wrap.appendChild(ed3.element);
    // 聚焦第一个可编辑块并输入 "/" 触发菜单
    const firstEditable = ed3Wrap.querySelector('.notion-editable');
    firstEditable.focus();
    // 模拟输入 "/"（input 事件由编辑器处理）
    firstEditable.textContent = '/';
    firstEditable.dispatchEvent(new win.Event('input', { bubbles: true }));
    // jsdom 中 getBoundingClientRect 为 0，菜单会出现但位置在 0,0，不影响逻辑
    const slashMenu = ed3Wrap.querySelector('.notion-slash-menu');
    assert(!!slashMenu, '输入 / 弹出 slash 菜单');
    const items = ed3Wrap.querySelectorAll('.notion-slash-item');
    assert(items.length > 0, '菜单有候选项 (' + items.length + ')');
    // 按 ArrowDown 高亮第二项
    firstEditable.dispatchEvent(new win.KeyboardEvent('keydown', { key: 'ArrowDown', bubbles: true, cancelable: true }));
    const active1 = ed3Wrap.querySelector('.notion-slash-item.ne-active');
    assert(!!active1 && active1 === items[1], 'ArrowDown 高亮第 2 项');
    // 再按 ArrowDown 到第 3 项
    firstEditable.dispatchEvent(new win.KeyboardEvent('keydown', { key: 'ArrowDown', bubbles: true, cancelable: true }));
    const active2 = ed3Wrap.querySelector('.notion-slash-item.ne-active');
    assert(active2 === items[2], 'ArrowDown 高亮第 3 项');
    // Esc 关闭
    firstEditable.dispatchEvent(new win.KeyboardEvent('keydown', { key: 'Escape', bubbles: true, cancelable: true }));
    assert(!ed3Wrap.querySelector('.notion-slash-menu'), 'Esc 关闭菜单');
    // 过滤：重新输入 / 打开菜单，再输入 /h 只显示标题
    firstEditable.textContent = '/h';
    firstEditable.dispatchEvent(new win.Event('input', { bubbles: true }));
    const filtered = ed3Wrap.querySelectorAll('.notion-slash-item');
    assert(filtered.length >= 1 && filtered[0].dataset.type === 'h1', '输入 /h 过滤出标题1 (' + Array.from(filtered).map(x => x.dataset.type).join(',') + ')');

    // ===== 8. 手柄菜单（复制/缩进/转换） =====
    console.log('\n[8] 手柄菜单');
    const ed4 = App.Components.initEditor(doc.createElement('div'), {
      initialData: [
        { id: 'x1', type: 'text', content: '第一行', indent: 0, props: {} },
        { id: 'x2', type: 'text', content: '第二行', indent: 0, props: {} },
      ],
      onChange: () => {},
    });
    const ed4Wrap = doc.createElement('div');
    doc.body.appendChild(ed4Wrap);
    ed4Wrap.appendChild(ed4.element);
    const h1Handle = ed4Wrap.querySelector('.notion-block[data-index="0"] .notion-block__handle');
    h1Handle.dispatchEvent(new win.MouseEvent('click', { bubbles: true }));
    const menu = ed4Wrap.querySelector('.notion-handle-menu');
    assert(!!menu, '点击手柄弹出菜单');
    const menuLabels = Array.from(menu.querySelectorAll('.notion-handle-item')).map(x => x.textContent);
    assert(menuLabels.some(l => l.indexOf('复制块') >= 0), '菜单含复制块');
    assert(menuLabels.some(l => l.indexOf('转换为') >= 0), '菜单含转换类型');
    assert(menuLabels.some(l => l.indexOf('增加缩进') >= 0), '菜单含增加缩进');
    assert(menuLabels.some(l => l.indexOf('删除块') >= 0), '菜单含删除块');
    // 点击复制块（按文本找到）
    const copyItem = Array.from(menu.querySelectorAll('.notion-handle-item')).find(x => x.textContent.indexOf('复制块') >= 0);
    copyItem.dispatchEvent(new win.MouseEvent('click', { bubbles: true }));
    const data4 = ed4.getEditorData();
    assert(data4.length === 3 && data4[1].content === '第一行', '复制块后数量 3 且复制内容正确');

    console.log('\n===== 结果: ' + pass + ' 通过, ' + fail + ' 失败 =====');
    process.exit(fail > 0 ? 1 : 0);
  } catch (e) {
    console.error('测试异常:', e);
    process.exit(1);
  }
}, 1000);
