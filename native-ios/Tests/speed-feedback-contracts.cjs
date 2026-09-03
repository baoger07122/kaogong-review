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
  'exit and restart confirmations preserve cancel path': () => {
    assert.match(page, /alert\("退出练习"/);
    assert.match(page, /alert\("重新开始"/);
    assert.match(page, /Button\("继续", role: \.cancel\) \{ \}/);
  },
  'direct touch press and immediate release, medium digits, white surround': () => {
    assert.match(pad, /static let panel = Color.white/);
    assert.match(pad, /fontSize: CGFloat = 24/);
    assert.match(pad, /weight: UIFont.Weight = \.medium/);
    assert.match(pad, /UIView.performWithoutAnimation/);
    assert.match(pad, /override func beginTracking[\s\S]*?setPressed\(true\)/);
    assert.match(pad, /override func endTracking[\s\S]*?setPressed\(false\)/);
    assert.match(pad, /override func cancelTracking[^\n]*setPressed\(false\)/);
    assert.doesNotMatch(pad, /sendActions\(for:/);
    assert.equal((pad.match(/addTarget\(/g) || []).length, 1);
    assert.match(pad, /override func accessibilityActivate/);
    assert.doesNotMatch(pad, /\.animation\(|withAnimation|UIView.animate|Task.sleep|asyncAfter/);
    assert.match(pad, /label: "删除上一位"[\s\S]*?action: onBackspace/);
    assert.match(pad, /label: "清空答案"[\s\S]*?action: onClear/);
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
    assert.match(animatedText, /group.duration = answer \? 0.15 : 0.32/);
    assert.match(animatedText, /movement.fromValue = answer \? 0.8 : 10/);
    assert.match(animatedText, /fade.fromValue = answer \? 0.4 : 0/);
    assert.match(animatedText, /surface.addSubview\(underline\)/);
    assert.match(animatedText, /removeAnimation\(forKey: "web-text-motion"\)/);
    assert.match(animatedText, /previousMotion != motion/);
    assert.doesNotMatch(animatedText, /Task|asyncAfter|\.task\(/);
  },
  'correct flash stays below practice content, never tints the keypad': () => {
    assert.match(page, /\.background \{[\s\S]*if screen == \.practice \{[\s\S]*SpeedCorrectFlash/);
    assert.doesNotMatch(page, /\.overlay \{ SpeedCorrectFlash/);
    assert.match(feedback, /fade.fromValue = 0.18/);
    assert.match(feedback, /fade.duration = 0.28/);
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
  }
};
for (const [name, test] of Object.entries(tests)) { test(); console.log('PASS ' + name); }
console.log(`${Object.keys(tests).length} speed source contracts passed; device verification still required.`);
