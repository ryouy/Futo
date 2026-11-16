import StoreKit
import StoreKitTest
import XCTest
@testable import Futo

/// StoreKit Testing（Futo.storekit）での購入の確認。実機・Sandbox・本番のApp Storeでの確認の代わりにはならない。
@MainActor
final class StoreKitPurchaseTests: XCTestCase {
    private var session: SKTestSession!
    private var suites: [String] = []

    override func setUp() async throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Futo.storekit")
        session = try SKTestSession(contentsOf: file)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        session.askToBuyEnabled = false
        LanguageStore.shared.select(.ja)
    }

    override func tearDown() async throws {
        session.resetToDefaultState()
        session.clearTransactions()
        for name in suites { UserDefaults().removePersistentDomain(forName: name) }
        session = nil
    }

    /// 起動のたびに新しいストア（= アプリの再起動）。処理ずみの取引IDは、スイートごとに分ける。
    private func makeStore(suite: String = UUID().uuidString) -> SupportStore {
        suites.append(suite)
        return SupportStore(defaults: UserDefaults(suiteName: suite)!)
    }

    private func loadedStore() async -> SupportStore {
        let store = makeStore()
        await store.refreshEntitlements()
        await store.loadProducts()
        return store
    }

    private func adFreeTransactionIDs() async -> [UInt64] {
        var ids: [UInt64] = []
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, t.productID == SupportProduct.adFree.rawValue { ids.append(t.id) }
        }
        return ids
    }

    private func unfinishedCount() async -> Int {
        var n = 0
        for await _ in Transaction.unfinished { n += 1 }
        return n
    }

    // MARK: 商品・価格

    func testBothProductsLoadWithStoreKitPrices() async throws {
        let store = await loadedStore()
        XCTAssertEqual(Set(store.products.keys), Set(SupportProduct.allCases))
        XCTAssertFalse(store.productsLoadFailed)
        XCTAssertEqual(store.products[.adFree]?.type, .nonConsumable)
        XCTAssertEqual(store.products[.tip]?.type, .consumable)
        // 価格は、StoreKit が返す表示用の価格（ローカルのテスト用設定 Futo.storekit では、どちらも 500。本番の価格は App Store Connect で決まる）。アプリの中の固定値ではない
        XCTAssertTrue(try XCTUnwrap(store.products[.adFree]).displayPrice.contains("500"))
        XCTAssertTrue(try XCTUnwrap(store.products[.tip]).displayPrice.contains("500"))
    }

    func testProductLoadFailureDoesNotAllowPurchase() async throws {
        try await session.setSimulatedError(.generic(.networkError(URLError(.notConnectedToInternet))), forAPI: .loadProducts)
        let store = makeStore()
        await store.loadProducts()
        XCTAssertTrue(store.productsLoadFailed)
        XCTAssertTrue(store.products.isEmpty, "取れなかったときは、価格も商品も持たない")
        await store.purchase(.adFree)
        await store.purchase(.tip)
        await store.refreshEntitlements()
        XCTAssertFalse(store.adsRemoved)
        XCTAssertNil(store.message)
        XCTAssertFalse(store.thanksForTip)
        // 通信が戻れば、読み込み直せる
        try await session.setSimulatedError(nil, forAPI: .loadProducts)
        await store.loadProducts()
        XCTAssertFalse(store.productsLoadFailed)
        XCTAssertEqual(store.products.count, 2)
    }

    // MARK: 広告なし（非消耗型）

    func testAdFreePurchaseHidesAdsAndPersistsAcrossRestart() async throws {
        let store = await loadedStore()
        XCTAssertFalse(store.adsRemoved)
        XCTAssertTrue(store.entitlementsLoaded)
        await store.purchase(.adFree)
        XCTAssertTrue(store.adFreePurchased)
        XCTAssertTrue(store.adsRemoved)
        let transactions = await adFreeTransactionIDs()
        XCTAssertEqual(transactions.count, 1)

        // 購入ずみでは、もう一度は買えない（取引が増えない）
        await store.purchase(.adFree)
        let after = await adFreeTransactionIDs()
        XCTAssertEqual(after.count, 1)

        // アプリの再起動：新しいストアが、購入の権利から判定する
        let restarted = makeStore()
        XCTAssertFalse(restarted.adsRemoved, "確認の前は、まだ付与しない")
        await restarted.refreshEntitlements()
        XCTAssertTrue(restarted.adsRemoved)
    }

    func testRestorePurchases() async throws {
        let store = await loadedStore()
        await store.purchase(.adFree)
        // 入れ直し・別の端末：新しいストアで、復元する
        let reinstalled = makeStore()
        await reinstalled.restore()
        XCTAssertTrue(reinstalled.adFreePurchased)
        XCTAssertEqual(reinstalled.message, tr("購入を復元しました"))
    }

    func testRestoreWithNothingToRestoreGrantsNothing() async throws {
        let store = makeStore()
        await store.restore()
        XCTAssertFalse(store.adsRemoved)
        XCTAssertEqual(store.message, tr("復元できる購入は、見つかりませんでした"))
    }

    func testRefundRemovesAdFree() async throws {
        let store = await loadedStore()
        await store.purchase(.adFree)
        XCTAssertTrue(store.adsRemoved)
        let ids = await adFreeTransactionIDs()
        let id = try XCTUnwrap(ids.first)
        try session.refundTransaction(identifier: UInt(id))
        // 返金が反映されるまで、少し待つ（再確認を繰り返す）
        for _ in 0..<50 {
            await store.refreshEntitlements()
            if !store.adFreePurchased { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertFalse(store.adFreePurchased, "返金・取り消しのあとは、権利を持たない")
        XCTAssertFalse(store.adsRemoved)
        let restarted = makeStore()
        await restarted.refreshEntitlements()
        XCTAssertFalse(restarted.adsRemoved)
        // 返金のあとは、もう一度買える
        await store.loadProducts()
        await store.purchase(.adFree)
        XCTAssertTrue(store.adsRemoved)
    }

    func testRevocationArrivingWhileRunningIsApplied() async throws {
        let store = await loadedStore()
        store.start()
        await store.purchase(.adFree)
        XCTAssertTrue(store.adsRemoved)
        let ids = await adFreeTransactionIDs()
        let id = try XCTUnwrap(ids.first)
        try session.refundTransaction(identifier: UInt(id))
        // Transaction.updates で届く取り消しが、反映される
        for _ in 0..<50 where store.adsRemoved { try await Task.sleep(for: .milliseconds(100)) }
        XCTAssertFalse(store.adsRemoved)
    }

    // MARK: ふとを応援（消耗型）

    func testTipCanBePurchasedRepeatedlyAndDoesNotRemoveAds() async throws {
        let suite = UUID().uuidString
        let store = makeStore(suite: suite)
        await store.refreshEntitlements()
        await store.loadProducts()
        for round in 1...3 {
            store.clearThanks()
            await store.purchase(.tip)
            XCTAssertTrue(store.thanksForTip, "購入のたびに、お礼を出す（\(round)回目）")
            XCTAssertFalse(store.adsRemoved, "応援だけでは、広告は消えない（\(round)回目）")
            XCTAssertNil(store.message)
        }
        let unfinished = await unfinishedCount()
        XCTAssertEqual(unfinished, 0, "消耗型の取引は、完了ずみ")
        let processed = UserDefaults(suiteName: suite)!.stringArray(forKey: "support.processedTipTransactions") ?? []
        XCTAssertEqual(Set(processed).count, 3, "3回の取引を、それぞれ1回ずつ記録")
        let restarted = makeStore()
        await restarted.refreshEntitlements()
        XCTAssertFalse(restarted.adsRemoved, "再起動しても、応援だけでは広告は消えない")
        XCTAssertFalse(restarted.adFreePurchased)
    }

    func testTipAndAdFreeAreIndependent() async throws {
        let store = await loadedStore()
        await store.purchase(.tip)
        XCTAssertFalse(store.adsRemoved)
        await store.purchase(.adFree)
        XCTAssertTrue(store.adsRemoved)
        store.clearThanks()
        await store.purchase(.tip)
        XCTAssertTrue(store.thanksForTip, "広告なしを買ったあとも、応援はできる")
    }

    // MARK: キャンセル・保留・失敗

    func testCancelledPurchaseGrantsNothing() async throws {
        let store = await loadedStore()
        try await session.setSimulatedError(.generic(.userCancelled), forAPI: .purchase)
        await store.purchase(.adFree)
        await store.purchase(.tip)
        XCTAssertFalse(store.adsRemoved)
        XCTAssertFalse(store.thanksForTip)
        XCTAssertNil(store.message, "キャンセルでは、何も表示しない")
        await store.refreshEntitlements()
        XCTAssertFalse(store.adsRemoved)
    }

    func testFailedPurchaseGrantsNothingAndShowsMessage() async throws {
        let store = await loadedStore()
        try await session.setSimulatedError(.generic(.networkError(URLError(.notConnectedToInternet))), forAPI: .purchase)
        await store.purchase(.adFree)
        XCTAssertFalse(store.adsRemoved)
        XCTAssertEqual(store.message, tr("購入できませんでした\nもう一度お試しください"))
        store.message = nil
        await store.purchase(.tip)
        XCTAssertFalse(store.thanksForTip, "失敗した応援に、お礼は出さない")
        XCTAssertNotNil(store.message)
        await store.refreshEntitlements()
        XCTAssertFalse(store.adsRemoved)
    }

    func testPendingPurchaseGrantsNothing() async throws {
        let store = await loadedStore()
        session.askToBuyEnabled = true
        await store.purchase(.adFree)
        XCTAssertFalse(store.adsRemoved)
        XCTAssertEqual(store.message, tr("承認を待っています"))
        store.message = nil
        await store.purchase(.tip)
        XCTAssertFalse(store.thanksForTip, "承認待ちの応援に、お礼は出さない")
        XCTAssertEqual(store.message, tr("承認を待っています"))
        await store.refreshEntitlements()
        XCTAssertFalse(store.adsRemoved)
    }
}
