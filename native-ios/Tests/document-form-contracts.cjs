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
const root = read('App/RootTabView.swift');
const doodle = read('Features/Library/LibraryDoodleSession.swift');
const navigationStyle = read('DesignSystem/NativeDocumentStyle.swift');
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
    assert.match(pencil, /fingerDrawingEnabled \? \.anyInput : \.pencilOnly/);
  },
  'drawing blocks the underlying back control without expanding it': () => {
    assert.doesNotMatch(detail, /navigationBarBackButtonHidden|ToolbarItem\(placement: \.topBarLeading\)/);
    assert.match(root, /NavigationStack \{ LibraryView\(\) \}[\s\S]*?environmentObject\(libraryDoodleSession\)/);
    assert.match(root, /\.overlay \{[\s\S]*?LibraryDoodleOverlay\(session: libraryDoodleSession\)/);
    assert.match(doodle, /above the complete NavigationStack/);
    assert.match(doodle, /Color\.black\.opacity\(0\.18\)/);
    assert.match(doodle, /NativePencilDrawingEditor/);
    const open = detail.split('private func openDoodle()')[1].split('private func saveDrawing')[0];
    assert.match(open, /doodleSession\.present/);
    assert.match(doodle, /transaction\.disablesAnimations = true/);
    assert.match(doodle, /NativeDoodleToolbarCapsule/);
    assert.match(doodle, /accessibilityIdentifier\("library-doodle-close"\)/);
    assert.match(read('DesignSystem/NativeDocumentStyle.swift'), /background\(\.regularMaterial, in: Capsule\(\)\)/);
  },
  'root chrome stays mounted across navigation transitions': () => {
    assert.match(root, /NativeBottomTabBar\(selection: \$selection\)[\s\S]*?opacity\(hidesBottomBar \? 0 : 1\)/);
    assert.doesNotMatch(root, /if !hidesBottomBar/);
    assert.doesNotMatch(root, /safeAreaInset\(edge: \.bottom/);
    assert.match(navigationStyle, /func stableRootNavigationBar\(\)/);
    assert.match(navigationStyle, /toolbar\(\.visible, for: \.navigationBar\)/);
    for (const source of [
      read('Features/Home/HomeView.swift'),
      read('Features/Library/LibraryView.swift'),
      read('Features/Settings/SettingsView.swift')
    ]) {
      assert.match(source, /stableRootNavigationBar\(\)/);
      assert.doesNotMatch(source, /toolbar\(\.hidden, for: \.navigationBar\)/);
    }
    assert.doesNotMatch(detail, /if !doodleSession\.isPresented/);
    assert.match(doodle, /LibraryDoodleCanvasState/);
  }
};
for (const [name, test] of Object.entries(tests)) { test(); console.log(`PASS ${name}`); }
console.log(`${Object.keys(tests).length} source contracts passed; device verification still required.`);
