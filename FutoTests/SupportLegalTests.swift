import XCTest
@testable import Futo

/// 購入画面の利用規約（EULA）と、Screen Time の許可前の文言。
@MainActor
final class SupportLegalTests: XCTestCase {
    func testTermsOfUseIsAppleStandardEULA() {
        XCTAssertEqual(SupportView.termsOfUseURL.absoluteString,
                       "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")
    }

    func testLegalAndPermissionWordingInBothLanguages() {
        let saved = LanguageStore.shared.language
        defer { LanguageStore.shared.select(saved) }
        LanguageStore.shared.select(.ja)
        XCTAssertEqual(tr("利用規約"), "利用規約")
        XCTAssertEqual(tr("次へ"), "次へ")
        LanguageStore.shared.select(.en)
        XCTAssertEqual(tr("利用規約"), "Terms of Use")
        XCTAssertEqual(tr("次へ"), "Next")
        XCTAssertEqual(tr("プライバシーポリシー"), "Privacy Policy")
    }
}
