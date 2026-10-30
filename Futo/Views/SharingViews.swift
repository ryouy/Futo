import CoreImage.CIFilterBuiltins
import SwiftData
import SwiftUI

/// 設定の「共有」タブ。ログインは任意で、しなくても、ほかの機能はすべて使える。
@MainActor
struct SharingTab: View {
    let model: AppModel
    @Environment(SharingModel.self) private var sharing
    @State private var editingName = false
    @State private var nameDraft = ""
    @State private var confirmSignOut = false
    @State private var confirmDelete = false

    var body: some View {
        Form {
            if !sharing.isConfigured {
                CardSection {
                    Text(tr("共有の機能は、まだ使えません。"))
                    Text(tr("このアプリには、共有サーバーの設定が入っていません。個人の機能は、そのまま使えます。"))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } else if model.mode == .demo {
                CardSection {
                    Text(tr("デモモードでは、共有できません。"))
                    Text(tr("実際の記録だけを、共有できます。"))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } else {
                switch sharing.auth.state {
                case .signedOut, .signingIn: signedOut
                case .needsReauth: needsReauth
                case .signedIn: signedIn
                }
            }
            if let message = sharing.message {
                CardSection { Text(message).font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .compactForm()
        .task { if sharing.isSignedIn { await sharing.loadProfile() } }
        .alert(tr("表示名"), isPresented: $editingName) {
            TextField(tr("1〜20文字"), text: $nameDraft)
            Button(tr("保存")) { Task { _ = await sharing.saveDisplayName(nameDraft) } }
            Button(tr("キャンセル"), role: .cancel) {}
        } message: {
            Text(tr("リンクの先やフレンドに表示されます。"))
        }
        .confirmationDialog(tr("ログアウトしますか？ 共有中のリンクは、そのまま有効です。"), isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button(tr("ログアウト"), role: .destructive) { sharing.signOut() }
            Button(tr("キャンセル"), role: .cancel) {}
        }
        .confirmationDialog(tr("アカウントと、共有・フレンドのデータをすべて削除しますか？ 取り消せません。端末の記録は消えません。"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(tr("削除する"), role: .destructive) { Task { _ = await sharing.deleteAccount() } }
            Button(tr("キャンセル"), role: .cancel) {}
        }
    }

    private var signedOut: some View {
        Group {
            CardSection {
                Text(tr("ログインすると、選んだ統計だけを、リンクやフレンドに共有できます。"))
                Text(tr("ログインしなくても、ほかの機能はすべて使えます。履歴や設定は、アップロードされません。"))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            PrimarySection {
                Button { Task { await sharing.signIn() } } label: {
                    Label(tr("Googleでログイン"), systemImage: "person.crop.circle.badge.checkmark")
                }
                .disabled(sharing.isWorking)
            }
        }
    }

    private var needsReauth: some View {
        Group {
            CardSection { Text(tr("ログインの確認が必要です。")) }
            PrimarySection {
                Button(tr("もう一度ログイン")) { Task { await sharing.signIn() } }
                Button(tr("ログアウト"), role: .destructive) { sharing.signOut() }
                    .buttonStyle(FutoButtonStyle(prominent: false))
            }
        }
    }

    @ViewBuilder
    private var signedIn: some View {
        CardSection {
            Button { nameDraft = sharing.profile?.displayName ?? ""; editingName = true } label: {
                HStack(spacing: 14) {
                    AccountAvatar(name: sharing.profile?.displayName ?? "", photoURL: sharing.auth.photoURL, size: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sharing.profile?.displayName ?? "…").font(.headline).foregroundStyle(.primary).oneLine()
                        Text(tr("Googleでログイン中")).font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "pencil").font(.footnote).foregroundStyle(Theme.accent)
                }
                .padding(.vertical, 4)
            }
            .accessibilityHint(tr("表示名を変える"))
        }
        CardSection {
            NavigationLink { SharedLinksView(model: model) } label: {
                Label(tr("リンクで共有"), systemImage: "link").foregroundStyle(Theme.accent)
            }.frame(minHeight: 44)
            NavigationLink { FriendsView(model: model) } label: {
                Label(tr("フレンド"), systemImage: "person.2").foregroundStyle(Theme.accent)
            }.frame(minHeight: 44)
            NavigationLink { BackupView() } label: {
                Label(tr("バックアップ"), systemImage: "icloud").foregroundStyle(Theme.accent)
            }.frame(minHeight: 44)
        }
        CardSection {
            Button { confirmSignOut = true } label: {
                Label(tr("ログアウト"), systemImage: "rectangle.portrait.and.arrow.right")
            }.frame(minHeight: 44)
            Button(role: .destructive) { confirmDelete = true } label: {
                Label(tr("アカウントを削除"), systemImage: "trash")
            }.frame(minHeight: 44)
        }
    }
}

// MARK: - 共有の作成（プレビュー付き）

enum ShareKind { case web, friends }

@MainActor
struct CreateShareView: View {
    let model: AppModel
    let kind: ShareKind
    var recipients: [FriendsResponse.Friend] = []

    @Environment(SharingModel.self) private var sharing
    @Query private var allSessions: [Session]
    @State private var period: SharePeriod = .lastWeek
    @State private var selection = ShareSelection()
    @State private var expiresInDays = 7
    @State private var chosen: Set<String> = []
    @State private var created: URL?
    @State private var done = false
    @State private var standing = true
    @State private var showQR = false

    private var isFriends: Bool { kind == .friends }

    private var payload: SharePayload? {
        try? sharing.previewPayload(sessions: allSessions, mode: model.mode, period: period, selection: selection,
                                    expiresInDays: isFriends ? nil : expiresInDays,
                                    recipientUids: isFriends ? Array(chosen) : nil, allowsMessage: isFriends)
    }

    private var messageProblem: String? {
        guard isFriends, let text = ShareMessage.normalized(selection.message) else { return nil }
        return ShareMessage.looksLikeLink(text) ? tr("リンクやURLは、一言に入れられません。") : nil
    }

    private var canCreate: Bool {
        selection.hasStats && !sharing.isWorking && messageProblem == nil && (!isFriends || !chosen.isEmpty)
    }

    /// いまの設定を、ひとことで言い直す（送る前の最終確認）。
    private var summary: String {
        var items: [String] = []
        if selection.counts { items.append(tr("回数")) }
        if selection.purposes { items.append(tr("目的")) }
        if selection.feelings { items.append(tr("気持ち")) }
        let what = items.isEmpty ? tr("（項目が未選択）") : items.joined(separator: tr("・"))
        if isFriends {
            return tr("{0}人に、{1}（{2}）を共有します。", "\(chosen.count)", what, period.label)
        }
        return tr("リンクを知っている人に、{0}（{1}）を見せます。", what, period.label)
    }

    var body: some View {
        Form {
            if isFriends { whoSection }
            whatSection
            periodSection
            if isFriends { messageSection } else { phraseSection }
            nameSection
            if isFriends { updateSection } else { expirySection }
            preview
            footer
        }
        .compactForm()
        .navigationTitle(isFriends ? tr("フレンドに共有") : tr("リンクで共有"))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: 入力

    private func header(_ title: String, _ detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
            if let detail { Text(detail).font(.footnote).foregroundStyle(.secondary) }
        }
        .textCase(nil)
        .padding(.bottom, 2)
    }

    private var whoSection: some View {
        Section {
            if recipients.isEmpty {
                Text(tr("まだフレンドがいません。「フレンド」の画面から招待して、承認されると、ここで選べます。"))
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                ForEach(recipients) { friend in
                    Button {
                        if chosen.contains(friend.uid) { chosen.remove(friend.uid) } else { chosen.insert(friend.uid) }
                    } label: {
                        HStack(spacing: 12) {
                            AccountAvatar(name: friend.displayName, size: 34)
                            Text(friend.displayName).foregroundStyle(.primary).oneLine()
                            Spacer(minLength: 0)
                            Image(systemName: chosen.contains(friend.uid) ? "checkmark.circle.fill" : "circle")
                                .font(.title3).foregroundStyle(chosen.contains(friend.uid) ? Theme.accent : .secondary)
                        }
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(chosen.contains(friend.uid) ? .isSelected : [])
                }
                Button(chosen.count == recipients.count ? tr("選択をすべて外す") : tr("全員を選ぶ")) {
                    chosen = chosen.count == recipients.count ? [] : Set(recipients.map(\.uid))
                }
                .buttonStyle(ChipButtonStyle())
            }
        } header: {
            header(tr("① 誰に共有する？"), tr("選んだ人だけが見られます。ほかのフレンドや、ほかの人には見えません。"))
        }
        .listRowBackground(Theme.card)
    }

    private var whatSection: some View {
        Section {
            Toggle(isOn: $selection.counts) { toggleLabel(tr("回数"), tr("使いたい・やめておく・中断の数")) }
            Toggle(isOn: $selection.purposes) { toggleLabel(tr("目的"), tr("使いたかった理由の内訳")) }
            Toggle(isOn: $selection.feelings) { toggleLabel(tr("気持ち"), tr("使ったあとの感想の内訳")) }
            Toggle(isOn: $selection.apps) { toggleLabel(tr("アプリ名"), appsDetail) }
        } header: {
            header(isFriends ? tr("② 何を見せる？") : tr("① 何を見せる？"), tr("選んだ項目だけが共有されます。記録の一覧や、アプリの名前は含まれません。"))
        }
        .listRowBackground(Theme.card)
    }

    /// アプリ名の説明。名前を読み取れない・解除の記録がないときは、その理由を正直に出す。
    private var appsDetail: String {
        guard selection.apps else { return tr("含めません") }
        let availability = AppNameResolver.availability(sessions: allSessions, mode: model.mode, interval: nil)
        if availability.total == 0 { return tr("解除した記録がまだありません") }
        if availability.named == 0 { return tr("名前を読み取れませんでした（含まれません）") }
        return tr("よく解除したアプリの名前と回数（最大10件）")
    }

    private func toggleLabel(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var periodSection: some View {
        Section {
            Picker(tr("期間"), selection: $period) {
                ForEach(SharePeriod.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            Text(periodHint).font(.footnote).foregroundStyle(.secondary)
        } header: {
            header(isFriends ? tr("③ いつの分？") : tr("② いつの分？"))
        }
        .listRowBackground(Theme.card)
    }

    private var periodHint: String {
        switch period {
        case .thisWeek: return tr("今週の、いままでの分です（途中経過）。")
        case .lastWeek: return tr("先週の1週間の分です。")
        case .all: return tr("最初の記録から、いままでの分です。")
        }
    }

    /// フレンドへの一言：自由に入力できる。定型文から選んで、直すこともできる。
    private var messageSection: some View {
        Section {
            TextField(tr("例：今週は少しがんばった！"), text: $selection.message, axis: .vertical)
                .lineLimit(1...3)
                .onChange(of: selection.message) { _, value in
                    if value.count > ShareMessage.maxLength { selection.message = String(value.prefix(ShareMessage.maxLength)) }
                }
            HStack {
                Menu {
                    ForEach(SharePhrase.allCases) { phrase in Button(phrase.text) { selection.message = phrase.text } }
                    if !selection.message.isEmpty { Button(tr("消す"), role: .destructive) { selection.message = "" } }
                } label: {
                    Label(tr("定型文から選ぶ"), systemImage: "text.quote")
                }
                .buttonStyle(ChipButtonStyle()).fixedSize()
                Spacer()
                Text("\(selection.message.count)/\(ShareMessage.maxLength)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            if let problem = messageProblem { Text(problem).font(.footnote).foregroundStyle(.red) }
        } header: {
            header(tr("④ ひとこと（任意）"), tr("相手に、短いメッセージを添えられます。空のままでも共有できます。"))
        }
        .listRowBackground(Theme.card)
    }

    private var phraseSection: some View {
        Section {
            Picker(tr("ひとこと"), selection: Binding(get: { selection.phrase?.rawValue ?? "" }, set: { selection.phrase = SharePhrase(rawValue: $0) })) {
                Text(tr("なし")).tag("")
                ForEach(SharePhrase.allCases) { Text($0.text).tag($0.rawValue) }
            }
        } header: {
            header(tr("③ ひとこと（任意）"), tr("公開リンクでは、決まった文から選べます。"))
        }
        .listRowBackground(Theme.card)
    }

    private var nameSection: some View {
        Section {
            Toggle(isOn: $selection.showName) {
                toggleLabel(tr("表示名を出す"), selection.showName ? tr("「{0}」と表示されます。", sharing.profile?.displayName ?? "") : tr("「匿名」と表示されます。"))
            }
        } header: {
            header(isFriends ? tr("⑤ 名前") : tr("④ 名前"))
        }
        .listRowBackground(Theme.card)
    }

    private var updateSection: some View {
        Section {
            Toggle(isOn: $standing) { toggleLabel(tr("アプリを開いたとき、最新にする"), standing ? tr("継続して共有します") : tr("1回だけ共有します")) }
            Text(standing
                 ? tr("選んだ項目だけが、アプリを開くたびに更新されます。最後の更新から30日たつと、自動で見えなくなります。")
                 : tr("いまの内容を、1回だけ共有します。30日で見えなくなります。"))
                .font(.footnote).foregroundStyle(.secondary)
        } header: {
            header(tr("⑥ 更新のしかた"))
        }
        .listRowBackground(Theme.card)
    }

    private var expirySection: some View {
        Section {
            Picker(tr("有効期間"), selection: $expiresInDays) {
                Text(tr("1日")).tag(1); Text(tr("7日")).tag(7); Text(tr("30日")).tag(30)
            }
            .pickerStyle(.segmented)
        } header: {
            header(tr("⑤ いつまで見られる？"), tr("期限がくると、リンクは自動で使えなくなります。"))
        }
        .listRowBackground(Theme.card)
    }

    // MARK: 確認と実行

    /// 送る内容そのままを、先にグラフで見せる。
    private var preview: some View {
        Group {
            if let payload {
                Section {
                    StatsChartsView(stats: ChartStats(payload: payload))
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        .listRowBackground(Color.clear)
                } header: {
                    header(tr("共有される内容"), selection.showName ? tr("表示名：{0}", sharing.profile?.displayName ?? "") : tr("表示名：匿名"))
                }
            } else {
                CardSection {
                    Text(tr("項目を選ぶと、ここにグラフで表示されます。")).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if let created {
            CardSection {
                HStack(spacing: 8) {
                    Label(tr("リンクを作りました"), systemImage: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                    Spacer(minLength: 0)
                    CopyIconButton(text: created.absoluteString)
                }
                HStack(spacing: 8) {
                    ShareLink(item: created) { Label(tr("送る"), systemImage: "square.and.arrow.up") }.buttonStyle(ChipButtonStyle())
                    Link(destination: created) { Label(tr("開く"), systemImage: "safari") }.buttonStyle(ChipButtonStyle())
                }
                Toggle(tr("QRコードを表示"), isOn: $showQR.animation())
                if showQR {
                    QRImage(text: created.absoluteString).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                Text(tr("リンクを知っている人は、期限まで見られます。転送されることもあります。やめたいときは「共有中のリンク」から止めてください。"))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        } else if done {
            CardSection {
                Label(tr("共有しました。"), systemImage: "checkmark.circle.fill").foregroundStyle(Theme.accent)
            }
        } else {
            CardSection { Text(summary).font(.footnote.weight(.medium)) }
            PrimarySection {
                Button(isFriends ? tr("フレンドに共有") : tr("リンクを作る")) { Task { await create() } }
                    .disabled(!canCreate)
            }
            if let message = sharing.message { CardSection { Text(message).font(.footnote).foregroundStyle(.secondary) } }
        }
    }

    private func create() async {
        guard let payload else { return }
        switch kind {
        case .web: created = await sharing.createWebShare(payload)
        case .friends: done = await sharing.createFriendShare(payload, standing: standing ? (period, selection) : nil)
        }
    }
}

/// 文字列をQRコードで表示する。
struct QRImage: View {
    let text: String
    var body: some View {
        if let image = Self.make(text) {
            Image(uiImage: image).interpolation(.none).resizable().scaledToFit().frame(width: 180, height: 180)
                .accessibilityLabel(tr("QRコード"))
        }
    }

    static func make(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// MARK: - 共有中のリンク

@MainActor
struct SharedLinksView: View {
    let model: AppModel
    @Environment(SharingModel.self) private var sharing
    @State private var confirmRevoke: ShareListItem?
    @State private var rotated: URL?

    var body: some View {
        Form {
            CardSection {
                NavigationLink { CreateShareView(model: model, kind: .web) } label: {
                    Label(tr("新しいリンクを作る"), systemImage: "plus.circle").foregroundStyle(Theme.accent)
                }.frame(minHeight: 44)
            }
            if sharing.shares.allSatisfy({ $0.status == "revoked" }) {
                CardSection { Text(tr("共有中のリンクはありません。")).foregroundStyle(.secondary) }
            }
            ForEach(sharing.shares.filter { $0.status != "revoked" }) { item in
                CardSection {
                    HStack {
                        Text(periodLabel(item.period)).font(.headline)
                        Spacer()
                        Text(statusText(item.status)).font(.footnote.weight(.medium))
                            .foregroundStyle(item.status == "active" ? Theme.accent : .secondary)
                    }
                    Text(tr("期限：{0}", dateText(item.expiresAt))).font(.footnote).foregroundStyle(.secondary)
                    if item.status == "active" {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                            if let url = sharing.localURL(for: item) {
                                Link(destination: url) { Label(tr("開く"), systemImage: "safari") }
                                ShareLink(item: url) { Label(tr("送る"), systemImage: "square.and.arrow.up") }
                            }
                            Button { Task { rotated = await sharing.rotateShare(item) } } label: { Label(tr("作り直す"), systemImage: "arrow.triangle.2.circlepath") }
                            Button(role: .destructive) { confirmRevoke = item } label: { Label(tr("停止"), systemImage: "stop.circle") }
                        }
                        .buttonStyle(ChipButtonStyle())
                        .padding(.vertical, 2)
                    }
                }
            }
            if let rotated {
                CardSection {
                    Text(tr("新しいリンクです。古いリンクは、使えなくなりました。")).font(.footnote)
                    HStack(spacing: 8) {
                        ShareLink(item: rotated) { Label(tr("送る"), systemImage: "square.and.arrow.up") }
                        Link(destination: rotated) { Label(tr("開く"), systemImage: "safari") }
                    }
                    .buttonStyle(ChipButtonStyle())
                }
            }
            if let message = sharing.message { CardSection { Text(message).font(.footnote) } }
        }
        .compactForm()
        .navigationTitle(tr("共有中のリンク"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await sharing.loadShares() }
        .confirmationDialog(tr("このリンクでの共有をやめますか？"), isPresented: Binding(get: { confirmRevoke != nil }, set: { if !$0 { confirmRevoke = nil } }), titleVisibility: .visible) {
            Button(tr("やめる"), role: .destructive) { if let item = confirmRevoke { Task { await sharing.revokeShare(item) } } }
            Button(tr("キャンセル"), role: .cancel) {}
        }
    }

    private func statusText(_ status: String) -> String {
        switch status {
        case "active": return tr("共有中")
        case "expired": return tr("期限切れ")
        default: return tr("停止済み")
        }
    }
}

func dateText(_ iso: String) -> String {
    let parser = ISO8601DateFormatter()
    parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let plain = ISO8601DateFormatter()
    guard let date = parser.date(from: iso) ?? plain.date(from: iso) else { return iso }
    return date.formatted(date: .abbreviated, time: .shortened)
}

/// ログイン中のしるし。Googleのアイコン画像があれば、それを丸く表示する。なければ、名前の頭文字をテーマ色の丸に載せる。
/// 画像はこの端末の表示だけに使い、サーバーには送らない。小さい画像を1回読み込むだけで、あとはキャッシュされる。
struct AccountAvatar: View {
    let name: String
    var photoURL: URL? = nil
    var size: CGFloat = 32

    var body: some View {
        ZStack {
            initial
            if let photoURL {
                AsyncImage(url: photoURL) { phase in
                    if case .success(let image) = phase { image.resizable().scaledToFill() }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var initial: some View {
        Circle()
            .fill(Theme.accent)
            .overlay(
                Text(String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
                    .font(.system(size: size * 0.45, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            )
    }
}

func periodLabel(_ period: String) -> String {
    switch period {
    case "thisWeek": return tr("今週")
    case "lastWeek": return tr("先週")
    default: return tr("全期間")
    }
}
