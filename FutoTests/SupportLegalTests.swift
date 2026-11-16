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

    /// 月額・自動更新・サブスクリプションの管理など、旧方式の表示が、画面の文言に残っていない（否定の説明は除く）。
    func testNoLegacySubscriptionWordingInStrings() {
        let banned = ["加入", "月額", "サブスク", "契約", "更新日", "/ 月"]
        for (ja, en) in EnglishStrings.table {
            for word in banned { XCTAssertFalse(ja.contains(word), "旧課金の語が残っている: \(ja)") }
            for word in ["Subscribe", "Subscription", "subscribe", "/ month", "Switch plan"] {
                XCTAssertFalse(en.contains(word), "旧課金の語が残っている: \(en)")
            }
        }
    }

    func testPurchaseScreenWordingInBothLanguages() {
        let saved = LanguageStore.shared.language
        defer { LanguageStore.shared.select(saved) }
        LanguageStore.shared.select(.en)
        XCTAssertEqual(tr("購入済み"), "Purchased")
        XCTAssertEqual(tr("追加の特典はありません（広告は消えません）"), "No extra perks (ads are not removed)")
        XCTAssertEqual(tr("自動更新はありません"), "No automatic renewal")
        LanguageStore.shared.select(.ja)
        XCTAssertEqual(tr("購入済み"), "購入済み")
    }
}
