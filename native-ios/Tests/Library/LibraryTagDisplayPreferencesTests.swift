import Foundation
import XCTest
@testable import KaogongReviewNative

@MainActor
final class LibraryTagDisplayPreferencesTests: XCTestCase {
    private let storageKey = "native.library.tag-display-preferences.v1"

    private struct LegacyState: Encodable {
        let settingsByScope: [String: LibraryTagDisplaySettings]
        let quantityTypeIDsByName = ["quantity:geometry": "a", "quantity:ratios": "b"]
    }

    func testQuantityTypesAndUnclassifiedShareOneSavedSetting() throws {
        let suite = "LibraryTagDisplayPreferencesTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = LibraryTagDisplayPreferences(defaults: defaults)
        let geometry = try XCTUnwrap(LibraryTagDisplayScope(subject: "数量关系", module: "几何问题"))
        let ratios = try XCTUnwrap(LibraryTagDisplayScope(subject: "数量关系", module: "和差倍比"))
        let unclassified = try XCTUnwrap(LibraryTagDisplayScope(subject: "数量关系", module: ""))
        let argument = try XCTUnwrap(LibraryTagDisplayScope(subject: "判断推理", module: "逻辑判断"))
        let formal = try XCTUnwrap(LibraryTagDisplayScope(subject: "判断推理", module: "形式逻辑"))
        var custom = LibraryTagDisplaySettings.defaults
        custom.showsMistakeTagCardHeader = true

        try preferences.update(custom, for: geometry)
        XCTAssertEqual(preferences.settings(for: ratios), custom)
        XCTAssertEqual(preferences.settings(for: unclassified), custom)
        XCTAssertEqual(preferences.settings(for: argument), .defaults)
        try preferences.update(custom, for: argument)
        XCTAssertEqual(preferences.settings(for: formal), .defaults)
        XCTAssertEqual(argument.title, "判断推理 · 论证推理")
        XCTAssertEqual(geometry.title, "数量关系")
        XCTAssertEqual(LibraryTagDisplayPreferences(defaults: defaults).settings(for: ratios), custom)
    }

    func testLegacyQuantitySettingsMigrateWhenConsistentAndUseDefaultsForConflicts() throws {
        let suite = "LibraryTagDisplayPreferencesTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let quantity = try XCTUnwrap(LibraryTagDisplayScope(subject: "数量关系", module: ""))
        var custom = LibraryTagDisplaySettings.defaults
        custom.showsKnowledgePointAttribute = false

        let consistent = LegacyState(settingsByScope: ["quantity-type:a": custom, "quantity-type:b": custom])
        defaults.set(try JSONEncoder().encode(consistent), forKey: storageKey)
        XCTAssertEqual(LibraryTagDisplayPreferences(defaults: defaults).settings(for: quantity), custom)

        let conflicting = LegacyState(settingsByScope: ["quantity-type:a": custom, "quantity-type:b": .defaults])
        defaults.set(try JSONEncoder().encode(conflicting), forKey: storageKey)
        let preferences = LibraryTagDisplayPreferences(defaults: defaults)
        XCTAssertEqual(preferences.settings(for: quantity), .defaults)
        try preferences.update(custom, for: quantity)
        XCTAssertEqual(LibraryTagDisplayPreferences(defaults: defaults).settings(for: quantity), custom)
    }
}
