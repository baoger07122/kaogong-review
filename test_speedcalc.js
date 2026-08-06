/* v8.6.14 速算重设计专项测试：13 题型生成器 / 设置持久化 / 首页 / 做题页（强制键盘）/ 自动下一题 / 记录 */
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
    w.confirm = () => true;
  }
});
setTimeout(async () => {
  const win = dom.window, doc = win.document, App = win.App;
  const SC = App.Pages.SpeedCalc;
  if (!SC) { console.error('SpeedCalc 未定义'); process.exit(1); }
  const wait = (ms) => new Promise(r => setTimeout(r, ms));

  try {
    console.log('[1] 版本号');
    assert(App.VERSION === '8.6.19', 'App.VERSION === 8.6.19（当前 ' + App.VERSION + '）');

    console.log('\n[2] 题型生成器（13 种，含 2 个 ▼ 占位）');
    const typeKeys = Object.keys(SC.TYPES);
    assert(typeKeys.length === 13, '13 种题型（' + typeKeys.length + '）');
    assert(!SC.TYPES.custom.gen && !SC.TYPES.dataReal.gen, '自定义练习/资料分析实战为 ▼ 占位（无生成器）');
    const checkQ = (expr) => {
      const e = String(expr).replace(/[×÷≈\s=]/g, (m) => ({ '×': '*', '÷': '/', '≈': '', '=': '', ' ': '' }[m]));
      return Function('"use strict"; return (' + e + ');')();
    };
    let ok = true;
    Object.keys(SC.TYPES).forEach(key => {
      const t = SC.TYPES[key];
      if (!t.gen) return;
      for (let i = 0; i < 30; i++) {
        const q = t.gen();
        if (typeof q.answer !== 'number' || isNaN(q.answer)) { ok = false; break; }
      }
    });
    assert(ok, '11 个可做题型各生成 30 题无异常');

    console.log('\n[3] 设置持久化（kg_speed_settings）');
    win.localStorage.removeItem(SC.SETTINGS_KEY);
    const d = SC.loadSettings();
    assert(d.confirmAuto === true && d.questionCount === 10 && d.mode === 'train', '默认设置：确定ON/10题/训练');
    d.confirmAuto = false;
    SC.saveSettings(d);
    assert(SC.loadSettings().confirmAuto === false, '修改开关后持久化生效');

    console.log('\n[4] 首页渲染（开关/题型/模式/操作区/速记）');
    // 使用 index.html 内置的 #page-speed-calc 容器（render 用 getElementById 定位）
    const home = doc.getElementById('page-speed-calc');
    SC.state.view = 'home';
    SC.state.type = null;
    await SC.render({});
    await wait(50);
    assert(home.querySelectorAll('.sc-switch').length === 6, '设置开关区 6 个 Switch（确定/键盘/顺序/夜间/否/速记）');
    assert(home.querySelectorAll('.sc-type-item').length === 13, '题型网格 13 项');
    assert(home.querySelectorAll('.sc-mode-opt').length === 2, '模式选择 2 项（训练/竞速）');
    assert(!!home.querySelector('.sc-count-picker'), '题量选择按钮存在');
    assert(!!home.querySelector('.sc-fab') && home.querySelector('.sc-fab').textContent === '速记', '右下角速记悬浮按钮存在');
    // 题型选中 → 开始练习
    const item0 = home.querySelector('.sc-type-item:not(.sc-type-item:has(.sc-type-item__drop))');
    item0.click();
    await wait(20);
    assert(SC.state.type !== null, '点击题型后已选中');

    console.log('\n[5] 做题页（状态栏/大题目/评级/强制键盘）');
    SC.startPractice();
    await wait(50);
    const pos = home.querySelector('.sc-statusbar__pos');
    assert(!!pos && /1\/10/.test(pos.textContent), '状态栏显示 1/10');
    assert(!!home.querySelector('.sc-statusbar__pen'), '状态栏有笔图标');
    assert(!!home.querySelector('#sc-timer'), '状态栏有计时器');
    assert(!!home.querySelector('.sc-standard'), '题目下方显示评级标准');
    assert(!!home.querySelector('.sc-practice__expr'), '大题目展示');
    const keys = home.querySelectorAll('.sc-numpad--v2 .sc-numpad__btn');
    assert(keys.length === 15, '屏幕键盘 15 键（重开/清空/退格 + 1-9/.0/确定）');
    assert(!!home.querySelector('.sc-numpad__btn--confirm'), '有「确定」键');
    assert(home.querySelector('.sc-numpad__footer').textContent.includes('第1/10题'), '底部进度 第1/10题');
    assert(!home.querySelector('input[type=text], input[type=number]'), '无系统输入框（强制屏幕键盘）');

    console.log('\n[6] 键盘输入 + 训练模式反馈 + 1.2s 自动下一题');
    const btn1 = Array.from(home.querySelectorAll('.sc-numpad__btn')).find(b => b.textContent === '1');
    const btn2 = Array.from(home.querySelectorAll('.sc-numpad__btn')).find(b => b.textContent === '2');
    const confirmBtn = home.querySelector('.sc-numpad__btn--confirm');
    // 输入正确数字（取答案：若答案匹配 1/2 则换键）
    const q0 = SC.state.questions[0];
    const ansStr = String(q0.answer);
    const inputKey = (digits) => {
      Array.from(String(digits)).forEach(ch => {
        const b = Array.from(home.querySelectorAll('.sc-numpad__btn')).find(x => x.textContent === ch);
        if (b) b.click();
      });
    };
    inputKey(ansStr);
    await wait(30);
    const ansDisp = home.querySelector('.sc-practice__answer');
    assert(ansDisp.textContent === ansStr, '点击数字键拼接答案显示（' + ansStr + '）');
    confirmBtn.click();
    await wait(60);
    const fb = home.querySelector('.sc-fb');
    assert(!!fb, '训练模式提交后显示反馈 ✓/✗');
    await wait(1500);
    assert(/^2\/10$/.test(home.querySelector('.sc-statusbar__pos').textContent), '1.2s 后自动进入下一题（2/10）');

    console.log('\n[7] confirmAuto 自动提交（位数匹配）');
    win.localStorage.setItem(SC.SETTINGS_KEY, JSON.stringify(Object.assign(SC.defaultSettings(), { confirmAuto: true, questionCount: 2, mode: 'train', selectedType: SC.state.type })));
    SC.startPractice();
    await wait(50);
    const q1 = SC.state.questions[0];
    const ans1 = String(q1.answer);
    inputKey(ans1);
    await wait(80);
    assert(SC.state.questions[0].correct === true, 'confirmAuto ON：答案位数匹配自动提交（correct=true）');

    console.log('\n[8] 完成 → 结果页 + kg_speed_records');
    SC.state.idx = SC.state.questions.length - 1;   // 快进到最后一题
    SC.state.questions.forEach(qq => { qq.user = qq.answer; qq.correct = true; });
    SC.next();   // 触发 finish
    await wait(80);
    assert(SC.state.view === 'result', '全部完成后进入结果页');
    const recs = JSON.parse(win.localStorage.getItem(SC.RECORDS_KEY)) || [];
    assert(recs.length >= 1 && recs[0].type && recs[0].count === 2 && typeof recs[0].totalTime === 'number' && Array.isArray(recs[0].details), '历史记录已存 kg_speed_records（type/count/totalTime/details）');

    console.log('\n[9] 历史页渲染');
    SC.state.view = 'history';
    await SC.render({});
    await wait(50);
    assert(home.querySelectorAll('.sc-hist-row').length >= 1, '历史页显示记录行');

    console.log('\n===== 速算专项: ' + pass + ' 通过, ' + fail + ' 失败 =====');
    if (fail > 0) { console.error('✗✗ 存在失败用例'); process.exit(1); }
    else { console.log('✓✓ 全部通过'); process.exit(0); }
  } catch (e) {
    console.error('测试执行异常:', e && e.stack || e);
    process.exit(1);
  }
}, 400);
