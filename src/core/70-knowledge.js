// ===== 学习库统一内容适配层 =====
// 第一阶段只做读取适配，不新增或迁移 IndexedDB 表。
// 旧数据仍分别保存在 errors / notes / words 中，由这里统一成 KnowledgeItem。
window.App = window.App || {};

App.Knowledge = (function () {
  const METHOD_TYPES = ['技巧总结', '解题方法', '方法总结'];

  function plainText(value) {
    if (value == null) return '';
    if (Array.isArray(value)) {
      try { return plainText(App.Utils.toNoteHtml(value)); } catch (e) { return JSON.stringify(value); }
    }
    const raw = String(value);
    if (!/[<&]/.test(raw)) return raw.replace(/\s+/g, ' ').trim();
    const holder = document.createElement('div');
    holder.innerHTML = raw;
    return (holder.textContent || holder.innerText || '').replace(/\s+/g, ' ').trim();
  }

  function normalizeError(error) {
    const compare = Array.isArray(error.compareGroups)
      ? error.compareGroups.map(g => [g && g.words, g && g.relation].filter(Boolean).join('：')).filter(Boolean).join('；')
      : '';
    const summary = [
      error.errorCause ? '错误原因：' + error.errorCause : '',
      compare ? '词语辨析：' + compare : '',
      error.pitfall ? '复盘：' + error.pitfall : ''
    ].filter(Boolean).join(' · ');
    return {
      id: 'wrong:' + error.id,
      sourceId: error.id,
      sourceStore: 'errors',
      subject: error.subject || '',
      module: error.module || '',
      type: 'wrong',
      typeLabel: '错题',
      title: error.question || '未命名错题',
      summary: summary || '暂无复盘摘要',
      content: error.question || '',
      status: error.status || '未掌握',
      createdTime: error.createdAt || error.updatedAt || '',
      updatedTime: error.updatedAt || error.createdAt || '',
      raw: error
    };
  }

  function normalizeNote(note) {
    const isMethod = METHOD_TYPES.indexOf(note.type) !== -1;
    const content = plainText(note.content);
    return {
      id: (isMethod ? 'method:' : 'note:') + note.id,
      sourceId: note.id,
      sourceStore: 'notes',
      subject: note.subject || '',
      module: note.module || '',
      type: isMethod ? 'method' : 'note',
      typeLabel: isMethod ? '方法' : '笔记',
      title: note.title || '未命名笔记',
      summary: content || '暂无内容摘要',
      content,
      status: 'active',
      createdTime: note.createdAt || note.updatedAt || '',
      updatedTime: note.updatedAt || note.createdAt || '',
      raw: note
    };
  }

  function normalizeWord(word) {
    let title = word.name || '';
    if (!title && Array.isArray(word.compareWords)) {
      title = word.compareWords.map(t => t && t.name).filter(Boolean).join(' VS ');
    }
    const isCompare = word.category === 'word-compare' || (word.compareWords && word.compareWords.length > 1);
    return {
      id: 'word:' + word.id,
      sourceId: word.id,
      sourceStore: 'words',
      sourceCategory: word.category || (isCompare ? 'word-compare' : 'word-def'),
      subject: word.subject || '',
      module: word.module || '',
      type: 'word',
      typeLabel: isCompare ? '词语辨析' : '词语',
      title: title || '未命名词语',
      summary: word.compareNote || word.meaning || word.myUnderstanding || '暂无释义',
      content: word.meaning || word.compareNote || '',
      status: 'active',
      createdTime: word.createdAt || word.updatedAt || '',
      updatedTime: word.updatedAt || word.createdAt || '',
      raw: word
    };
  }

  async function getAll() {
    const [errors, notes, words] = await Promise.all([
      App.DB.getErrors(), App.DB.getNotes(), App.DB.getWords()
    ]);
    return [
      ...errors.map(normalizeError),
      ...notes.map(normalizeNote),
      ...words.map(normalizeWord)
    ].filter(item => item.subject);
  }

  function matches(item, query) {
    const q = String(query || '').trim().toLowerCase();
    if (!q) return true;
    return [item.subject, item.module, item.title, item.summary, item.typeLabel]
      .join(' ').toLowerCase().includes(q);
  }

  function filter(items, options) {
    const opts = options || {};
    return (items || []).filter(item => {
      if (opts.subject && item.subject !== opts.subject) return false;
      if (opts.module && item.module !== opts.module) return false;
      if (opts.type === 'note' && item.type !== 'note' && item.type !== 'method') return false;
      if (opts.type && opts.type !== 'all' && opts.type !== 'note' && item.type !== opts.type) return false;
      return matches(item, opts.search);
    });
  }

  function count(items, options) {
    return filter(items, options).length;
  }

  return { getAll, filter, count, plainText, METHOD_TYPES };
})();
