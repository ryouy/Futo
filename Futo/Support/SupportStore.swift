import Observation
import StoreKit

/// アプリ内課金の2つの商品。どちらも、一度きりの購入（自動更新はしない）。基本の機能は、購入しなくても、すべて無料。
/// 決済・請求・返金は、すべて Apple が扱う。ふとは、購入者の情報を受け取らない。
enum SupportProduct: String, CaseIterable, Identifiable {
    /// 広告なし（非消耗型）。一度の購入で、待機の画面の広告が、ずっと出なくなる。購入の復元ができる。
    case adFree = "com.ryouy.futo.adfree.lifetime"
    /// ふとを応援（消耗型）。一回ごとの任意の応援。何回でも購入できる。広告の非表示などの特典は、付けない。
    case tip = "com.ryouy.futo.support.tip"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .adFree: return tr("広告なし")
        case .tip: return tr("ふとを応援")
        }
    }

    /// 1行ずつ（句の切れ目で改行する）
    var lines: [String] {
        switch self {
        case .adFree: return [tr("待機の画面の広告が、ずっと表示されなくなります")]
        case .tip: return [tr("ふとの開発と運営を支える、一回かぎりの応援です")]
        }
    }

    /// 購入の種類の説明（何が起きて、何が起きないか）
    var terms: [String] {
        switch self {
        case .adFree: return [tr("一度の購入で、ずっと有効（買い切り）"), tr("自動更新はありません"), tr("購入の復元ができます")]
        case .tip: return [tr("一回ごとの任意の応援です"), tr("自動更新はありません"), tr("追加の特典はありません（広告は消えません）")]
        }
    }
}

@MainActor
@Observable
final class SupportStore {
    private(set) var products: [SupportProduct: Product] = [:]
    /// 「広告なし」を、検証済みの購入として持っているか（返金・取り消しがあれば、false に戻る）
    private(set) var adFreePurchased = false
    /// 購入の状況を、一度確認し終えたか（確認前は、広告を出さない）
    private(set) var entitlementsLoaded = false
    private(set) var isLoadingProducts = false
    /// 商品の取得を試して、取れなかったか（取れないときは、購入を進めない）
    private(set) var productsLoadFailed = false
    private(set) var isWorking = false
    var message: String?
    /// 「ふとを応援」の購入が済んだとき、お礼を出すための印（画面を離れたら消す）
    private(set) var thanksForTip = false
    @ObservationIgnored private var updates: Task<Void, Never>?
    @ObservationIgnored private let defaults: UserDefaults

    /// 広告を出さないか。App Store の「広告なし」（非消耗型）の購入権利があるときだけ。
    /// 「ふとを応援」の購入や、ログイン・アカウントの状態では、広告は消えない。
    var adsRemoved: Bool { adFreePurchased }

    /// 処理ずみの「ふとを応援」の取引ID（同じ取引を、2度処理しないため）
    private static let processedTipsKey = "support.processedTipTransactions"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// アプリの起動時に1回。購入の更新（別の端末・返金・取り消し・未完了の取引など）も、受け取り続ける。
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
            let loaded = try await Product.products(for: SupportProduct.allCases.map(\.rawValue))
            var map: [SupportProduct: Product] = [:]
            for product in loaded { if let item = SupportProduct(rawValue: product.id) { map[item] = product } }
            products = map
            productsLoadFailed = map.count != SupportProduct.allCases.count
        } catch {
            productsLoadFailed = true
        }
    }

    /// いまの購入の状況を確認する（端末に控えた情報でも確認できる）。検証済みで、取り消されていない「広告なし」だけを数える。
    func refreshEntitlements() async {
        var owned = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result, transaction.revocationDate == nil,
                  transaction.productID == SupportProduct.adFree.rawValue else { continue }
            owned = true
        }
        adFreePurchased = owned
        entitlementsLoaded = true
    }

    /// 届いた取引を処理する。検証できないものは、何も付与しない。
    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else { return }
        switch SupportProduct(rawValue: transaction.productID) {
        case .tip:
            await completeTip(transaction)
        case .adFree:
            await transaction.finish()
            await refreshEntitlements()
        case nil:
            // 知らない商品（以前の月額プランなど）は、何も付与せず、完了だけする
            await transaction.finish()
        }
    }

    /// 「ふとを応援」の取引を、1回だけ処理して、完了にする。お礼は、新しい取引のときだけ出す。
    private func completeTip(_ transaction: Transaction) async {
        let id = String(transaction.id)
        var processed = Set(defaults.stringArray(forKey: Self.processedTipsKey) ?? [])
        let isNew = !processed.contains(id)
        if isNew {
            processed.insert(id)
            // 保存が大きくなりすぎないように、新しい側を残す（取引IDは、増える数字）
            let kept = processed.compactMap { UInt64($0) }.sorted().suffix(500).map(String.init)
            defaults.set(kept, forKey: Self.processedTipsKey)
            thanksForTip = true
        }
        await transaction.finish()
    }

    func clearThanks() { thanksForTip = false }

    /// 購入する。「広告なし」を持っているときは、もう一度は買えない。成功・保留・キャンセル・失敗を、それぞれ扱う。
    func purchase(_ item: SupportProduct) async {
        guard let product = products[item], !isWorking else { return }
        if item == .adFree, adFreePurchased { return }
        isWorking = true
        message = nil
        thanksForTip = false
        defer { isWorking = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    switch item {
                    case .tip:
                        await completeTip(transaction)
                    case .adFree:
                        await transaction.finish()
                        await refreshEntitlements()
                    }
                } else {
                    // 検証できない取引は、何も付与しない
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
            message = tr("購入できませんでした\nもう一度お試しください")
        }
    }

    /// 購入の復元（別の端末や、入れ直したあとに、「広告なし」を取り戻す）。「ふとを応援」は、復元の対象ではない。
    func restore() async {
        guard !isWorking else { return }
        isWorking = true
        message = nil
        defer { isWorking = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            message = adFreePurchased ? tr("購入を復元しました") : tr("復元できる購入は、見つかりませんでした")
        } catch {
            message = tr("復元できませんでした\nもう一度お試しください")
        }
    }
}
