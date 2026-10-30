import SwiftUI
import XCTest
@testable import Futo

@MainActor
final class AvatarSettingsTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "avatar-tests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    func testDefaultsAreTheInitialInTheThemeColor() {
        let s = AvatarSettings(defaults: defaults())
        XCTAssertNil(s.symbolIndex)
        XCTAssertNil(s.colorIndex)
        XCTAssertEqual(s.fill(choices: [.red, .green, .blue, .orange], themeColor: .purple), .purple)
    }

    func testColorIsChosenFromTheFourThemeColors() {
        let s = AvatarSettings(defaults: defaults())
        XCTAssertEqual(AvatarSettings.colorCount, 4)
        s.colorIndex = 2
        XCTAssertEqual(s.fill(choices: [.red, .green, .blue, .orange], themeColor: .purple), .blue)
    }

    func testSymbolsAreTwelveAndSelectionWorks() {
        XCTAssertEqual(AvatarSettings.symbols.count, 12)
        XCTAssertEqual(Set(AvatarSettings.symbols.map(\.name)).count, 12)
        let s = AvatarSettings(defaults: defaults())
        s.selectSymbol(2)
        XCTAssertEqual(s.symbolIndex, 2)
        s.selectInitial()
        XCTAssertNil(s.symbolIndex)
        s.selectSymbol(99)
        XCTAssertNil(s.symbolIndex, "範囲外は無視する")
    }

    func testChoicesPersistAndBadStoredValuesAreIgnored() {
        let d = defaults()
        let first = AvatarSettings(defaults: d)
        first.selectSymbol(5); first.colorIndex = 3
        let second = AvatarSettings(defaults: d)
        XCTAssertEqual(second.symbolIndex, 5)
        XCTAssertEqual(second.colorIndex, 3)
        d.set(77, forKey: "avatar.symbolIndex"); d.set(9, forKey: "avatar.colorIndex")
        let third = AvatarSettings(defaults: d)
        XCTAssertNil(third.symbolIndex)
        XCTAssertNil(third.colorIndex, "4色の範囲外は無視する")
    }

    func testResetRestoresTheDefaults() {
        let s = AvatarSettings(defaults: defaults())
        s.selectSymbol(1); s.colorIndex = 1
        s.reset()
        XCTAssertNil(s.symbolIndex)
        XCTAssertNil(s.colorIndex)
    }

    func testProfileCacheKeepsTheLastNamePerAccount() {
        let d = defaults()
        XCTAssertNil(ProfileCache.name(uid: "A", defaults: d))
        ProfileCache.save(name: "山田", uid: "A", defaults: d)
        XCTAssertEqual(ProfileCache.name(uid: "A", defaults: d), "山田")
        XCTAssertNil(ProfileCache.name(uid: "B", defaults: d), "別のアカウントには見えない")
        ProfileCache.clear(uid: "A", defaults: d)
        XCTAssertNil(ProfileCache.name(uid: "A", defaults: d))
    }
}
