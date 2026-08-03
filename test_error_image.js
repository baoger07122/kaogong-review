/* 错题表单图片模块专项测试 */
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
    w.prompt = () => null;
    w.confirm = () => true;
    w.FileReader = class {
      readAsDataURL(file) {
        const self = this;
        setTimeout(() => {
          try { self.result = 'data:image/png;base64,' + btoa(String(file.name || 'img')); }
          catch (e) { self.result = 'data:image/png;base64,AAAA'; }
          self.onload && self.onload();
        }, 10);
      }
      readAsText() {}
    };
  }
});

setTimeout(async () => {
  const win = dom.window, doc = win.document, App = win.App;

  const kvStore = {};
  const dbStore = {};
  if (App.DB) {
    App.DB.kvSet = async (k, v) => { kvStore[k] = JSON.parse(JSON.stringify(v)); };
    App.DB.kvGet = async (k) => kvStore[k];
    App.DB.get = async (table, id) => dbStore[table + '::' + id] || null;
    App.DB.getErrors = async () => Object.values(dbStore).filter(x => x && x.question);
    App.DB.getNotes = async () => [];
    App.DB.addError = async (data) => { data.id = 'err1'; dbStore['errors::err1'] = data; return data.id; };
    App.DB.updateError = async (data) => { dbStore['errors::' + data.id] = data; };
  }
  App.Components.confirm = async () => true;
  App.Components.toast = () => {};

  try {
    console.log('[1] 无图：表单显示插入按钮，无占位');
    const page = doc.getElementById('page-error-form');
    await App.Pages.Errors.renderForm.call(App.Pages.Errors, {});
    await new Promise(r => setTimeout(r, 400));
    const imgLabel = Array.from(page.querySelectorAll('.form-label')).find(l => l.textContent.includes('图片'));
    assert(!!imgLabel, '「图片」标签存在');
    const addBtn = Array.from(page.querySelectorAll('button')).find(b => b.textContent.includes('插入图片'));
    assert(!!addBtn, '无图时显示「🖼️ 插入图片」按钮');
    assert(!page.querySelector('.error-form-image__img'), '无图时不显示图片');
    assert(!page.querySelector('.error-form-image__btns'), '无图时不显示更换/删除按钮');
    const fileInput = page.querySelector('input[type=file][accept="image/*"]');
    assert(!!fileInput, '隐藏 file input 存在 (accept=image/*)');

    console.log('\n[2] 有图：展示图片 + 更换/删除');
    // 通过模拟点击插入图片（FileReader mock）
    const btn = Array.from(page.querySelectorAll('button')).find(b => b.textContent.includes('插入图片'));
    btn.dispatchEvent(new win.MouseEvent('click', { bubbles: true }));
    // file input change 事件模拟
    const fi = page.querySelector('input[type=file][accept="image/*"]');
    // 直接触发 change：jsdom 无法设置 files，改用 FileReader 直测——验证组件逻辑：模拟文件选择
    // 通过 Object.defineProperty 设置 files
    try {
      Object.defineProperty(fi, 'files', { value: [{ name: 'photo.png', type: 'image/png', size: 1024 }], configurable: true });
      fi.dispatchEvent(new win.Event('change', { bubbles: true }));
      await new Promise(r => setTimeout(r, 100));
      const imgEl = page.querySelector('.error-form-image__img');
      assert(!!imgEl, '插入后展示图片');
      assert(imgEl.src.startsWith('data:image/png'), '图片为 Base64 dataURL');
      assert(!!page.querySelector('.error-form-image__btns'), '显示更换/删除按钮');
    } catch (e) {
      console.log('  ✗ file input 模拟失败:', e.message);
      fail++;
    }

    console.log('\n[3] 删除图片回到无图态');
    if (page.querySelector('.error-form-image__btns')) {
      const delBtn = Array.from(page.querySelectorAll('.error-form-image__btns button')).find(b => b.textContent.includes('删除'));
      delBtn.dispatchEvent(new win.MouseEvent('click', { bubbles: true }));
      await new Promise(r => setTimeout(r, 50));
      assert(!page.querySelector('.error-form-image__img'), '删除后图片消失');
      assert(!!Array.from(page.querySelectorAll('button')).find(b => b.textContent.includes('插入图片')), '删除后回到插入按钮');
    }

    console.log('\n[4] 提交保存 image 字段');
    // 重置表单（重新渲染干净状态）
    await App.Pages.Errors.renderForm.call(App.Pages.Errors, {});
    await new Promise(r => setTimeout(r, 400));
    // 重新插入图片
    const btn2 = Array.from(page.querySelectorAll('button')).find(b => b.textContent.includes('插入图片'));
    btn2.dispatchEvent(new win.MouseEvent('click', { bubbles: true }));
    const fi2 = page.querySelector('input[type=file][accept="image/*"]');
    if (fi2) {
      try {
        Object.defineProperty(fi2, 'files', { value: [{ name: 'photo2.png', type: 'image/png', size: 1024 }], configurable: true });
        fi2.dispatchEvent(new win.Event('change', { bubbles: true }));
        await new Promise(r => setTimeout(r, 150));
      } catch (e) { console.log('  ⚠ 图片插入模拟失败:', e.message); }
    }
    assert(!!page.querySelector('.error-form-image__img'), '重新插入后展示图片');
    // 填必填项（每次操作后重新查询 select，等待 buildForm 完成）
    const setSel = (idx, val) => {
      const s = page.querySelectorAll('.form-select')[idx];
      if (!s) return false;
      const setter = Object.getOwnPropertyDescriptor(win.HTMLSelectElement.prototype, 'value').set;
      setter.call(s, val);
      s.dispatchEvent(new win.Event('change', { bubbles: true }));
      return true;
    };
    setSel(0, '言语理解');
    await new Promise(r => setTimeout(r, 500));
    setSel(1, '逻辑填空');
    await new Promise(r => setTimeout(r, 500));
    // 考点输入（tagInput 输入行）
    const kpInput = page.querySelector('.tag-input__field-row .form-input');
    if (kpInput) {
      kpInput.value = '语境分析';
      kpInput.dispatchEvent(new win.KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }));
      await new Promise(r => setTimeout(r, 80));
    }
    // 错因输入（最后一个 tag-input 输入行）
    const ecInputs = page.querySelectorAll('.tag-input__field-row .form-input');
    const ecInput = ecInputs[ecInputs.length - 1];
    if (ecInput) {
      ecInput.value = '词义理解偏差';
      ecInput.dispatchEvent(new win.KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }));
      await new Promise(r => setTimeout(r, 80));
    }
    // 题目
    const qInput = Array.from(page.querySelectorAll('textarea')).find(t => t.placeholder.includes('题干'));
    if (qInput) { qInput.value = '这是一道测试题'; qInput.dispatchEvent(new win.Event('input', { bubbles: true })); }
    // 选项 A
    const optInputs = page.querySelectorAll('.error-form-option-input');
    if (optInputs[0]) { optInputs[0].value = '选项A内容'; optInputs[0].dispatchEvent(new win.Event('input', { bubbles: true })); }
    // 正确选项 select（第三个 select，值 A）
    setSel(2, 'A');
    await new Promise(r => setTimeout(r, 300));
    // 提交（页头右侧是 div 不是 button）
    let lastToast = '';
    App.Components.toast = (m) => { lastToast = m; };
    const submitEl = Array.from(page.querySelectorAll('.page-header__right, .page-header__title, div')).find(b => b.textContent.trim() === '提交' && b.className.includes('page-header__right'));
    if (submitEl) {
      submitEl.dispatchEvent(new win.MouseEvent('click', { bubbles: true }));
      await new Promise(r => setTimeout(r, 500));
      console.log('  提交后 toast:', lastToast || '(无)');
    } else {
      console.log('  ✗ 提交按钮未找到');
    }
    const saved = dbStore['errors::err1'];
    if (saved) {
      assert(saved.image && saved.image.startsWith('data:image/png'), '保存的错题含 image 字段(Base64)');
      assert(saved.question === '这是一道测试题', '保存的题目正确');
      console.log('  saved.image 前缀:', saved.image.slice(0, 30));
    } else {
      console.log('  ✗ 错题未保存成功');
      fail++;
    }

    console.log('\n===== 错题图片模块专项: ' + pass + ' 通过, ' + fail + ' 失败 =====');
    process.exit(fail > 0 ? 1 : 0);
  } catch (e) {
    console.error('测试异常:', e && e.stack || e);
    process.exit(1);
  }
}, 1000);
