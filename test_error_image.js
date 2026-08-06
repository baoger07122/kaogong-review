/* 错题表单多图 + 删除解析笔记 专项测试 */
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
    console.log('[1] 无图：显示插入按钮，无占位，可多选');
    const page = doc.getElementById('page-error-form');
    await App.Pages.Errors.renderForm.call(App.Pages.Errors, {});
    await new Promise(r => setTimeout(r, 400));
    const imgLabel = Array.from(page.querySelectorAll('.form-label')).find(l => l.textContent.includes('图片'));
    assert(!!imgLabel, '「图片」标签存在');
    const addBtn = Array.from(page.querySelectorAll('button')).find(b => b.textContent.includes('插入图片'));
    assert(!!addBtn, '无图时显示「🖼️ 插入图片」按钮');
    assert(!page.querySelector('.error-form-image__grid'), '无图时不显示图片网格');
    const fileInput = page.querySelector('input[type=file][accept="image/*"]');
    assert(!!fileInput, '隐藏 file input 存在');
    assert(fileInput.multiple === true, '支持多选 (multiple)');

    console.log('\n[2] 插入多张图片：网格展示 + 逐张删除');
    // 依次插入 3 张
    const fi = page.querySelector('input[type=file][accept="image/*"]');
    for (let i = 0; i < 3; i++) {
      try {
        Object.defineProperty(fi, 'files', { value: [{ name: 'img' + i + '.png', type: 'image/png', size: 1024 }], configurable: true });
        fi.dispatchEvent(new win.Event('change', { bubbles: true }));
        await new Promise(r => setTimeout(r, 80));
      } catch (e) { console.log('  ⚠ 插入模拟失败:', e.message); }
    }
    const grid = page.querySelector('.error-form-image__grid');
    assert(!!grid, '图片网格出现');
    const items = grid.querySelectorAll('.error-form-image__item');
    assert(items.length === 3, '3 张图片都在网格中');
    assert(!!page.querySelector('.error-form-image__del'), '每张有删除按钮');
    assert(!!Array.from(page.querySelectorAll('button')).find(b => b.textContent.includes('继续添加图片')), '显示「继续添加图片」按钮');
    // 删除第 2 张
    const delBtns = grid.querySelectorAll('.error-form-image__del');
    delBtns[1].dispatchEvent(new win.MouseEvent('click', { bubbles: true }));
    await new Promise(r => setTimeout(r, 50));
    const items2 = page.querySelector('.error-form-image__grid').querySelectorAll('.error-form-image__item');
    assert(items2.length === 2, '删除后剩 2 张');

    console.log('\n[3] 提交保存 images 数组');
    // 填必填项并提交
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
    const kpInput = page.querySelector('.tag-input__field-row .form-input');
    if (kpInput) {
      kpInput.value = '语境分析';
      kpInput.dispatchEvent(new win.KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }));
      await new Promise(r => setTimeout(r, 80));
    }
    const ecInputs = page.querySelectorAll('.tag-input__field-row .form-input');
    const ecInput = ecInputs[ecInputs.length - 1];
    if (ecInput) {
      ecInput.value = '词义理解偏差';
      ecInput.dispatchEvent(new win.KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }));
      await new Promise(r => setTimeout(r, 80));
    }
    const qInput = Array.from(page.querySelectorAll('textarea')).find(t => t.placeholder.includes('题干'));
    if (qInput) { qInput.value = '多图测试题'; qInput.dispatchEvent(new win.Event('input', { bubbles: true })); }
    const optInputs = page.querySelectorAll('.error-form-option-input');
    if (optInputs[0]) { optInputs[0].value = 'A选项'; optInputs[0].dispatchEvent(new win.Event('input', { bubbles: true })); }
    setSel(2, 'A');
    await new Promise(r => setTimeout(r, 300));
    let lastToast = '';
    App.Components.toast = (m) => { lastToast = m; };
    const submitEl = Array.from(page.querySelectorAll('.page-header__right, div')).find(b => b.textContent.trim() === '提交' && b.className.includes('page-header__right'));
    if (submitEl) {
      submitEl.dispatchEvent(new win.MouseEvent('click', { bubbles: true }));
      await new Promise(r => setTimeout(r, 500));
    }
    const saved = dbStore['errors::err1'];
    if (saved) {
      assert(Array.isArray(saved.images) && saved.images.length === 2, '保存 images 数组含 2 张');
      assert(saved.images.every(s => s.startsWith('data:image/png')), '均为 Base64 dataURL');
      assert(saved.analysisNote === undefined, '不再保存 analysisNote 字段');
      assert(saved.question === '多图测试题', '题目正确保存');
      console.log('  images[0] 前缀:', saved.images[0].slice(0, 30));
    } else {
      console.log('  ✗ 错题未保存成功, toast:', lastToast);
      fail++;
    }

    console.log('\n[4] 表单无「解析分析笔记」模块');
    await App.Pages.Errors.renderForm.call(App.Pages.Errors, {});
    await new Promise(r => setTimeout(r, 400));
    const noteLabel = Array.from(page.querySelectorAll('.form-label')).find(l => l.textContent.includes('解析分析笔记'));
    assert(!noteLabel, '表单无「解析分析笔记」标签');
    assert(!!Array.from(page.querySelectorAll('.form-label')).find(l => l.textContent.includes('错题笔记')), '「错题笔记」仍在');

    console.log('\n[5] 详情页：多图展示 + 无解析笔记');
    await App.Pages.Errors.renderDetail.call(App.Pages.Errors, {
      id: 'd1'
    });
    // mock DB.get 返回多图数据
    const origGet = App.DB.get;
    App.DB.get = async (t, id) => {
      if (t === 'errors' && id === 'd1') {
        return { id: 'd1', subject: '言语理解', module: '逻辑填空', knowledgePoints: ['考点'], errorCause: '错因',
          question: '详情题', images: ['data:image/png;base64,A', 'data:image/png;base64,B'], status: '未掌握',
          analysisNote: '旧解析内容' };
      }
      return origGet(t, id);
    };
    await App.Pages.Errors.renderDetail.call(App.Pages.Errors, { id: 'd1' });
    await new Promise(r => setTimeout(r, 100));
    const dPage = doc.getElementById('page-error-detail');
    const imgs = dPage.querySelectorAll('.error-detail-images .error-detail-image');
    assert(imgs.length === 2, '详情页展示 2 张图片');
    assert(!dPage.textContent.includes('解析分析笔记'), '详情页无解析分析笔记');
    assert(!dPage.textContent.includes('旧解析内容'), '旧 analysisNote 内容不再展示');

    console.log('\n[6] 画廊卡片：多图 + 宽度自适应');
    const card = App.Components.galleryErrorCard({
      knowledgePoints: ['考点'], errorCause: '错因', question: '题',
      images: ['data:image/png;base64,A', 'data:image/png;base64,B', 'data:image/png;base64,C', 'data:image/png;base64,D'],
      status: '未掌握', createdAt: new Date().toISOString()
    }, () => {});
    const cardImgs = card.querySelectorAll('.error-gallery-card__img');
    assert(cardImgs.length === 3, '卡片最多显示 3 张');
    assert(!!card.querySelector('.error-gallery-card__imgmore'), '多余图片显示 +N');
    assert(card.querySelector('.error-gallery-card__imgmore').textContent === '+1', '+N 数量正确');
    assert(!!card.querySelector('.error-gallery-card__tagrow'), '考点+错因标签行存在');
    assert(Array.from(card.querySelectorAll('.error-gallery-card__tagrow .tag')).some(t => t.textContent === '错因'), '错因标签仍在');
    // 单图旧数据兼容
    const card2 = App.Components.galleryErrorCard({
      knowledgePoints: [], errorCause: '', question: '题',
      image: 'data:image/png;base64,OLD', status: '未掌握'
    }, () => {});
    assert(card2.querySelectorAll('.error-gallery-card__img').length === 1, '旧 image 单图兼容');

    console.log('\n[7] v8.6.3 错题笔记对齐去块：HTML 直通 + 迁移 + htmlEditor');
    // 历史 Markdown 笔记 → 打开自动迁移为 HTML 并存回
    const errWithNote = { id: 'n1', subject: '资料分析', module: '增长率', knowledgePoints: ['公式'], errorCause: '看错', question: 'Q', note: '# 复盘\n\n**重点**内容' };
    dbStore['errors::n1'] = errWithNote;
    await App.Pages.Errors.renderDetail.call(App.Pages.Errors, { id: 'n1' });
    await new Promise(r => setTimeout(r, 100));
    assert(typeof dbStore['errors::n1'].note === 'string' && dbStore['errors::n1'].note.indexOf('<') === 0, '历史 MD 笔记打开时迁移为完整 HTML 并存回');
    assert(dbStore['errors::n1'].note.includes('<h1') && dbStore['errors::n1'].note.includes('<strong>'), '迁移 HTML 含 h1/strong（格式保真）');
    const dPage7 = doc.getElementById('page-error-detail');
    const enoteView7 = dPage7.querySelector('.card .note-html-body');
    assert(!!enoteView7 && enoteView7.innerHTML.includes('<h1'), '查看态 HTML 直通渲染（note-html-body + h1）');
    // 点击笔记 → 编辑器为 htmlEditor（非旧块编辑器）
    const enoteCard7 = enoteView7.closest('.card');
    enoteCard7.click();
    await new Promise(r => setTimeout(r, 100));
    assert(!!dPage7.querySelector('.card .html-editor'), '错题笔记编辑用 htmlEditor（单连续富文本）');
    assert(!dPage7.querySelector('.card .notion-block'), '编辑区无块结构（彻底去块）');
    const enoteArea7 = dPage7.querySelector('.card .html-editor__area');
    assert(!!enoteArea7 && enoteArea7.innerHTML.includes('<h1'), '编辑器直存 HTML（h1 保留）');

    console.log('\n===== 错题多图+删解析笔记专项: ' + pass + ' 通过, ' + fail + ' 失败 =====');
    process.exit(fail > 0 ? 1 : 0);
  } catch (e) {
    console.error('测试异常:', e && e.stack || e);
    process.exit(1);
  }
}, 1000);
