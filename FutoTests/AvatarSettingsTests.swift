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

    func testDefaultIsThePlainIconInTheThemeColor() {
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

    func testNineSymbolsPlusThePlainOneMakeTen() {
        XCTAssertEqual(AvatarSettings.symbols.count, 9, "9個＋無印で10個")
        XCTAssertEqual(Set(AvatarSettings.symbols.map(\.name)).count, 9)
        let s = AvatarSettings(defaults: defaults())
        s.selectSymbol(2)
        XCTAssertEqual(s.symbolIndex, 2)
        s.selectPlain()
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

    func testCustomColorIsKeptSentAndRestored() {
        let name = "avatar-hex-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        let settings = AvatarSettings(defaults: d)
        settings.customHex = "#A25A72"
        XCTAssertEqual(AvatarSettings(defaults: d).customHex, "#A25A72", "保存される")
        XCTAssertEqual(settings.spec(themeIndex: 0), AvatarSpec(symbol: nil, color: 0, hex: "#A25A72"))
        // 別の端末のアイコンを取り込む
        settings.adopt(AvatarSpec(symbol: 2, color: 1, hex: "#123456"))
        XCTAssertEqual(settings.customHex, "#123456")
        XCTAssertNil(settings.colorIndex)
        settings.adopt(AvatarSpec(symbol: 2, color: 3))
        XCTAssertNil(settings.customHex, "4色のどれかなら、好きな色は外す")
        XCTAssertEqual(settings.colorIndex, 3)
        settings.adopt(AvatarSpec(symbol: nil, color: 0, hex: "not-a-color"))
        XCTAssertNil(settings.customHex, "形式の違う値は、取り込まない")
        settings.customHex = "#ABCDEF"
        settings.reset()
        XCTAssertNil(settings.customHex)
    }

    func testThemeColorIsSentWhenNoColorWasChosen() {
        let name = "avatar-theme-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        let settings = AvatarSettings(defaults: d)
        XCTAssertEqual(settings.spec(themeIndex: 2, themeHex: "#334455"), AvatarSpec(symbol: nil, color: 2, hex: "#334455"), "色を選んでいなければ、アプリの好きな色で見せる")
        settings.colorIndex = 1
        XCTAssertEqual(settings.spec(themeIndex: 2, themeHex: "#334455"), AvatarSpec(symbol: nil, color: 1))
    }
}
