const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const source = fs.readFileSync(
  path.join(__dirname, "..", "Sources", "Features", "Shared", "NativeRichTextEditor.swift"),
  "utf8",
);

assert.match(
  source,
  /keyboardAccessory:\s*AnyView\(keyboardToolbar\)/,
  "The shared rich-text editor must pass its toolbar to the active text view.",
);
assert.match(
  source,
  /textView\.inputAccessoryView\s*=\s*container/,
  "The toolbar must be attached directly to UITextView.inputAccessoryView.",
);
assert.doesNotMatch(
  source,
  /ToolbarItem\(placement:\s*\.keyboard\)/,
  "Do not rely on a navigation-level SwiftUI keyboard toolbar for UIKit text input.",
);
assert.match(source, /accessibilityLabel\("笔记格式栏"\)/);
assert.match(source, /label:\s*"收起键盘"/);
assert.match(source, /private enum RichTextToolbarPage:[\s\S]*case main, format/);
assert.match(source, /keyboardAccessoryHeight:\s*keyboardAccessoryHeight/);
assert.match(source, /private var keyboardAccessoryHeight:[\s\S]*?\n\s*58\n/);
assert.match(source, /private var insertMenu:/);
assert.match(source, /private var paragraphMenu:/);
assert.doesNotMatch(source, /toolbarPage == \.insert|toolbarPage == \.paragraph/);
assert.match(source, /private struct RichTextSelectionState/);
assert.doesNotMatch(
  source,
  /backgroundColor\s*=\s*\.secondarySystemBackground/,
  "The accessory host must stay transparent so the centered floating card is not replaced by a full-width gray strip.",
);

console.log("PASS rich-text toolbar is a focus-owned, fixed-height floating keyboard accessory");
