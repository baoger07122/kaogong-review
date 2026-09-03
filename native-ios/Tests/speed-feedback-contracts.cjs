// Source contracts complement the executable Swift tests; they do not prove device animations.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const read = name => fs.readFileSync(path.join(__dirname, '../Sources/Features/Speed', name + '.swift'), 'utf8');
const page = read('SpeedPracticeView');
const pad = read('SpeedNumberPad');
const result = read('SpeedResultView');
const feedback = read('SpeedFeedback');
const tests = {
  'manual confirmation regardless of legacy setting': () => {
    assert.doesNotMatch(page, /settings\.confirmAuto|settingBinding\(\\\.confirmAuto\)/);
    const input = page.split('private func pressKey')[1].split('private func resetAttemptState')[0];
    assert.doesNotMatch(input, /submit\(\)|advance\(\)/);
  },
  'single cancellable submission, no unguarded delayed advance': () => {
    assert.match(page, /!isSubmitting/);
    assert.match(page, /questions\[index\]\.id == submittedID/);
    assert.match(page, /advanceTask\?\.cancel\(\)/);
    assert.doesNotMatch(page, /DispatchQueue\.main\.asyncAfter/);
  },
  'exit and restart confirmations preserve cancel path': () => {
    assert.match(page, /alert\("退出练习"/);
    assert.match(page, /alert\("重新开始"/);
    assert.match(page, /Button\("继续", role: \.cancel\) \{ \}/);
  },
  'short press, medium digits, white keypad surround': () => {
    assert.match(pad, /static let panel = Color.white/);
    assert.match(pad, /size: 24, weight: \.medium/);
    assert.match(pad, /configuration.isPressed \? nil : \.easeOut\(duration: 0.07\)/);
    assert.doesNotMatch(pad, /spring|timingCurve/);
  },
  'first input and question entrance use restartable tasks': () => {
    assert.match(feedback, /task\(id: trigger\)/);
    assert.match(feedback, /task\(id: questionID\)/);
    assert.match(feedback, /Task.isCancelled/);
    assert.match(page, /SpeedCorrectFlash/);
    assert.match(page, /SpeedQuestionEntrance/);
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
