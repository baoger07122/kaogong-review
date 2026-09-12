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
const theme = read('DesignSystem/AppTheme.swift');
const tests = {
  'compact detail typography': () => {
    assert.match(theme, /questionTextFont = Font\.system\(size: 13\.5, weight: \.regular\)/);
    assert.match(theme, /questionLineSpacing: CGFloat = 5/);
    assert.match(detail, /\.font\(AppTheme\.questionTextFont\)/);
    assert.match(detail, /\.lineSpacing\(AppTheme\.questionLineSpacing\)/);
    assert.match(detail, /\.padding\(\.top, 5\)/);
  },
  'empty metadata keeps its label': () => {
    const metadata = detail.split('private var metadata:')[1].split('@ViewBuilder private var imagesBlock')[0];
    assert.doesNotMatch(metadata, /if !.*knowledgePoint|if !.*errorCause|if !.*pitfall/);
    assert.match(metadata, /metadataTagLine\(knowledgePointLabel/);
    assert.match(metadata, /metadataTagLine\(errorCauseLabel/);
    assert.match(metadata, /metadataTextLine\("思维误区"/);
  },
  'inline note owns typing state and flushes before drawing': () => {
    assert.match(detail, /LibraryInlineNoteView/);
    assert.match(detail, /guard noteSession\.finish\(\) else/);
    assert.match(note, /milliseconds\(1_400\)/);
    assert.match(note, /\.onDisappear/);
    assert.doesNotMatch(note, /navigationDestination|\.sheet\(/);
  },
  'canonical empty note stays empty': () => {
    assert.match(note, /if let note = object\["note"\] as\? String \{ return note \}/);
    assert.match(read('Features/Library/LibraryRecordRepository.swift'), /if kind == \.errors, let note = original\["note"\] as\? String \{ content = note \}/);
  },
  'document editor grows and keeps keyboard toolbar': () => {
    assert.match(rich, /if growsWithContent \{\s+view\.isScrollEnabled = false/);
    assert.match(rich, /textView\.inputAccessoryView = container/);
    assert.doesNotMatch(rich, /ToolbarItem\(placement: \.keyboard\)/);
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
    assert.match(pencil, /PKEraserTool\(\.bitmap, width: eraserWidth\)/);
    assert.match(pencil, /fingerDrawingEnabled \? \.anyInput : \.pencilOnly/);
  },
  'smart split is compact and preserves the final question paragraph': () => {
    const dialog = form.split('private var smartSplitDialog')[1].split('private func errorSection')[0];
    assert.match(dialog, /ErrorSmartSplitDialog/);
    assert.match(form, /frame\(height: 148\)/);
    assert.doesNotMatch(form, /粘贴完整题干、A\/B\/C\/D 选项和答案/);
    assert.match(form, /private struct OptionMarker/);
    assert.match(form, /请将 A、B、C、D 分行放在各选项开头/);
    assert.match(form, /private static func cleanedQuestion/);
    assert.match(form, /"\\\(body\)\\n\\\(prompt\)"/);
  },
  'drawing tools persist and clear without confirmation': () => {
    assert.match(pencil, /nativePencil\.eraserWidth/);
    assert.match(pencil, /defaults\.set\(Double\(eraserWidth\)/);
    assert.match(pencil, /Text\("小"\)\.tag\(CGFloat\(14\)\)/);
    assert.match(pencil, /Text\("大"\)\.tag\(CGFloat\(44\)\)/);
    assert.match(pencil, /func requestClear\(\) \{[\s\S]*?action = PencilAction\(kind: \.clear\)/);
    assert.doesNotMatch(pencil, /showClearConfirmation|NativeDeleteDialog/);
    assert.match(detail, /else if legacyPreviewCleared/);
  },
  'drawing blocks the underlying back control without expanding it': () => {
    assert.doesNotMatch(detail, /navigationBarBackButtonHidden|ToolbarItem\(placement: \.topBarLeading\)/);
    assert.match(root, /@State private var libraryPath: \[LibraryRoute\] = \[\]/);
    assert.match(root, /NavigationStack\(path: \$libraryPath\) \{[\s\S]*?LibraryView\(navigationPath: \$libraryPath\)[\s\S]*?environmentObject\(libraryDoodleSession\)/);
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
  'root chrome stays mounted while content uses the empty bar region': () => {
    assert.doesNotMatch(root, /hidesBottomBar|onPreferenceChange/);
    assert.match(root, /window\.safeAreaInsets\.top/);
    assert.match(navigationStyle, /padding\(\.top, windowTop\)/);
    assert.match(navigationStyle, /ignoresSafeArea\(\.container, edges: \.top\)/);
    assert.match(navigationStyle, /safeAreaInset\(edge: \.bottom, spacing: 0\)/);
    assert.match(navigationStyle, /NativeBottomTabBar\(selection: selection\)/);
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
