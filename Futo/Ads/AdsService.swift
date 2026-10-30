import GoogleMobileAds
import Observation
import UIKit
import UserMessagingPlatform

/// 広告の設定。**開発中は、すべてのビルド（Debug・Release）で、必ず Google 公式のテスト広告**になる。
/// 本番の広告は、コンパイル条件 `FUTO_LIVE_ADS` を、公開の直前に、意図して有効にしたときだけ使う（いまは無効）。
/// 本番のアプリID（Info.plist）と、このコンパイル条件が食い違うと、ビルドが失敗する（ビルドフェーズ「Check ad configuration」）。
enum AdsConfig {
    #if FUTO_LIVE_ADS
    /// 本番のバナーのユニットID（公開前は使わない）
    static let bannerUnitID = "ca-app-pub-5121019112887429/1750867148"
    /// 本番のアプリID（Info.plist の `ADMOB_APP_ID` も、同時に替える）
    static let appID = "ca-app-pub-5121019112887429~1939615583"
    static let isLive = true
    #else
    /// Google公式のテスト用アダプティブバナーのユニットID（収益は発生しない。自分で押しても安全）
    static let bannerUnitID = "ca-app-pub-3940256099942544/2435281174"
    /// Google公式のテスト用アプリID
    static let appID = "ca-app-pub-3940256099942544~1458002511"
    static let isLive = false
    #endif
}

/// 広告の同意（Google UMP）と、SDKの開始。広告を出すのは、待機の画面のバナー1枠だけ。
///
/// - 同意の確認は、必要な地域（EEA・英国など）でだけフォームが出る。結果は、AdMobの「プライバシーとメッセージ」の設定に従う。
/// - 同意が得られる（`canRequestAds`）まで、SDKを開始せず、広告も要求しない。
/// - 広告の要求には、キーワード・URL・個人の気分や回答・利用履歴を一切付けない。パーソナライズしない広告（`npa=1`）にする。
/// - 広告が出せなくても、待機・解除は、まったく変わらない。
@MainActor
@Observable
final class AdsService {
    private(set) var canRequestAds = false
    private(set) var privacyOptionsRequired = false
    @ObservationIgnored private var started = false
    @ObservationIgnored private var gathering = false

    /// 起動時に1回。同意の状態を確認し、必要なときだけフォームを出す。失敗しても、何も変わらない（広告が出ないだけ）。
    func gatherConsent() async {
        guard !gathering else { return }
        gathering = true
        defer { gathering = false }
        let parameters = RequestParameters()
        parameters.isTaggedForUnderAgeOfConsent = false
        do {
            try await ConsentInformation.shared.requestConsentInfoUpdate(with: parameters)
            try await ConsentForm.loadAndPresentIfRequired(from: Self.topViewController())
        } catch {
            // 同意の確認に失敗しても、前回の結果（canRequestAds）を使う
        }
        refreshState()
    }

    /// 広告のプライバシーの選択（必要な地域だけ）。設定から開く。
    func presentPrivacyOptions() async {
        try? await ConsentForm.presentPrivacyOptionsForm(from: Self.topViewController())
        refreshState()
    }

    private func refreshState() {
        canRequestAds = ConsentInformation.shared.canRequestAds
        privacyOptionsRequired = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
    }

    /// 広告を要求してよいときだけ、SDKを開始する（1回だけ）。
    func startIfAllowed() -> Bool {
        refreshState()
        guard canRequestAds else { return false }
        if !started {
            started = true
            MobileAds.shared.start(completionHandler: nil)
        }
        return true
    }

    /// 画面の幅に対する、アンカー型アダプティブバナーの高さ（同じ幅なら、いつも同じ高さ）。広告の枠を、先に確保するために使う。
    static func bannerSize(width: CGFloat) -> AdSize {
        largePortraitAnchoredAdaptiveBanner(width: width)
    }

    /// 広告の要求。個人の情報は付けず、パーソナライズしない広告にする。
    static func makeRequest() -> Request {
        let request = Request()
        let extras = Extras()
        extras.additionalParameters = ["npa": "1"]
        request.register(extras)
        return request
    }

    static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var controller = scene?.keyWindow?.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        return controller
    }
}
