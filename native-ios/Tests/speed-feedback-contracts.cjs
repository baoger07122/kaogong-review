// Source contracts complement the executable Swift tests; they do not prove device animations.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const read = name => fs.readFileSync(path.join(__dirname, '../Sources/Features/Speed', name + '.swift'), 'utf8');
const page = read('SpeedPracticeView');
const pad = read('SpeedNumberPad');
const result = read('SpeedResultView');
const feedback = read('SpeedFeedback');
const answer = read('SpeedAnswerRow');
const animatedText = read('SpeedAnimatedText');
const keySound = read('SpeedKeySound');
const exitConfirmation = read('SpeedExitConfirmation');
const dialogs = fs.readFileSync(path.join(__dirname, '../Sources/DesignSystem/NativeDialogs.swift'), 'utf8');
const documentStyle = fs.readFileSync(path.join(__dirname, '../Sources/DesignSystem/NativeDocumentStyle.swift'), 'utf8');
const homeShortcuts = fs.readFileSync(path.join(__dirname, '../Sources/Features/Home/HomeShortcutViews.swift'), 'utf8');
const studyReport = fs.readFileSync(path.join(__dirname, '../Sources/Features/Home/StudyReportView.swift'), 'utf8');
const detail = fs.readFileSync(path.join(__dirname, '../Sources/Features/Library/LibraryRecordDetailView.swift'), 'utf8');
const editor = fs.readFileSync(path.join(__dirname, '../Sources/Features/Library/LibraryRecordEditorView.swift'), 'utf8');
const settingsView = fs.readFileSync(path.join(__dirname, '../Sources/Features/Settings/SettingsView.swift'), 'utf8');
const tests = {
  'manual confirmation regardless of legacy setting': () => {
    assert.doesNotMatch(page, /settings\.confirmAuto|settingBinding\(\\\.confirmAuto\)/);
    const input = page.split('private func pressKey')[1].split('private func resetAttemptState')[0];
    assert.doesNotMatch(input, /submit\(\)|advance\(\)/);
    assert.match(page, /Button\("确认答案", action: submit\)/);
  },
  'manual submission advances synchronously without feedback wait': () => {
    assert.match(page, /!isSubmitting/);
    assert.match(page, /questions\[index\]\.isCorrect == nil/);
    const submit = page.split('private func submit()')[1].split('private func advance()')[0];
    assert.match(submit, /withTransaction\(transaction\) \{ advance\(\) \}/);
    assert.doesNotMatch(submit, /Task|sleep|asyncAfter/);
    assert.doesNotMatch(page, /advanceTask|DispatchQueue\.main\.asyncAfter/);
    assert.match(page.split('private func advance()')[1].split('private func abandon()')[0], /currentInput = ""/);
  },
  'exit confirmation preserves cancel path and practice restart is removed': () => {
    assert.match(page, /alert\("退出练习"/);
    assert.doesNotMatch(page, /alert\("重新开始"|showRestartConfirmation|Button\("重开"\)/);
    assert.match(page, /Button\("继续", role: \.cancel\) \{ \}/);
    assert.match(page, /SpeedExitConfirmation\(onContinue: \{ showExitConfirmation = false \}, onExit: abandon\)/);
    assert.match(page, /withTransaction\(transaction\) \{ showExitConfirmation = true \}/);
    assert.match(exitConfirmation, /NativeConfirmationDialog\(/);
    assert.doesNotMatch(exitConfirmation, /NativeModalContainer|regularMaterial|buttonStyle\(\.plain\)/);
    assert.match(dialogs, /struct NativeConfirmationDialog/);
    const confirmation = dialogs.split('struct NativeConfirmationDialog')[1].split('private struct NativeConfirmationButtonStyle')[0];
    assert.match(confirmation, /systemBackground/);
    assert.match(confirmation, /transaction\.disablesAnimations = true/);
    assert.doesNotMatch(confirmation, /regularMaterial|\.transition\(/);
    const exit = page.split('private func abandon()')[1].split('private func pressKey')[0];
    assert.match(exit, /transaction.disablesAnimations = true/);
    assert.match(exit, /showExitConfirmation = false/);
    assert.match(exit, /screen = \.home/);
    assert.doesNotMatch(exit, /sleep|saveHistory|asyncAfter/);
    const back = page.split('private var backControl')[1].split('private var isEstimateQuestion')[0];
    assert.match(back, /frame\(width: 36, height: 36\)[\s\S]*contentShape\(Circle\(\)\)/);
    assert.match(back, /Button\(action: navigateBack\)/);
    assert.match(back, /allowsHitTesting\(!showDoodle\)/);
    assert.match(back, /accessibilityHidden\(showDoodle\)/);
    assert.doesNotMatch(back, /showDoodle \? 164/);
    assert.match(page, /ToolbarItem\(placement: \.topBarLeading\) \{ backControl \}/);
    assert.doesNotMatch(page, /ToolbarItem\(placement: \.topBarLeading\) \{ backControl \}\s*\.documentToolbarBackground\(\)/);
    assert.doesNotMatch(documentStyle, /NativeToolbarBackButton|NativeStaticToolbarButtonStyle|contentShape\(\.interaction/);
  },
  'estimate uses structured rows and custom settings never affect ordinary practice': () => {
    assert.match(page, /SpeedEstimateExercise\(problem: estimate/);
    assert.match(page, /SpeedEstimateTableView\(rows: estimateRows\)/);
    assert.match(page, /customMode: settings.useCustomPractice == true \? settings.customNumberMode : nil/);
    assert.match(read('SpeedQuestionEngine'), /question\(rows: estimates\)/);
    assert.match(read('SpeedEstimateRules'), /minimumCorrectionRatio = 0\.015/);
    assert.match(read('SpeedEstimateRules'), /guard let source = candidates\.randomElement\(\) else \{ return nil \}/);
    assert.match(read('SpeedEstimateRules'), /Double\(initial\) \* Double\(match.value\) \/ Double\(source\)/);
  },
  'direct touch press and immediate release, medium digits, white surround': () => {
    assert.match(pad, /static let panel = Color.white/);
    assert.match(pad, /fontSize: CGFloat = 24/);
    assert.match(pad, /weight: UIFont.Weight = \.medium/);
    assert.match(pad, /UIView.performWithoutAnimation/);
    assert.match(pad, /override func beginTracking[\s\S]*?setPressed\(true\)/);
    assert.match(pad, /override func endTracking[\s\S]*?if shouldActivate \{ action\(\) \}[\s\S]*?setPressed\(false\)/);
    assert.match(pad, /override func cancelTracking[^\n]*setPressed\(false\)/);
    assert.doesNotMatch(pad, /sendActions\(for:/);
    assert.equal((pad.match(/addTarget\(/g) || []).length, 0);
    assert.match(pad, /override func accessibilityActivate/);
    assert.doesNotMatch(pad, /\.animation\(|withAnimation|UIView.animate|Task.sleep|asyncAfter/);
    assert.match(pad, /label: "删除上一位"[\s\S]*?action: onBackspace/);
    assert.match(pad, /label: "清空答案"[\s\S]*?action: onClear/);
  },
  'key sound uses a prestarted low-latency engine': () => {
    assert.match(keySound, /AVAudioEngine\(\)/);
    assert.match(keySound, /AVAudioPlayerNode/);
    assert.match(keySound, /setPreferredIOBufferDuration\(0\.0029\)/);
    assert.match(keySound, /engine\.prepare\(\)/);
    assert.match(keySound, /engine\.start\(\)/);
    assert.match(keySound, /scheduleBuffer\(tone, at: nil, options: \[\.interrupts\]\)/);
    assert.doesNotMatch(keySound, /AVAudioPlayer\(|currentTime\s*=|prepareToPlay/);
  },
  'all pushed navigation destinations use system back controls': () => {
    assert.doesNotMatch(documentStyle, /NativeToolbarBackButton|NativeDismissToolbarBackModifier/);
    for (const source of [homeShortcuts, studyReport, editor, settingsView]) {
      assert.doesNotMatch(source, /nativeToolbarBackButton\(\)|navigationBarBackButtonHidden\(true\)/);
    }
    assert.match(detail, /navigationBarBackButtonHidden\(showDoodle\)/);
    assert.match(detail, /ToolbarItem\(placement: \.topBarLeading\)[\s\S]*?if showDoodle[\s\S]*?\.disabled\(true\)/);
    assert.doesNotMatch(detail, /NativeToolbarBackButton/);
  },
  'start is a full-width 48pt text button without a capsule': () => {
    const start = page.split('Button(action: start) {')[1].split('.accessibilityIdentifier("speed-start")')[0];
    assert.match(start, /Text\(startButtonTitle\)[\s\S]*frame\(maxWidth: \.infinity\)[\s\S]*frame\(height: 48\)[\s\S]*contentShape\(Rectangle\(\)\)/);
    assert.match(start, /size: 15, weight: \.semibold/);
    assert.doesNotMatch(start, /background|RoundedRectangle|Capsule/);
    assert.match(start, /disabled\(!canStart\)/);
  },
  'web input motion is scoped to answer and commits synchronously': () => {
    assert.doesNotMatch(answer, /SpeedInputPulse|scaleEffect|^\s*\.opacity\(|withAnimation/m);
    assert.match(answer, /transaction \{ \$0.animation = nil; \$0.disablesAnimations = true \}/);
    assert.match(answer, /motion: \.answer\(inputRevision\)/);
    assert.match(answer, /motion: \.expression\(questionID\)/);
    assert.match(answer, /let equals = " ="/);
    assert.match(animatedText, /let duration = answer \? 0.15 : 0.32/);
    for (const component of ['fade', 'movement', 'group']) assert.ok(animatedText.includes(`${component}.duration = duration`));
    assert.match(animatedText, /guard window != nil, bounds.width > 0, bounds.height > 0/);
    assert.match(animatedText, /CATransaction.commit\(\)\s+startPendingMotion\(\)/);
    assert.doesNotMatch(animatedText, /surface.frame =/);
    assert.match(animatedText, /movement.fromValue = answer \? 0.8 : 10/);
    assert.match(animatedText, /fade.fromValue = answer \? 0.4 : 0/);
    assert.match(animatedText, /surface.addSubview\(underline\)/);
    assert.match(animatedText, /removeAnimation\(forKey: "web-text-motion"\)/);
    assert.match(animatedText, /previousMotion != motion/);
    assert.doesNotMatch(animatedText, /Task|asyncAfter|\.task\(/);
  },
  'correct answers never flash the page background': () => {
    assert.doesNotMatch(page + feedback, /SpeedCorrectFlash|SpeedFlashSurface|correctRevision|correct-background/);
    assert.match(page, /settings.nightMode \? Color.black : Color.white/);
    assert.match(feedback, /isUserInteractionEnabled = false/);
  },
  'web toast colors, small symbols and independent lifetime': () => {
    assert.match(feedback, /ofSize: 12, weight: \.medium/);
    assert.match(feedback, /52 \/ 255.0, green: 199 \/ 255.0, blue: 89 \/ 255.0/);
    assert.match(feedback, /dark \? 69 : 59/);
    assert.match(feedback, /dark \? 58 : 48/);
    assert.match(feedback, /opacity.keyTimes = \[0, 0.12, 0.8, 0.92, 1\]/);
    assert.match(page, /milliseconds\(2500\)/);
    assert.match(page, /SpeedFeedbackToast[\s\S]*padding\(\.top, 16\).allowsHitTesting\(false\)/);
  },
  'result retry keeps wrong questions, footer stays fixed': () => {
    assert.match(page, /SpeedPracticeFlow.retryQuestions/);
    assert.match(result, /safeAreaInset\(edge: \.bottom/);
    assert.match(result, /correct \? "✓" : "✗"/);
    assert.match(result, /correct \? green : red/);
    assert.match(page, /NativePencilDrawingEditor/);
    assert.match(page, /NativeDoodleToolbarCapsule/);
    assert.match(page, /accessibilityIdentifier\("speed-doodle-close"\)/);
    assert.match(page, /accessibilityIdentifier\("speed-doodle-open"\)/);
    assert.match(page, /Group \{[\s\S]*?switch screen[\s\S]*?allowsHitTesting\(!showDoodle\)/);
    assert.match(page, /误差 ±3%   合格:/);
    assert.match(result, /frame\(height: 38\)/);
    assert.match(result, /frame\(height: 47\)/);
    assert.match(result, /frame\(height: 49\)/);
  },
  'home alone shows the global tab bar and practice tools are consistent': () => {
    assert.match(page, /RootBottomBarHiddenPreferenceKey\.self, value: screen != \.home/);
    assert.doesNotMatch(page, /eye\.slash|显示或隐藏估算输入|showEstimateInput/);
    assert.match(page, /screen == \.practice \|\| screen == \.result \|\| \(screen == \.history && selectedHistory != nil\)/);
    const practice = page.split('private var practice: some View')[1].split('private var result: some View')[0];
    assert.doesNotMatch(practice, /pencil\.and\.scribble|重开/);
  },
  'web-shaped history grouping and statistics are present': () => {
    const historyModels = read('SpeedHistoryModels');
    assert.match(historyModels, /runs\.last\?\.name == record\.name/);
    assert.match(historyModels, /runs\.reversed\(\)/);
    assert.match(historyModels, /longestFour[\s\S]*totalTime/);
    assert.match(page, /expandedHistoryBlocks/);
    assert.match(page, /showsStandard: false/);
    assert.match(page, /showsFooter: false/);
    assert.match(page, /近 7 天正确率/);
    assert.match(page, /练习类型用时/);
  }
};
for (const [name, test] of Object.entries(tests)) { test(); console.log('PASS ' + name); }
console.log(`${Object.keys(tests).length} speed source contracts passed; device verification still required.`);
