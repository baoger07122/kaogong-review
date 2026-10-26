#!/usr/bin/env bash
set -euo pipefail

BASELINE_DIR="$RUNNER_TEMP/native-tabbar-baseline"
RESULT_PATH="$RUNNER_TEMP/native-tabbar-baseline.xcresult"
DERIVED_DATA_PATH="$RUNNER_TEMP/native-tabbar-baseline-derived-data"

git worktree add --detach "$BASELINE_DIR" "$BASELINE_COMMIT"
trap 'git worktree remove --force "$BASELINE_DIR" >/dev/null 2>&1 || true' EXIT
cp native-ios/Tests/UI/SpeedInteractionUITests.swift \
  "$BASELINE_DIR/native-ios/Tests/UI/SpeedInteractionUITests.swift"
(cd "$BASELINE_DIR/native-ios" && xcodegen generate)
xcrun simctl boot "$SIMULATOR_ID" || true
xcrun simctl bootstatus "$SIMULATOR_ID" -b

if ! xcodebuild test \
  -project "$BASELINE_DIR/native-ios/KaogongReviewNative.xcodeproj" \
  -scheme KaogongReviewNative \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -parallel-testing-enabled NO \
  -resultBundlePath "$RESULT_PATH" \
  -only-testing:SpeedInteractionUITests/SpeedInteractionUITests/testRootTabBarFrameBaselineDiagnostics \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Automatic; then
  xcrun xcresulttool get test-results summary --path "$RESULT_PATH" || true
  exit 1
fi
