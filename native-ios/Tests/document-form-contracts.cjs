// Source regression checks only. These do not replace Xcode or device interaction tests.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const read = p => fs.readFileSync(path.join(__dirname, '../Sources', p), 'utf8');
const detail = read('Features/Library/LibraryRecordDetailView.swift');
const form = read('Features/Library/LibraryRecordEditorView.swift');
const note = read('Features/Library/LibraryInlineNoteView.swift');
const rich = read('Features/Shared/NativeRichTextEditor.swift');
const picker = read('Features/Library/LibrarySelectionDialogs.swift');
const pencil = read('Features/Shared/NativePencilDrawingEditor.swift');
const tests = {
  'compact detail typography': () => {
    assert.match(detail, /size: 13\.5, weight: \.regular/);
    assert.match(detail, /\.lineSpacing\(5\)/);
    assert.match(detail, /\.padding\(\.top, 5\)/);
  },
  'empty metadata keeps its label': () => {
    const metadata = detail.split('private func metadataLine')[1].split('private func supportingLine')[0];
    assert.doesNotMatch(metadata, /if !text\.isEmpty/);
    for (const label of ['考点', '错因', '思维误区']) assert.ok(detail.includes(`metadataLine("${label}"`));
  },
  'inline note owns typing state and flushes before drawing': () => {
    assert.match(detail, /LibraryInlineNoteView/);
    assert.match(detail, /guard noteSession\.finish\(\) else/);
    assert.match(note, /milliseconds\(700\)/);
    assert.match(note, /\.onDisappear/);
    assert.doesNotMatch(note, /navigationDestination|\.sheet\(/);
  },
  'canonical empty note stays empty': () => {
    assert.match(note, /if let note = object\["note"\] as\? String \{ return note \}/);
    assert.match(read('Features/Library/LibraryRecordRepository.swift'), /if kind == \.errors, let note = original\["note"\] as\? String \{ content = note \}/);
  },
  'document editor grows and keeps keyboard toolbar': () => {
    assert.match(rich, /if growsWithContent \{\s+view\.isScrollEnabled = false/);
    assert.match(rich, /ToolbarItem\(placement: \.keyboard\)/);
    assert.match(rich, /focusOnAppear/);
  },
  'thinking trap is text, never auto-added to tag library': () => {
    assert.match(form, /title\.hasPrefix\("思维误区"\)/);
    const save = form.split('private func save()')[1].split('private func remove()')[0];
    assert.doesNotMatch(save, /kind: \.thinkingTrap/);
    assert.match(picker, /kind == \.knowledgePoint \? 3 : 1/);
  },
  'centered tag and relation selectors, cancellable selections': () => {
    assert.match(picker, /NativeEditorDialog/g);
    assert.match(picker, /@State private var selected/);
    assert.match(form, /NativeDocumentProperty/);
    assert.match(form, /LibraryRelationSelectionDialog/);
  },
  'no toolbar background and bitmap eraser preserved': () => {
    assert.match(read('DesignSystem/NativeDocumentStyle.swift'), /sharedBackgroundVisibility\(\.hidden\)/);
    assert.match(pencil, /PKEraserTool\(\.bitmap, width: pencilBitmapEraserWidth\)/);
  },
  'drawing keeps title stable and blocks the underlying back control': () => {
    assert.match(detail, /navigationBarBackButtonHidden\(true\)/);
    assert.match(detail, /allowsHitTesting\(!showDoodle\)/);
    assert.match(detail, /accessibilityHidden\(showDoodle\)/);
    assert.match(detail, /frame\(width: showDoodle \? 164 : nil, alignment: \.leading\)/);
    assert.match(detail, /frame\(width: showDoodle \? 164 : nil, alignment: \.trailing\)/);
    const open = detail.split('private func openDoodle()')[1].split('private func closeDoodle()')[0];
    const close = detail.split('private func closeDoodle()')[1].split('private func saveDrawing()')[0];
    assert.match(open, /transaction\.disablesAnimations = true/);
    assert.match(close, /transaction\.disablesAnimations = true/);
    assert.match(detail, /HStack\(spacing: 3\)/);
  }
};
for (const [name, test] of Object.entries(tests)) { test(); console.log(`PASS ${name}`); }
console.log(`${Object.keys(tests).length} source contracts passed; device verification still required.`);
