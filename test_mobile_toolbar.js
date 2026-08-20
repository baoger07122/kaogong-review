/**
 * Notion 移动端底部工具栏 + Bottom Sheet 专项验证
 * 运行：node test_mobile_toolbar.js
 */
const { JSDOM } = require('jsdom');
const fs = require('fs');
const path = require('path');

const html = fs.readFileSync(path.join(__dirname, 'index.html'), 'utf8');
const dom = new JSDOM(html, {
  runScripts: 'dangerously',
  pretendToBeVisual: true,
  url: 'https://localhost/',
  beforeParse(w) {
    w.matchMedia = w.matchMedia || function () { return { matches: false, addListener() {}, removeListener() {}, addEventListener() {}, removeEventListener() {}, dispatchEvent() { return false; } }; };
    w.requestAnimationFrame = (cb) => setTimeout(cb, 0);
    w.cancelAnimationFrame = (id) => clearTimeout(id);
    w.getSelection = () => ({ rangeCount: 0, removeAllRanges() {}, addRange() {}, getRangeAt() { return { toString: () => '' }; }, isCollapsed: true });
    // 模拟移动端视口（<768px）
    Object.defineProperty(w, 'innerWidth', { value: 390, writable: true, configurable: true });
    Object.defineProperty(w, 'innerHeight', { value: 844, writable: true, configurable: true });
    Object.defineProperty(w, 'ontouchstart', { value: null, writable: true, configurable: true });
  },
});

let pass = 0, fail = 0;
function assert(cond, msg) {
  if (cond) { pass++; console.log('  ✓ ' + msg); }
  else { fail++; console.error('  ✗ ' + msg); }
}

