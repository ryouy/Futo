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

    func testDefaultsUseThePhotoAndTheThemeColor() {
        let s = AvatarSettings(defaults: defaults())
        XCTAssertTrue(s.usesPhoto)
        XCTAssertNil(s.colorIndex)
        XCTAssertTrue(s.showsPhoto(available: true))
        XCTAssertFalse(s.showsPhoto(available: false), "写真が取れていなければ、頭文字")
    }

    func testChoicesPersistAcrossLaunches() {
        let d = defaults()
        let first = AvatarSettings(defaults: d)
        first.usesPhoto = false
        first.colorIndex = 3
        let second = AvatarSettings(defaults: d)
        XCTAssertFalse(second.usesPhoto)
        XCTAssertEqual(second.colorIndex, 3)
        XCTAssertFalse(second.showsPhoto(available: true), "写真を使わない設定なら、写真があっても頭文字")
    }

    func testInvalidStoredColorFallsBackToTheTheme() {
        let d = defaults()
        d.set(99, forKey: "avatar.colorIndex")
        XCTAssertNil(AvatarSettings(defaults: d).colorIndex)
    }

    func testResetRestoresTheDefaults() {
        let s = AvatarSettings(defaults: defaults())
        s.usesPhoto = false; s.colorIndex = 2
        s.reset()
        XCTAssertTrue(s.usesPhoto)
        XCTAssertNil(s.colorIndex)
    }

    func testSymbolsAreTwelveAndSelectingOneStopsUsingThePhoto() {
        XCTAssertEqual(AvatarSettings.symbols.count, 12)
        XCTAssertEqual(Set(AvatarSettings.symbols.map(\.name)).count, 12)
        let s = AvatarSettings(defaults: defaults())
        s.selectSymbol(2)
        XCTAssertEqual(s.symbolIndex, 2)
        XCTAssertFalse(s.showsPhoto(available: true))
        s.selectPhoto()
        XCTAssertNil(s.symbolIndex)
        XCTAssertTrue(s.showsPhoto(available: true))
        s.selectInitial()
        XCTAssertFalse(s.showsPhoto(available: true))
        XCTAssertNil(s.symbolIndex)
        s.selectSymbol(99)
        XCTAssertNil(s.symbolIndex, "範囲外は無視する")
    }

    func testSymbolChoicePersistsAndBadStoredValuesAreIgnored() {
        let d = defaults()
        AvatarSettings(defaults: d).selectSymbol(5)
        XCTAssertEqual(AvatarSettings(defaults: d).symbolIndex, 5)
        d.set(77, forKey: "avatar.symbolIndex")
        XCTAssertNil(AvatarSettings(defaults: d).symbolIndex)
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
