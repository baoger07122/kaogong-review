// ===== 考公笔试复盘系统 - 便签管理页（查看全部） =====
window.App = window.App || {};
App.Pages = App.Pages || {};

App.Pages.Stickies = {
  async render(params) {
    params = params || {};
    const container = document.getElementById('page-stickies');
    container.innerHTML = '';
    const hasContext = !!(params.subject && params.module);
    const title = hasContext ? params.module + ' · 便签' : '便签';

    const header = App.Components.pageHeader(title, '＋', () => {
      App.Components.stickySheet({
        title: '新增便签',
        onSave: async (data) => {
          try {
            await App.DB.addSticky(Object.assign({}, data, hasContext ? { subject: params.subject, module: params.module } : {}));
          } catch (e) { App.Components.toast('保存失败', 'error'); return; }
          App.Components.toast('已添加 ✓', 'success');
          this.render(params);
        }
      });
    }, hasContext ? {
      onBack: () => App.Router.navigate('library?subject=' + encodeURIComponent(params.subject) + '&module=' + encodeURIComponent(params.module))
    } : undefined);
    container.appendChild(header);

    const content = document.createElement('div');
    content.style.cssText = 'padding:var(--spacing-md) var(--page-padding);padding-bottom:var(--spacing-3xl);';

    const wrap = document.createElement('div');
    wrap.id = 'sticky-manage-wrap';
    content.appendChild(wrap);
    container.appendChild(content);

    await this._fill(wrap, params);
  },

  async _fill(wrap, params) {
    wrap.innerHTML = '';
    let stickies = [];
    try { stickies = await App.DB.getStickies(); } catch (e) {}
    if (params && params.subject && params.module) {
      stickies = stickies.filter(sticky => sticky.subject === params.subject && sticky.module === params.module);
    }

    const masonry = document.createElement('div');
    masonry.className = 'sticky-masonry ' + (params && params.subject && params.module ? 'sticky-masonry--home' : 'sticky-masonry--manage');
    if (stickies.length === 0) {
      const empty = document.createElement('div');
      empty.className = 'sticky-empty';
      empty.textContent = '暂无便签，点击右上角 + 添加第一条';
      masonry.appendChild(empty);
    } else {
      stickies.forEach(s => masonry.appendChild(App.Components.stickyCard(s, { onRefresh: () => this._fill(wrap, params) })));
    }
    wrap.appendChild(masonry);
  }
};
