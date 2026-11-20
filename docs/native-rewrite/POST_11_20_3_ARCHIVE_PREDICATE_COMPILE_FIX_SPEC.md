# Native 11.20.3 archive predicate compile correction

## Page and entry point

Library record detail (`LibraryRecordDetailView`) and its SwiftData query for the detail record set.

## Existing behavior

The 11.20.3 release commit expanded the query to include `keyvalue`, but the multiline `#Predicate<StoredRecord>` closure omitted its explicit `record` parameter. The iOS archive then failed during Swift macro expansion, and the compiler interpreted `record` as a view member. The query must continue to include `words`, `errors`, `exams`, and `keyvalue`.

## Target behavior and implementation

Declare the predicate parameter explicitly as `record in`, retaining the four existing collection comparisons and their OR ordering. Do not change the query scope, routing, persistence, or detail behavior.

Implementation location: `native-ios/Sources/Features/Library/LibraryRecordDetailView.swift`, the `@Query(filter:)` declaration on `LibraryRecordDetailView`.

## Boundaries and failure handling

This is a compile correction only. No record fields are migrated or rewritten, and no UI strings or layout change. The build must fail normally if the macro still cannot expand; do not bypass archive errors.

## Reproducible acceptance

1. Confirm the predicate explicitly binds `record` and still lists all four collections.
2. Run the fixed native domain behavior checks in the release workflow.
3. Produce the iOS device archive and confirm the `Archive native App` step succeeds; this is necessary validation that the compiler accepts the SwiftData macro.
4. Confirm IPA packaging, upload, and direct Release asset download availability. No simulator run is required for this predicate-only fix.
