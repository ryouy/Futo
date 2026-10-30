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
}
