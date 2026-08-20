// ===== 考公笔试复盘系统 - 考点 / 错因管理页面 =====
window.App = window.App || {};
App.Pages = App.Pages || {};

App.Pages.KpManage = {
  render(params) {
    const container = document.getElementById('page-kpmanage');
    container.innerHTML = '';

    // 头部说明（v8.12.26 对齐画布 21:573：标题 20px SemiBold + 说明 12px 灰，无返回）
    const header = document.createElement('div');
    header.style.cssText = 'padding:var(--spacing-lg) var(--page-padding);padding-bottom:var(--spacing-sm);';
    header.innerHTML = `
      <div style="font-size:20px;font-weight:600;color:var(--text-primary);margin-bottom:6px;line-height:1.3;">考点 / 错因管理</div>
      <div style="font-size:12px;color:var(--text-tertiary);line-height:1.5;">
        考点按「科目 → 模块」分级管理；错因<i><b>按模块独立管理</b></i>，在模块内增删的错因仅属于该模块、与其它模块互不互通。
      </div>
    `;
    container.appendChild(header);

    // 折叠卡片式管理组件（考点 + 错因，编辑模式支持拖拽排序 / 删除 / 添加）
    const mgrWrap = document.createElement('div');
    mgrWrap.className = 'tag-manager-wrap';
    mgrWrap.style.cssText = 'padding:0 var(--page-padding) var(--spacing-xl);';
    container.appendChild(mgrWrap);
    App.Components.tagManager(mgrWrap, {
      title: '标签管理',
      kinds: ['kp', 'ec'],
      onDone: () => {}
    });
  }
};
