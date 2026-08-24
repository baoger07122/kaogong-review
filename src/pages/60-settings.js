// ===== 考公笔试复盘系统 - 设置页面 =====
window.App = window.App || {};
App.Pages = App.Pages || {};

App.Pages.Settings = {
  // 折叠与管理状态持久化在实例上：每次重渲染(fold)都能保留
  _state: { expanded: {}, managed: false },
  render(params) {
    const container = document.getElementById('page-settings');
    container.innerHTML = '';

    // 页面标题（对齐画布 7:357：标题26px + 右侧版本号 v8.x.x）
    const header = document.createElement('div');
    header.className = 'page-header';
    header.innerHTML = `
      <div class="page-header__title" style="font-size:26px;font-weight:600;">设置</div>
      <div class="settings-version">v${App.VERSION || ''}</div>
    `;
    container.appendChild(header);

    const content = document.createElement('div');
    content.style.cssText = 'padding:var(--spacing-md) 0;';

    // ===== 醒目备份卡片（顶部，v8.12.7 对齐画布 7:366：深色 Tile 左右布局）=====
    const backupGroup = document.createElement('div');
    backupGroup.className = 'settings-group';
    backupGroup.innerHTML = `
      <div class="backup-hero">
        <div class="backup-hero__info">
          <div class="backup-hero__title">一键备份到 iCloud 云盘</div>
        </div>
        <button class="backup-hero__btn" id="backup-icloud">立即备份</button>
      </div>
      <div class="backup-hero__hint" id="backup-info">读取中…</div>
    `;
    content.insertBefore(backupGroup, content.firstChild);

    // 一键备份：调用 iOS 分享面板，选择「存储到文件 / iCloud 云盘 > 考公备考系统」
    const shareBackupToICloud = async () => {
      try {
        // v8.6.18 不再提示「今日已备份/是否覆盖」，点击直接备份（用户要求）
        await App.DB.shareBackupToICloud();
        App.Components.toast('备份文件已生成，请保存到 iCloud「考公备考系统」文件夹', 'success');
        refreshBackupInfo();
      } catch (e) {
        if (e && e.name === 'AbortError') return;
        console.error(e);
        App.Components.toast('备份失败，请重试', 'error');
      }
    };
    const refreshBackupInfo = async () => {
      try {
        const last = await App.DB.kvGet('last_icloud_backup');
        const info = backupGroup.querySelector('#backup-info');
        if (info) {
          let txt = '备份文件「考公备考系统-backup.json」可保存到 iCloud「考公备考系统」文件夹';
          if (last) {
            const d = new Date(parseInt(last, 10));
            txt += ' · 上次备份：' + d.toLocaleString('zh-CN', { hour12: false });
          } else {
            txt += ' · 暂无 iCloud 备份';
          }
          info.textContent = txt;
        }
      } catch (e) { /* ignore */ }
    };
    const backupBtn = backupGroup.querySelector('#backup-icloud');
    if (backupBtn) backupBtn.addEventListener('click', shareBackupToICloud);
    refreshBackupInfo();




    // ===== 数据组（对齐画布 7:451：组标题「数据」+ 白卡4行） =====
    const dataGroup = document.createElement('div');
    dataGroup.className = 'settings-group';
    dataGroup.innerHTML = `
      <div style="padding:12px var(--spacing-md);font-size:var(--font-xs);color:var(--text-tertiary);font-weight:600;text-transform:uppercase;">数据</div>
    `;

    // iCloud 云备份（对齐画布 7:454：图标底 + 右侧绿色「已启用」）
    const icloudItem = document.createElement('div');
    icloudItem.className = 'ss-row';
    icloudItem.innerHTML = `
      <div class="ss-row__left">
        <span class="ss-ico"><svg viewBox="0 0 24 24" fill="none" stroke="#5A67D8" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M7 18a4 4 0 1 1 .5-7.97A5 5 0 0 1 17 11a3.6 3.6 0 0 1 .5 7.16"/><path d="M12 13v5M9.5 15.5 12 18l2.5-2.5"/></svg></span>
        <span class="ss-row__label">iCloud 云备份</span>
      </div>
      <span class="ss-row__val" style="color:#34C759;">已启用</span>
    `;
    dataGroup.appendChild(icloudItem);

    // 导出数据（对齐画布 7:462：图标底+箭头）
    const exportItem = document.createElement('div');
    exportItem.className = 'ss-row';
    exportItem.innerHTML = `
      <div class="ss-row__left">
        <span class="ss-ico"><svg viewBox="0 0 24 24" fill="none" stroke="#5A67D8" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 15V4M7 9l5-5 5 5"/><path d="M5 20h14"/></svg></span>
        <span class="ss-row__label">导出数据</span>
      </div>
      <span class="ss-row__val"><span class="ss-arrow">›</span></span>
    `;
    exportItem.addEventListener('click', async () => {
      try {
        await App.DB.exportAll();
        App.Components.toast('备份文件已下载 ✓', 'success');
      } catch (e) {
        App.Components.toast('导出失败，请重试', 'error');
      }
    });
    dataGroup.appendChild(exportItem);

    // 导入恢复（对齐画布 7:470：图标底+箭头）
    const importItem = document.createElement('div');
    importItem.className = 'ss-row';
    importItem.innerHTML = `
      <div class="ss-row__left">
        <span class="ss-ico"><svg viewBox="0 0 24 24" fill="none" stroke="#5A67D8" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 4v11M7 11l5 5 5-5"/><path d="M5 20h14"/></svg></span>
        <span class="ss-row__label">导入恢复</span>
      </div>
      <span class="ss-row__val"><span class="ss-arrow">›</span></span>
    `;
    importItem.addEventListener('click', () => {
      const fileInput = document.getElementById('import-file-input');
      fileInput.value = '';
      fileInput.onchange = async (e) => {
        const file = e.target.files[0];
        if (!file) return;

        const confirmed = await App.Components.confirm(
          '导入数据',
          '选择「考公备考系统-backup.json」即可恢复全部数据。导入将覆盖现有全部数据（错题、笔记、套卷、待办）。确定继续？',
          '确认导入', '取消', true
        );
        if (!confirmed) return;

        try {
          const text = await file.text();
          const data = JSON.parse(text);
          await App.DB.importAll(data);
          App.Components.toast('数据已恢复 ✓ 请刷新页面查看', 'success');
          setTimeout(() => location.reload(), 1500);
        } catch (e) {
          App.Components.toast('导入失败，请检查文件格式', 'error');
          console.error(e);
        }
      };
      fileInput.click();
    });
    dataGroup.appendChild(importItem);

    // 清除全部数据（对齐画布 7:478：图标底+红字+箭头，破坏性操作需确认）
    const clearItem = document.createElement('div');
    clearItem.className = 'ss-row';
    clearItem.innerHTML = `
      <div class="ss-row__left">
        <span class="ss-ico ss-ico--red"><svg viewBox="0 0 24 24" fill="none" stroke="#FF3B30" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M6 7h12l-1 13H7L6 7zM9 7V5h6v2M10 11v5M14 11v5"/></svg></span>
        <span class="ss-row__label" style="color:#FF3B30;">清除全部数据</span>
      </div>
      <span class="ss-row__val" style="color:#FF3B30;"><span class="ss-arrow">›</span></span>
    `;
    clearItem.addEventListener('click', async () => {
      const ok = await App.Components.confirm(
        '清除全部数据',
        '将永久清除本机全部错题、笔记、套卷、待办等数据，且不可恢复。建议先「导出备份」。确定继续吗？',
        '清空', '取消', true
      );
      if (!ok) return;
      // 删除 IndexedDB 库 + 清除本地应用 key
      try { indexedDB.deleteDatabase('CivilExamReview'); } catch (e) { /* ignore */ }
      try {
        Object.keys(localStorage).forEach(k => {
          if (k.indexOf('kg_') === 0 || k.indexOf('doodle_') === 0 || k === 'theme') localStorage.removeItem(k);
        });
      } catch (e) { /* ignore */ }
      App.Components.toast('数据已清除，正在刷新…', 'success');
      setTimeout(() => location.reload(), 1200);
    });
    dataGroup.appendChild(clearItem);

    content.appendChild(dataGroup);

    // ===== 笔记组（对齐画布 8:157：组标题「笔记」+ 笔记类型行，图标底+数量+箭头） =====
    const noteGroup = document.createElement('div');
    noteGroup.className = 'settings-group';
    const ntTitle = document.createElement('div');
    ntTitle.style.cssText = 'padding:12px var(--spacing-lg);font-size:var(--font-xs);color:var(--text-tertiary);font-weight:600;text-transform:uppercase;';
    ntTitle.textContent = '笔记';
    noteGroup.appendChild(ntTitle);
    const ntRow = document.createElement('div');
    ntRow.className = 'ss-row';
    ntRow.innerHTML = `
      <div class="ss-row__left">
        <span class="ss-ico"><svg viewBox="0 0 24 24" fill="none" stroke="#0EA5E9" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 12V4h8l8 8-8 8-8-8z"/><path d="M8 8h.01"/></svg></span>
        <span class="ss-row__label">笔记类型</span>
      </div>
      <span class="ss-row__val">按科目 / 模块管理<span class="ss-arrow">›</span></span>
    `;
    ntRow.addEventListener('click', () => App.Router.navigate('note-type-manage'));
    noteGroup.appendChild(ntRow);
    content.appendChild(noteGroup);

    // ===== 版本与更新：按设计稿展示版本信息和手动检查按钮 =====
    const updateGroup = document.createElement('div');
    updateGroup.className = 'settings-update-card';
    updateGroup.innerHTML = `
      <div class="settings-update-card__title">版本与更新</div>
      <div class="settings-update-card__main">
        <div class="settings-update-card__info">
          <div class="settings-update-card__version">v${App.VERSION || ''}</div>
          <div class="settings-update-card__desc">个人管家 v${App.VERSION || ''} - 统一震动反馈并配置<br>Capacitor 云端 iOS 构建流程</div>
        </div>
        <button type="button" class="settings-update-btn" id="settings-check-update">检查更新</button>
      </div>
      <div class="settings-update-card__hint">手动检查后会加载最新版本，数据仍保存在本机。</div>
    `;
    const updateBtn = updateGroup.querySelector('#settings-check-update');
    updateBtn.addEventListener('click', async (event) => {
      event.stopPropagation();
      if (!App.Update || typeof App.Update.checkForUpdate !== 'function') {
        App.Components.toast('更新检查功能暂不可用', 'error');
        return;
      }
      updateBtn.disabled = true;
      updateBtn.textContent = '检查中…';
      try {
        const result = await App.Update.checkForUpdate();
        if (result && result.status === 'latest') {
          App.Components.toast('当前已是最新版本 v' + result.version, 'success');
        } else if (result && result.status === 'checking') {
          App.Components.toast('正在检查更新，请稍候', 'info');
        } else if (!result || result.status === 'error') {
          App.Components.toast('检查更新失败，请稍后重试', 'error');
        }
      } catch (error) {
        App.Components.toast('检查更新失败，请稍后重试', 'error');
      } finally {
        updateBtn.disabled = false;
        updateBtn.textContent = '检查更新';
      }
    });
    content.appendChild(updateGroup);


    // ===== 偏好组（对齐画布 7:485：组标题「偏好」+ 界面字号 + 关于版本，图标底） =====
    const aboutGroup = document.createElement('div');
    aboutGroup.className = 'settings-group';
    aboutGroup.innerHTML = `
      <div style="padding:12px var(--spacing-md);font-size:var(--font-xs);color:var(--text-tertiary);font-weight:600;text-transform:uppercase;">偏好</div>
      <div class="ss-row">
        <div class="ss-row__left">
          <span class="ss-ico"><svg viewBox="0 0 24 24" fill="none" stroke="#8B5CF6" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M5 19l3.2-8.5M12.4 19l-3.2-8.5m0 0L7.9 15h4.8M16 19l2.5-6.5L21 19M17 16.5h3"/></svg></span>
          <span class="ss-row__label">界面字号</span>
        </div>
        <span class="ss-row__val">标准<span class="ss-arrow">›</span></span>
      </div>
      <div class="ss-row">
        <div class="ss-row__left">
          <span class="ss-ico"><svg viewBox="0 0 24 24" fill="none" stroke="#10B981" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18z"/><path d="M12 11v6M12 7.5h.01"/></svg></span>
          <span class="ss-row__label">关于</span>
        </div>
        <span class="ss-row__val">v${App.VERSION}</span>
      </div>
    `;
    content.appendChild(aboutGroup);

    container.appendChild(content);
  }
};
