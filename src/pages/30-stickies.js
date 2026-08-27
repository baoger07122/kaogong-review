// ===== 考公笔试复盘系统 - 便签管理页（查看全部） =====
window.App = window.App || {};
App.Pages = App.Pages || {};

App.Pages.Stickies = {
  async render(params) {
    const container = document.getElementById('page-stickies');
    container.innerHTML = '';

    const header = App.Components.pageHeader('便签', '＋', () => {
      App.Components.stickySheet({
        title: '新增便签',
        onSave: async (data) => {
          try { await App.DB.addSticky(data); } catch (e) { App.Components.toast('保存失败', 'error'); return; }
          App.Components.toast('已添加 ✓', 'success');
          this.render({});
        }
      });
    });
    container.appendChild(header);

    const content = document.createElement('div');
    content.style.cssText = 'padding:var(--spacing-md) var(--page-padding);padding-bottom:var(--spacing-3xl);';

    const wrap = document.createElement('div');
    wrap.id = 'sticky-manage-wrap';
    content.appendChild(wrap);
    container.appendChild(content);

    await this._fill(wrap);
  },

  async _fill(wrap) {
    wrap.innerHTML = '';
    let stickies = [];
    // 此页面是首页便签的管理入口，不混入各模块的独立便签。
    try { stickies = await App.DB.getStickies({ scope: 'home' }); } catch (e) {}

    const masonry = document.createElement('div');
    masonry.className = 'sticky-masonry sticky-masonry--manage';
    if (stickies.length === 0) {
      const empty = document.createElement('div');
      empty.className = 'sticky-empty';
      empty.textContent = '暂无便签，点击右上角 + 添加第一条';
      masonry.appendChild(empty);
    } else {
      stickies.forEach(s => masonry.appendChild(App.Components.stickyCard(s, { onRefresh: () => this._fill(wrap) })));
    }
    wrap.appendChild(masonry);
  }
};

