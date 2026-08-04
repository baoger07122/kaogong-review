/* 速算 v8.5.0：数字键盘 + 涂鸦 专项测试 */
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
    w.innerWidth = 390; w.innerHeight = 844;
    w.prompt = () => null;
    w.confirm = () => true;
  }
});

setTimeout(async () => {
  const win = dom.window, doc = win.document, App = win.App;
  const SC = App.Pages.SpeedCalc;
  const page = doc.getElementById('page-speed-calc');

  try {
    console.log('[1] 竞速模式：键盘布局 + 模式差异');
    SC.state.view = 'home'; SC.state.type = 'add3'; SC.state.mode = 'race';
    await SC.render({});
    page.querySelector('.sc-btn--primary').dispatchEvent(new win.MouseEvent('click', { bubbles: true }));
    // 键盘 15 键
    const btns = Array.from(page.querySelectorAll('.sc-numpad__btn'));
    assert(btns.length === 15, '3×5=15 键');
    // 竞速：首行是「重开」
    assert(btns[0].textContent === '重开', '竞速模式左上角=重开');
    assert(btns[1].textContent === '清空', '清空键');
    assert(btns[2].textContent === '⌫', '退格键');
    assert(btns[btns.length - 1].textContent === '确认', '确认键');
    assert(btns[btns.length - 1].classList.contains('sc-numpad__btn--confirm'), '确认键蓝色样式');
    assert(btns[0].classList.contains('sc-numpad__btn--func'), '功能键样式');
    // 底部进度 1/10
    assert(page.querySelector('.sc-numpad__footer').textContent.includes('1/10'), '底部进度 1/10');
    // 竞速信息：计时器+标准
    assert(!!page.querySelector('.sc-race-timer'), '竞速总计时器');
    assert(page.querySelector('.sc-race-standard').textContent.includes('合格'), '合格标准显示');
    // 题目大字号 42px
    const exprStyle = win.getComputedStyle(page.querySelector('.sc-practice__expr')).fontSize;
    assert(exprStyle === '42px', '题目字号 42px (' + exprStyle + ')');
    // 键盘高度 42vh
    const numpadStyle = win.getComputedStyle(page.querySelector('.sc-numpad')).height;
    assert(numpadStyle.includes('px') || numpadStyle.includes('vh'), '键盘有高度');
    // 涂鸦按钮
    assert(!!page.querySelector('.sc-doodle-btn'), '涂鸦按钮存在');

    console.log('\n[2] 键盘输入逻辑：退格/清空/防重复小数点/12位限制');
    const pressKey = (k) => {
      const btn = Array.from(page.querySelectorAll('.sc-numpad__btn')).find(b => b.textContent === k || (b.textContent === '确认' && k === 'confirm'));
      btn && btn.dispatchEvent(new win.MouseEvent('click', { bubbles: true }));
    };
    // 输入 12 位后第 13 位被忽略
    SC.state.currentInput = '';
    for (let i = 0; i < 14; i++) pressKey('9');
    assert(SC.state.currentInput.length === 12, '输入限制 12 位');
    // 退格
    pressKey('⌫');
    assert(SC.state.currentInput.length === 11, '退格删除一位');
    // 清空
    pressKey('清空');
    assert(SC.state.currentInput === '', '清空');
    // 重复小数点
    pressKey('.'); pressKey('.');
    assert(SC.state.currentInput === '.', '防止重复小数点');

    console.log('\n[3] 估算题型 ±3% 误差判定');
    SC.state.view = 'practice'; SC.state.mode = 'train'; SC.state.type = 'mulEst';
    SC.state.idx = 0;
    SC.state.questions = [{ expr: '23 × 47 ≈', answer: 1000, user: '', correct: null }];
    await SC.render({});
    // 输入 1030（3% 内）→ 对
    SC.state.currentInput = '1030';
    const pressC = () => {
      const btn = Array.from(page.querySelectorAll('.sc-numpad__btn')).find(b => b.textContent === '确认');
      btn && btn.dispatchEvent(new win.MouseEvent('click', { bubbles: true }));
    };
    pressC();
    assert(SC.state.questions[0].correct === true, '估算题 ±3% 内判对');
    // 输入 1200 → 错
    SC.state.questions = [{ expr: '23 × 47 ≈', answer: 1000, user: '', correct: null }];
    SC.state.idx = 0;
    await SC.render({});
    SC.state.currentInput = '1200';
    pressC();
    assert(SC.state.questions[0].correct === false, '估算题超 3% 判错');

    console.log('\n[4] 精确题不容忍误差');
    SC.state.view = 'practice'; SC.state.mode = 'train'; SC.state.type = 'add3';
    SC.state.idx = 0;
    SC.state.questions = [{ expr: '123 + 456', answer: 579, user: '', correct: null }];
    await SC.render({});
    SC.state.currentInput = '580';
    pressC();
    assert(SC.state.questions[0].correct === false, '精确题 ±1 判错');

    console.log('\n[5] 训练模式：跳过键 + 进度 1/∞');
    SC.state.view = 'practice'; SC.state.mode = 'train'; SC.state.type = 'add3';
    SC.state.questions = [SC.TYPES.add3.gen(), SC.TYPES.add3.gen()];
    SC.state.questions.forEach(q => { q.user = ''; q.correct = null; });
    SC.state.idx = 0;
    await SC.render({});
    const trainBtns = Array.from(page.querySelectorAll('.sc-numpad__btn'));
    assert(trainBtns[0].textContent === '跳过', '训练模式左上角=跳过');
    assert(page.querySelector('.sc-numpad__footer').textContent.includes('1/∞'), '训练模式进度 1/∞');
    // 点击跳过 → 下一题
    trainBtns[0].dispatchEvent(new win.MouseEvent('click', { bubbles: true }));
    assert(SC.state.idx === 1, '跳过进入下一题');

    console.log('\n[6] 换题/新一轮清空涂鸦');
    SC.state.doodleData = 'data:image/png;base64,AAA';
    SC.state.idx = 0;
    SC.state.questions = [SC.TYPES.add3.gen(), SC.TYPES.add3.gen()];
    SC.state.questions.forEach(q => { q.user = ''; q.correct = null; });
    await SC.render({});
    // 直接调用 next() → 应清空涂鸦并进入第 2 题
    const before = SC.state.doodleData;
    SC.next();
    assert(before !== null && SC.state.doodleData === null, 'next() 换题清空涂鸦');
    // startPractice 清空
    SC.state.doodleData = 'data:image/png;base64,BBB';
    SC.startPractice();
    assert(SC.state.doodleData === null, '新一轮 startPractice 清空涂鸦');

    console.log('\n===== 速算数字键盘+涂鸦专项: ' + pass + ' 通过, ' + fail + ' 失败 =====');
    process.exit(fail > 0 ? 1 : 0);
  } catch (e) {
    console.error('测试异常:', e && e.stack || e);
    process.exit(1);
  }
}, 1000);
