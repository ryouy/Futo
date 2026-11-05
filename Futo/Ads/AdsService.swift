import AppTrackingTransparency
import GoogleMobileAds
import Observation
import UIKit
import UserMessagingPlatform

/// 広告の設定。**Debugは、必ず Google 公式のテスト広告**（広告ユニット）になる。Releaseは、本番の広告ユニット。
/// 本番の広告ユニットは、コンパイル条件 `FUTO_LIVE_ADS`（Releaseだけ）のときだけ使う。
/// アプリID（Info.plist の `GADApplicationIdentifier`）は、DebugもReleaseも本番のIDにしている：
/// UMP（同意のフォーム）は、アプリIDで、AdMobの「プライバシーとメッセージ」の設定を取るため。Googleのテスト用アプリIDだと、
/// Googleのサンプルの説明メッセージ（"Our app wants to stay free for you"）が出てしまう。
/// 広告ユニットがテストなので、Debugで表示・クリックしても、本番の広告にはならない。
/// アプリIDと、このコンパイル条件が食い違うと、ビルドが失敗する（ビルドフェーズ「Check ad configuration」）。
enum AdsConfig {
    #if FUTO_LIVE_ADS
    /// 本番のバナーのユニットID（公開前は使わない）
    static let bannerUnitID = "ca-app-pub-5121019112887429/4837007551"
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

    /// テスト端末ID。Releaseでも、ここに入れた端末には、テスト広告だけが出る（自分の端末で、本番広告を表示・クリックしないため）。
    /// ビルド設定 `ADMOB_TEST_DEVICE_IDS`（カンマ区切り）で指定する。端末のIDは、広告の要求時にコンソールに出る
    /// （「To get test ads on this device, set: … testDeviceIdentifiers = @[ "…" ]」）。
    static var testDeviceIDs: [String] {
        let raw = Bundle.main.object(forInfoDictionaryKey: "FutoAdTestDeviceIDs") as? String ?? ""
        return raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !$0.hasPrefix("$(") }
    }
}

/// 広告の同意（Google UMP）・追跡の許可（ATT）と、SDKの開始。広告を出すのは、待機の画面のバナー1枠だけ。
///
/// - 同意の「状態の更新」は、起動のたびに、画面を出さずに行う（`updateConsentInfo`）。
/// - 同意のフォームと、追跡の許可のダイアログは、初回説明・チュートリアル・Screen Timeの許可・通知の確認が終わり、
///   ホームが操作できる状態になってから、順番に（UMP → ATT）求める（`startConsentFlowIfNeeded`）。ほかのダイアログとは重ねない。
///   フォームは、必要な地域（EEA・英国など）でだけ出る。結果は、AdMobの「プライバシーとメッセージ」の設定に従う。
/// - 同意が得られる（`canRequestAds`）まで、SDKを開始せず、広告も要求しない。
/// - 広告の要求には、キーワード・URL・個人の気分や回答・利用履歴を一切付けない。パーソナライズしない広告（`npa=1`）にする。
/// - 追跡の許可（ATT）を拒否しても、広告は広告用の識別子なしで出て、基本の機能は、何も変わらない。
/// - 広告が出せなくても、待機・解除は、まったく変わらない。
@MainActor
@Observable
final class AdsService {
    private(set) var canRequestAds = false
    private(set) var privacyOptionsRequired = false
    /// 同意のフォーム・追跡の許可を、求めている最中か（二重に始めない）
    private(set) var isAskingConsent = false
    /// 追跡の許可（ATT）のダイアログの前に、アプリ自身の画面で、やさしく説明しているか
    private(set) var isShowingTrackingExplainer = false
    @ObservationIgnored private var explainerContinuation: CheckedContinuation<Void, Never>?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var updateTask: Task<Void, Never>?
    /// 同意のフォームは、1回の起動で1度だけ試す（オフラインなどで失敗しても、画面のたびに通信し直さない。次の起動でまた試す）
    @ObservationIgnored private var attemptedConsentForm = false

    /// 同意の状態を更新する（画面は出さない）。起動のたびに呼ぶ。失敗しても、前回の結果（canRequestAds）を使う。
    func updateConsentInfo() async {
        if let updateTask { await updateTask.value; return }
        let task = Task { @MainActor in
            let parameters = RequestParameters()
            parameters.isTaggedForUnderAgeOfConsent = false
            #if DEBUG
            // 開発用：同意フォームを、地域を指定して確かめる（シミュレーターは、自動でテスト端末として扱われる）
            if let geography = DebugLaunch.umpGeography {
                let debugSettings = DebugSettings()
                debugSettings.geography = geography == "eea" ? .EEA : .other
                parameters.debugSettings = debugSettings
            }
            #endif
            #if DEBUG
            // 開発用：同意の状態と、失敗の理由を、コンソールに出す（Debugビルドにだけ存在する）
            do { try await ConsentInformation.shared.requestConsentInfoUpdate(with: parameters) } catch { NSLog("[UMP] update failed: %@", String(describing: error)) }
            NSLog("[UMP] %@", "consentStatus=\(ConsentInformation.shared.consentStatus.rawValue) formStatus=\(ConsentInformation.shared.formStatus.rawValue) canRequestAds=\(ConsentInformation.shared.canRequestAds) privacyOptions=\(ConsentInformation.shared.privacyOptionsRequirementStatus.rawValue)")
            #else
            try? await ConsentInformation.shared.requestConsentInfoUpdate(with: parameters)
            #endif
            refreshState()
        }
        updateTask = task
        await task.value
        updateTask = nil
    }

