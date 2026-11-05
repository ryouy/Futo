import StoreKit
import SwiftUI

/// 設定 → ふとを応援。月額の2つのプラン（どちらも任意。基本の機能は、ずっと無料）。
/// ホームや待機の画面では、加入をすすめる表示は出さない。
@MainActor
struct SupportView: View {
    @Environment(SupportStore.self) private var store
    @Environment(SharingModel.self) private var sharing
    @State private var showManage = false

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("どちらも任意です"))
                    Text(tr("基本の機能は、ずっと無料です"))
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 0, trailing: 8))
            }

            if let plan = store.accountPlan, store.current == nil {
                // アカウントで加入している（アプリの外での加入）。二重に購入しないよう、購入のボタンは出さない
                CardSection {
                    Label(tr("{0}に加入中", plan.title), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Theme.accentText)
                        .frame(minHeight: 44)
                    Text(tr("このアカウントの加入が、反映されています")).font(.footnote).foregroundStyle(.secondary)
                }
            } else {
                ForEach(SupportPlan.allCases) { plan in
                    planCard(plan)
                }
            }

            if let message = store.message {
                CardSection { Text(message).font(.footnote).foregroundStyle(.secondary) }
            }

            CardSection {
                Button { Task { await store.restore() } } label: {
                    Label(tr("購入を復元"), systemImage: "arrow.clockwise").foregroundStyle(Theme.accentText)
                }
                .frame(minHeight: 44)
                .disabled(store.isWorking)
                Button { showManage = true } label: {
                    Label(tr("契約の管理"), systemImage: "creditcard").foregroundStyle(Theme.accentText)
                }
                .frame(minHeight: 44)
                if let privacy = privacyURL {
                    Link(destination: privacy) {
                        Label(tr("プライバシーポリシー"), systemImage: "hand.raised").foregroundStyle(Theme.accentText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 44)
                }
            }

            Section {
                Text(tr("2つのプランは、同時には加入できません"))
                    .font(.footnote).foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
            }
        }
        .compactForm()
        .navigationTitle(tr("ふとを応援"))
        .navigationBarTitleDisplayMode(.inline)
        .manageSubscriptionsSheet(isPresented: $showManage)
        .task {
            await store.refreshEntitlements()
            if store.products.isEmpty { await store.loadProducts() }
        }
    }

    /// プライバシーポリシー（共有・招待と同じドメインの /privacy。アプリから開くので、戻り先は、アプリ用の紹介ページ）
    private var privacyURL: URL? {
        (sharing.config.apiBaseURL ?? URL(string: "https://futo-share.vercel.app")).flatMap { URL(string: "privacy?from=about", relativeTo: $0)?.absoluteURL }
    }

    private func priceText(_ plan: SupportPlan) -> String {
        let price: String
        if let product = store.products[plan] {
            // 金額と通貨はストアのまま。英語表示のときだけ、書式（記号の位置・区切り）を英語向けにする
            price = LanguageStore.shared.language == .en
                ? product.price.formatted(product.priceFormatStyle.locale(Locale(identifier: "en_US")))
                : product.displayPrice
        } else {
            price = "¥\(plan.fallbackPrice)"
        }
        return tr("{0} / 月", price)
    }

    private func planCard(_ plan: SupportPlan) -> some View {
        let isCurrent = store.current == plan
        return CardSection {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(plan.title).font(.headline)
                    Spacer(minLength: 8)
                    Text(priceText(plan)).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(plan.lines, id: \.self) { Text($0) }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                if isCurrent {
                    Label(tr("加入中"), systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.accentText)
                        .frame(maxWidth: .infinity, minHeight: 44)
                } else if store.products[plan] == nil {
                    if store.isLoadingProducts {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 44)
                    } else {
                        Button(tr("読み込み直す")) { Task { await store.loadProducts() } }
                            .buttonStyle(FutoButtonStyle(prominent: false))
                    }
                } else {
                    Button(store.current == nil ? tr("加入する") : tr("このプランに変更")) {
                        Task { await store.purchase(plan) }
                    }
                    .buttonStyle(FutoButtonStyle(prominent: store.current == nil))
                    .disabled(store.isWorking)
                }
            }
            .padding(.vertical, 4)
        }
    }
}
