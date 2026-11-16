import SwiftUI

/// 設定 → 広告なし・応援。2つの商品は、どちらも一度きりの任意の購入（自動更新なし）。
/// 「広告なし」は買い切りで、広告が出なくなる。「ふとを応援」は、一回ごとの応援で、特典はない。
/// ホームや待機の画面では、購入をすすめる表示は出さない。
@MainActor
struct SupportView: View {
    @Environment(SupportStore.self) private var store
    @Environment(SharingModel.self) private var sharing

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

            adFreeCard
            tipCard

            if store.productsLoadFailed, !store.isLoadingProducts {
                CardSection {
                    Text(tr("商品の情報を読み込めませんでした\n今は、購入できません"))
                        .font(.footnote).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(tr("読み込み直す")) { Task { await store.loadProducts() } }
                        .buttonStyle(FutoButtonStyle(prominent: false))
                }
            }

            if let message = store.message {
                CardSection { Text(message).font(.footnote).foregroundStyle(.secondary) }
            }

            // 購入前に確認できるように、商品のすぐ下に置く（利用規約・プライバシーポリシー）
            CardSection {
                Text(tr("どちらも、一度きりの購入です　自動更新や、月ごとの課金はありません"))
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 24) {
                    Link(destination: Self.termsOfUseURL) {
                        Label(tr("利用規約"), systemImage: "doc.text").foregroundStyle(Theme.accentText)
                    }
                    if let privacy = privacyURL {
                        Link(destination: privacy) {
                            Label(tr("プライバシーポリシー"), systemImage: "hand.raised").foregroundStyle(Theme.accentText)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .font(.subheadline)
                .frame(minHeight: 44)
            }

            CardSection {
                Button { Task { await store.restore() } } label: {
                    Label(tr("購入を復元"), systemImage: "arrow.clockwise").foregroundStyle(Theme.accentText)
                }
                .frame(minHeight: 44)
                .disabled(store.isWorking)
                Text(tr("「広告なし」を購入ずみなら、入れ直しや機種変更のあとに、ここで戻せます"))
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .compactForm()
        .navigationTitle(tr("広告なし・応援"))
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { store.clearThanks() }
        .task {
            await store.refreshEntitlements()
            if store.products.count != SupportProduct.allCases.count { await store.loadProducts() }
        }
    }

    /// 利用規約（EULA）。ふと独自の規約は設けず、Apple 標準のライセンス契約（Standard EULA）を使う。
    static let termsOfUseURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    /// プライバシーポリシー（共有・招待と同じドメインの /privacy。アプリから開くので、戻り先は、アプリ用の紹介ページ）
    private var privacyURL: URL? {
        (sharing.config.apiBaseURL ?? URL(string: "https://futo-share.vercel.app")).flatMap { URL(string: "privacy?from=about", relativeTo: $0)?.absoluteURL }
    }

    /// 価格は、ストアが返した表示用の価格をそのまま出す（取れていなければ、出さない）。
    private func priceText(_ item: SupportProduct) -> String? {
        store.products[item]?.displayPrice
    }

    // MARK: 広告なし（買い切り）

    private var adFreeCard: some View {
        let item = SupportProduct.adFree
        return CardSection {
            VStack(alignment: .leading, spacing: 10) {
                header(item)
                details(item)
                if store.adFreePurchased {
                    Label(tr("購入済み"), systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.accentText)
                        .frame(maxWidth: .infinity, minHeight: 44)
                } else {
                    buyButton(item, label: tr("購入する"), prominent: true)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: ふとを応援（一回ごとの応援）

    private var tipCard: some View {
        let item = SupportProduct.tip
        return CardSection {
            VStack(alignment: .leading, spacing: 10) {
                header(item)
                details(item)
                if store.thanksForTip {
                    Label(tr("ありがとうございます\nいただいた応援は、ふとの開発と運営に使います"), systemImage: "heart.fill")
                        .font(.subheadline)
                        .foregroundStyle(Theme.accentText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                buyButton(item, label: tr("応援する"), prominent: false)
            }
            .padding(.vertical, 4)
        }
    }

    private func header(_ item: SupportProduct) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(item.title).font(.headline)
            Spacer(minLength: 8)
            if let price = priceText(item) {
                Text(price).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
    }

    private func details(_ item: SupportProduct) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(item.lines, id: \.self) { Text($0) }
            }
            .font(.subheadline)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(item.terms, id: \.self) { Text($0) }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func buyButton(_ item: SupportProduct, label: String, prominent: Bool) -> some View {
        if store.products[item] == nil {
            if store.isLoadingProducts {
                ProgressView().frame(maxWidth: .infinity, minHeight: 44)
            }
            // 取れなかったときは、購入のボタンを出さない（上の案内と「読み込み直す」だけ）
        } else {
            Button(label) { Task { await store.purchase(item) } }
                .buttonStyle(FutoButtonStyle(prominent: prominent))
                .disabled(store.isWorking)
        }
    }
}