    /// 同意のフォーム（UMP）か、追跡の許可（ATT）の、どちらかを、まだ求める必要があるか。
    /// 同意が不要な地域（日本など。`.notRequired`）や、すでに答えた人（`.obtained`）には、フォームは出ない。
    static func needsConsentPrompt(consentStatus: ConsentStatus, trackingStatus: ATTrackingManager.AuthorizationStatus) -> Bool {
        consentStatus == .required || consentStatus == .unknown || trackingStatus == .notDetermined
    }

    /// 追跡の許可（ATT）のダイアログを、いま出してよいか。まだ聞いていない・アプリが前面、のとき。
    /// （前面でないと、ダイアログは出ない。出なかったときは、また条件がそろったときに、もう一度試す）
    static func shouldRequestTracking(status: ATTrackingManager.AuthorizationStatus, appActive: Bool) -> Bool {
        status == .notDetermined && appActive
    }

    /// 必要な同意を、順番に求める（バックグラウンドで始める）。ホームが操作できる状態になったときに呼ぶ。
    /// 求める必要が無ければ、何も出さずに、すぐ終わる。
    func startConsentFlowIfNeeded() {
        guard !isAskingConsent else { return }
        Task { @MainActor in await requestConsentsInOrder() }
    }

    /// 説明の画面の「つぎへ」。閉じると、OSの許可のダイアログへ進む。
    func dismissTrackingExplainer() {
        isShowingTrackingExplainer = false
        explainerContinuation?.resume()
        explainerContinuation = nil
    }

    #if DEBUG
    /// 開発用：説明の画面だけを出す（見た目の確認用）。Debugビルドにだけ存在する。
    func debugShowTrackingExplainer() { isShowingTrackingExplainer = true }
    #endif

    /// 同意のフォーム（UMP。必要な地域だけ）→ 追跡の許可（ATT。未決定のときだけ）の順に求める。
    /// 許可しなくても、広告は（広告用の識別子なしで）出て、アプリの機能は何も変わらない。
    /// 広告の設定（非パーソナライズ・first-party IDなし）は、許可の結果に関わらず、同じ。
    func requestConsentsInOrder() async {
        #if DEBUG
        NSLog("[AdConsent] start: asking=%@ consentStatus=%ld ATT=%ld", isAskingConsent ? "true" : "false",
              ConsentInformation.shared.consentStatus.rawValue, ATTrackingManager.trackingAuthorizationStatus.rawValue)
        #endif
        guard !isAskingConsent,
              Self.needsConsentPrompt(consentStatus: ConsentInformation.shared.consentStatus,
                                      trackingStatus: ATTrackingManager.trackingAuthorizationStatus) else { return }
        isAskingConsent = true
        defer { isAskingConsent = false }
        let consentStatus = ConsentInformation.shared.consentStatus
        if !attemptedConsentForm, consentStatus == .required || consentStatus == .unknown {
            attemptedConsentForm = true
            await updateConsentInfo()
            // フォームが失敗しても（オフラインなど）、前回の結果を使う。広告が出ないだけ
            #if DEBUG
            do { try await ConsentForm.loadAndPresentIfRequired(from: Self.topViewController()) } catch { NSLog("[UMP] form failed: %@", String(describing: error)) }
            NSLog("[UMP] %@", "after form: consentStatus=\(ConsentInformation.shared.consentStatus.rawValue) canRequestAds=\(ConsentInformation.shared.canRequestAds)")
            #else
            try? await ConsentForm.loadAndPresentIfRequired(from: Self.topViewController())
            #endif
            refreshState()
        }
        if Self.shouldRequestTracking(status: ATTrackingManager.trackingAuthorizationStatus,
                                      appActive: UIApplication.shared.applicationState == .active) {
            // OSのダイアログの前に、アプリの画面で、先に説明する（「つぎへ」だけ。断る選択肢は置かない：次のダイアログで選べる）
            isShowingTrackingExplainer = true
            await withCheckedContinuation { explainerContinuation = $0 }
            // 画面が消えてから、OSのダイアログを出す（切り替えと重ならないように）
            try? await Task.sleep(for: .milliseconds(400))
            if Self.shouldRequestTracking(status: ATTrackingManager.trackingAuthorizationStatus,
                                          appActive: UIApplication.shared.applicationState == .active) {
                _ = await ATTrackingManager.requestTrackingAuthorization()
            }
        }
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
            MobileAds.shared.requestConfiguration.testDeviceIdentifiers = AdsConfig.testDeviceIDs
            // 非パーソナライズ広告を、公式の設定でも明示する。アプリをまたぐパブリッシャーのID（first-party ID）も使わない
            // （ATTは求めない・トラッキングなしの申告に合わせる）。どちらも、広告の要求の前に、SDKの開始前に設定する
            MobileAds.shared.requestConfiguration.publisherPrivacyPersonalizationState = .disabled
            MobileAds.shared.requestConfiguration.setPublisherFirstPartyIDEnabled(false)
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
