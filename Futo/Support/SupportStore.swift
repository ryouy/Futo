import Observation
import StoreKit

/// 「ふとを応援」の月額プラン（App Store の自動更新サブスクリプション）。
/// 2つのプランは、同じサブスクリプショングループに置くので、同時には加入できず、プラン間の変更もできる。
/// どちらも、加入すると、待機画面のバナー広告が出なくなる（基本の機能は、加入しなくても、すべて無料）。
/// 決済・請求・解約は、すべて Apple が扱う。ふとは、購入者の情報を受け取らない。
enum SupportPlan: String, CaseIterable, Identifiable {
    /// 広告なし（App Store 経由は月額150円。Web 経由は100円）
    case adFree = "com.ryouy.futo.noads.monthly"
    /// ふとを応援（月額500円。広告非表示も含む）
    case support = "com.ryouy.futo.support.monthly"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .adFree: return tr("広告なし")
        case .support: return tr("ふとを応援")
        }
    }

    /// 1行ずつ（句の切れ目で改行する）
    var lines: [String] {
        switch self {
        case .adFree: return [tr("待機の時間を、より静かに")]
        case .support: return [tr("ふとの開発と運営を支える"), tr("広告非表示も含む")]
        }
    }

    /// App Store から価格を取れないときに出す、予定の価格（円）
    var fallbackPrice: Int {
        switch self {
        case .adFree: return 150
        case .support: return 500
        }
    }
}

@MainActor
@Observable
final class SupportStore {
    private(set) var products: [SupportPlan: Product] = [:]
    /// いま加入しているプラン（なければ nil）
    private(set) var current: SupportPlan?
    /// 加入状況を、一度確認し終えたか（確認前は、広告を出さない）
    private(set) var entitlementsLoaded = false
    private(set) var isLoadingProducts = false
    private(set) var isWorking = false
    var message: String?
    @ObservationIgnored private var updates: Task<Void, Never>?

    var adsRemoved: Bool { current != nil }

    /// アプリの起動時に1回。購入の更新（別の端末・更新・解約など）も、受け取り続ける。
    func start() {
        guard updates == nil else { return }
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.handle(result)
            }
        }
        Task {
            await refreshEntitlements()
            await loadProducts()
        }
    }

    func loadProducts() async {
        guard !isLoadingProducts else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let loaded = try await Product.products(for: SupportPlan.allCases.map(\.rawValue))
            var map: [SupportPlan: Product] = [:]
            for product in loaded { if let plan = SupportPlan(rawValue: product.id) { map[plan] = product } }
            products = map
        } catch {
            // 取れなくても、アプリの動作は変わらない（画面に、読み込めなかったと出す）
        }
    }

    /// いまの加入状況を確認する（端末に控えた情報でも確認できる）。
    func refreshEntitlements() async {
        var active: SupportPlan?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result, transaction.revocationDate == nil,
                  let plan = SupportPlan(rawValue: transaction.productID) else { continue }
            // 念のため両方あれば、上のプラン（ふとを応援）を優先する
            if active == nil || plan == .support { active = plan }
        }
        current = active
        entitlementsLoaded = true
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else { return }
        await transaction.finish()
        await refreshEntitlements()
    }

    /// 加入する、または、もう一方のプランへ変更する（同じグループなので、Apple が切り替える）。
    func purchase(_ plan: SupportPlan) async {
        guard let product = products[plan], !isWorking else { return }
        isWorking = true
        message = nil
        defer { isWorking = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    await refreshEntitlements()
                } else {
                    message = tr("購入を確認できませんでした")
                }
            case .pending:
                message = tr("承認を待っています")
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            message = tr("購入できませんでした　もう一度お試しください")
        }
    }

    /// 購入の復元（別の端末や、入れ直したあとに、加入状況を取り戻す）。
    func restore() async {
        guard !isWorking else { return }
        isWorking = true
        message = nil
        defer { isWorking = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            message = current == nil ? tr("復元できる購入は、見つかりませんでした") : tr("購入を復元しました")
        } catch {
            message = tr("復元できませんでした　もう一度お試しください")
        }
    }
}