setTimeout(() => {
  const win = dom.window, doc = win.document;
  const App = win.App;
  try {
    const ed = App.Components.initEditor(doc.createElement('div'), {
      initialData: [
        { id: 'm1', type: 'text', content: '第一行', indent: 0, props: {} },
        { id: 'm2', type: 'toggle', content: '折叠', children: [{ id: 'm3', type: 'text', content: '子块', indent: 0, props: {} }], collapsed: false, indent: 0, props: {} },
      ],
      dataMode: 'json',
      onChange: () => {},
    });
    const wrap = doc.createElement('div');
    doc.body.appendChild(wrap);
    wrap.appendChild(ed.element);

    // 1. 底部工具栏挂载 + 常用功能按钮 + 顺序
    console.log('\n[1] 底部工具栏');
    const tb = doc.querySelector('.notion-mobile-toolbar');
    assert(!!tb, '底部工具栏已挂载到 body');
    if (tb) {
      const btns = tb.querySelectorAll('.notion-mobile-tool-btn');
      assert(btns.length === 6, '普通模式按钮数量 6 (' + btns.length + ')');
      const keys = Array.from(btns).map(b => b.dataset.key);
      const expected = ['undo','redo','format','blockfmt','insert','dismiss'];
      assert(JSON.stringify(keys) === JSON.stringify(expected), '按钮顺序正确: ' + keys.join(','));
      const masks = tb.querySelectorAll('.notion-mobile-toolbar__mask');
      assert(masks.length === 2, '左右渐变遮罩存在');
      // 按钮含 SVG 图标
      const hasSvg = btns[0].querySelector('svg');
      assert(!!hasSvg, '按钮使用内联 SVG 图标');
    }

    // 2. 点击 ➕ 打开块插入菜单
    console.log('\n[2] 块插入菜单');
    const plusBtn = tb && tb.querySelector('[data-key="insert"]');
    plusBtn.dispatchEvent(new win.MouseEvent('click', { bubbles: true }));
    setTimeout(() => {
      const sheet = doc.querySelector('.notion-mobile-sheet');
      assert(!!sheet, '点击 ➕ 弹出 Bottom Sheet');
      if (sheet) {
        assert(sheet.classList.contains('is-block'), '块插入菜单高度 65vh 类');
        const handle = sheet.querySelector('.notion-mobile-sheet__handle');
        assert(!!handle, '拖拽条存在');
        const items = sheet.querySelectorAll('.notion-mobile-sheet-item');
        assert(items.length === 21, '菜单项 21 个 (' + items.length + ')');
        const secTitles = Array.from(sheet.querySelectorAll('.notion-mobile-sheet-section-title')).map(x => x.textContent);
        assert(secTitles.indexOf('基本区块') >= 0 && secTitles.indexOf('媒体') >= 0, '分类标题: ' + secTitles.join(' | '));
        // 两列网格
        const grid = sheet.querySelector('.notion-mobile-sheet-grid');
        assert(!!grid && win.getComputedStyle(grid).gridTemplateColumns.split(' ').length >= 2, '两列网格布局');
        // 点击「折叠列表」插入
        const toggleItem = Array.from(items).find(x => x.textContent.indexOf('折叠列表') >= 0);
        toggleItem.dispatchEvent(new win.MouseEvent('click', { bubbles: true }));
        setTimeout(() => {
          const d = ed.getEditorData();
          const toggleCount = d.filter(b => b.type === 'toggle').length;
          assert(toggleCount === 2, '插入折叠块后 toggle 数量 2 (' + toggleCount + ')');
          // 面板关闭动画 260ms，此时已执行 forceCloseSheet 移除（等 300ms 确保移除）
          setTimeout(() => {
            assert(!doc.querySelector('.notion-mobile-sheet'), '点击菜单项后面板关闭');

            // 3. 点击 Aa 打开格式菜单
            console.log('\n[3] 文本格式菜单');
            const fmtBtn = doc.querySelector('.notion-mobile-toolbar [data-key="format"]');
            fmtBtn.dispatchEvent(new win.MouseEvent('click', { bubbles: true }));
            setTimeout(() => {
              const fsheet = doc.querySelector('.notion-mobile-sheet');
              assert(!!fsheet && fsheet.classList.contains('is-format'), '点击 Aa 弹出格式菜单 (45vh)');
              if (fsheet) {
                const fmtItems = fsheet.querySelectorAll('.notion-mobile-fmt-item');
                assert(fmtItems.length === 8, '格式选项 8 个 (' + fmtItems.length + ')');
                const cmds = Array.from(fmtItems).map(x => x.dataset.cmd);
                assert(cmds.join(',') === 'bold,italic,underline,strike,code,color-red,bg-yellow,link', '格式命令: ' + cmds.join(','));
                const title = fsheet.querySelector('.notion-mobile-fmt-title');
                assert(title && title.textContent === '格式', '标题「格式」');
              }
              // 4. 遮罩点击关闭
              const overlay = doc.querySelector('.notion-mobile-sheet-overlay');
              overlay.dispatchEvent(new win.MouseEvent('click', { bubbles: true }));
              setTimeout(() => {
                assert(!doc.querySelector('.notion-mobile-sheet-overlay'), '遮罩点击后关闭');

                // 5. 工具栏动作：撤销/重做（初始2块→插入1块=3→撤销2→重做3）
                console.log('\n[4] 工具栏动作');
                const undoBtn = doc.querySelector('.notion-mobile-toolbar [data-key="undo"]');
                undoBtn.dispatchEvent(new win.MouseEvent('click', { bubbles: true }));
                const dAfter = ed.getEditorData();
                assert(dAfter.length === 2, '撤销后回到 2 块 (' + dAfter.length + ')');
                const redoBtn = doc.querySelector('.notion-mobile-toolbar [data-key="redo"]');
                redoBtn.dispatchEvent(new win.MouseEvent('click', { bubbles: true }));
                assert(ed.getEditorData().length === 3, '重做后回到 3 块');

                // 6. HTML 富文本进入表格后，仍复用同一条底部胶囊栏切换为表格模式
                const htmlEd = App.Components.htmlEditor('<table><tbody><tr><td>甲</td><td>乙</td></tr></tbody></table>', { placeholder: false });
                wrap.appendChild(htmlEd.element);
                const firstCell = htmlEd.area.querySelector('td');
                firstCell.dispatchEvent(new win.MouseEvent('click', { bubbles: true }));
                const tableKeys = Array.from(tb.querySelectorAll('.notion-mobile-tool-btn')).map(b => b.dataset.key);
                assert(tb.dataset.mode === 'table', '进入表格单元格后工具栏切换为表格模式');
                assert(tableKeys.join(',') === 'table-add-row,table-add-col,table-delete-row,table-delete-col,table-header,table-align,table-delete,table-done', '表格模式按钮顺序正确');
                tb.querySelector('[data-key="table-add-row"]').dispatchEvent(new win.MouseEvent('click', { bubbles: true }));
                assert(htmlEd.area.querySelectorAll('tr').length === 2, '表格模式可以增加一行');
                tb.querySelector('[data-key="table-add-col"]').dispatchEvent(new win.MouseEvent('click', { bubbles: true }));
                assert(htmlEd.area.querySelector('tr').cells.length === 3, '表格模式可以增加一列');
                tb.querySelector('[data-key="table-header"]').dispatchEvent(new win.MouseEvent('click', { bubbles: true }));
                assert(!!htmlEd.area.querySelector('thead th'), '表格模式可以切换表头');
                tb.querySelector('[data-key="table-delete-col"]').dispatchEvent(new win.MouseEvent('click', { bubbles: true }));
                tb.querySelector('[data-key="table-delete-row"]').dispatchEvent(new win.MouseEvent('click', { bubbles: true }));
                assert(htmlEd.area.querySelectorAll('tr').length === 1 && htmlEd.area.querySelector('tr').cells.length === 2, '表格模式可以删除一行和一列');
                tb.querySelector('[data-key="table-done"]').dispatchEvent(new win.MouseEvent('click', { bubbles: true }));
                assert(tb.dataset.mode === 'default', '点击完成后恢复普通工具栏');
                console.log('\n===== 移动端专项: ' + pass + ' 通过, ' + fail + ' 失败 =====');
                process.exit(fail > 0 ? 1 : 0);
              }, 300);
            }, 100);
          }, 300);
        }, 100);
      } else {
        process.exit(1);
      }
    }, 100);
  } catch (e) {
    console.error('测试异常:', e);
    process.exit(1);
  }
}, 900);
