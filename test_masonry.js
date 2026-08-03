/* JS 瀑布流错题列表 专项测试 */
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
    w.innerWidth = 390;   // 手机宽度 → 2 列
    w.screen = { width: 390, height: 844 };
  }
});

setTimeout(async () => {
  const win = dom.window, doc = win.document, App = win.App;

  try {
    console.log('[1] 手机 2 列瀑布流');
    const holder = doc.createElement('div');
    doc.body.appendChild(holder);
    const inst = App.Components.masonryGrid(holder, { onOpen: () => {} });
    assert(inst.getColumnCount() === 2, '390px 宽 → 2 列');
    const items = [
      { id: 'a', question: '题目A', knowledgePoints: ['考点1'], errorCause: '错因1', createdAt: new Date().toISOString() },
      { id: 'b', question: '题目B', knowledgePoints: ['考点2'], errorCause: '错因2', createdAt: new Date().toISOString() },
      { id: 'c', question: '题目C', knowledgePoints: ['考点3'], errorCause: '错因3', createdAt: new Date().toISOString() },
      { id: 'd', question: '题目D', knowledgePoints: ['考点4'], errorCause: '错因4', createdAt: new Date().toISOString() },
      { id: 'e', question: '题目E', knowledgePoints: ['考点5'], errorCause: '错因5', createdAt: new Date().toISOString() }
    ];
    inst.render(items, false);
    const cols = holder.querySelectorAll('.error-masonry__col');
    assert(cols.length === 2, '渲染 2 列容器');
    const totalCards = holder.querySelectorAll('.error-masonry__card').length;
    assert(totalCards === 5, '5 张卡片全部渲染');
    // 卡片被分布到各列（最短列优先）
    const col1Count = cols[0].querySelectorAll('.error-masonry__card').length;
    const col2Count = cols[1].querySelectorAll('.error-masonry__card').length;
    assert(col1Count + col2Count === 5, '卡片分布在两列中');
    // 卡片展示规则：考点+错因同行、日期末行
    const firstCard = holder.querySelector('.error-masonry__card');
    assert(!!firstCard.querySelector('.error-gallery-card__tagrow'), '卡片有标签行');
    const dateEl = firstCard.querySelector('.error-gallery-card__date');
    assert(!!dateEl, '卡片有日期');
    assert(Array.from(firstCard.children).indexOf(dateEl) === firstCard.children.length - 1, '日期在最后');

    console.log('\n[2] 图片卡片：多图纵排 + 懒加载');
    const items2 = [
      { id: 'x', question: '带图题', knowledgePoints: [], errorCause: '', createdAt: new Date().toISOString(),
        images: ['data:image/png;base64,AAAA', 'data:image/png;base64,BBBB'] }
    ];
    inst.render(items2, false);
    const imgCard = holder.querySelector('.error-masonry__card');
    const imgs = imgCard.querySelectorAll('img');
    assert(imgs.length === 2, '2 张图片都渲染');
    assert(imgs[0].getAttribute('loading') === 'lazy', '首图懒加载');
    // 卡片无图时只渲染文字
    const items3 = [{ id: 'y', question: '纯文字题', knowledgePoints: [], errorCause: '', createdAt: new Date().toISOString() }];
    inst.render(items3, false);
    const textCard = holder.querySelector('.error-masonry__card');
    assert(textCard.querySelectorAll('img').length === 0, '无图卡片无 img 元素');

    console.log('\n[3] resize 重排（手机→平板 3 列）');
    win.innerWidth = 800;
    win.dispatchEvent(new win.Event('resize'));
    await new Promise(r => setTimeout(r, 350));   // 防抖 250ms
    const cols2 = holder.querySelectorAll('.error-masonry__col');
    assert(cols2.length === 3, '800px 宽 → 3 列');
    assert(holder.querySelectorAll('.error-masonry__card').length === 1, '重排后卡片仍在');

    console.log('\n[4] destroy 解绑 resize 监听');
    inst.destroy();
    // destroy 后再 resize 不应重排（实例已销毁）
    win.innerWidth = 1200;
    win.dispatchEvent(new win.Event('resize'));
    await new Promise(r => setTimeout(r, 350));
    const cols3 = holder.querySelectorAll('.error-masonry__col');
    assert(cols3.length === 3, '销毁后列数不变（监听已解绑）');

    console.log('\n[5] 空列表渲染');
    const holder2 = doc.createElement('div');
    doc.body.appendChild(holder2);
    const inst2 = App.Components.masonryGrid(holder2, { onOpen: () => {} });
    inst2.render([], false);
    assert(holder2.querySelectorAll('.error-masonry__col').length === 4, '空列表也有列容器（当前宽 1200 → 4 列）');
    assert(holder2.querySelectorAll('.error-masonry__card').length === 0, '空列表无卡片');
    inst2.destroy();

    console.log('\n===== 瀑布流专项: ' + pass + ' 通过, ' + fail + ' 失败 =====');
    process.exit(fail > 0 ? 1 : 0);
  } catch (e) {
    console.error('测试异常:', e && e.stack || e);
    process.exit(1);
  }
}, 1000);
