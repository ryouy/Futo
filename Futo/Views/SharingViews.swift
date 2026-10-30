import CoreImage.CIFilterBuiltins
import SwiftData
import SwiftUI

/// 設定の「共有」タブ。ログインは任意で、しなくても、ほかの機能はすべて使える。
@MainActor
struct SharingTab: View {
    let model: AppModel
    @Environment(SharingModel.self) private var sharing
    @State private var confirmSignOut = false
    @State private var confirmDelete = false

    var body: some View {
        Form {
            if !sharing.isConfigured {
                CardSection {
                    Text(tr("共有の機能は、まだ使えません。"))
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
                Text(tr("ログインすると、選んだ記録だけを、リンクやフレンドに共有できます。"))
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
            NavigationLink { ProfileView() } label: {
                HStack(spacing: 14) {
                    AccountAvatar(name: sharing.profile?.displayName ?? "", photoURL: sharing.auth.photoURL, size: 48, isOwn: true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sharing.profile?.displayName ?? "…").font(.headline).oneLine()
                        Text(tr("Googleでログイン中")).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            .accessibilityHint(tr("プロフィールを変える"))
        }
        CardSection {
            NavigationLink { SharedLinksView(model: model) } label: {
                Label(tr("記録をリンクで共有"), systemImage: "link").foregroundStyle(Theme.accent)
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
                Label(tr("ログアウト"), systemImage: "rectangle.portrait.and.arrow.right").foregroundStyle(Theme.accent)
            }
            .frame(minHeight: 44)
            Button(role: .destructive) { confirmDelete = true } label: {
                Label(tr("アカウントを削除"), systemImage: "trash").foregroundStyle(.red)
            }
            .frame(minHeight: 44)
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
                                    recipientUids: isFriends ? Array(chosen) : nil, allowsMessage: isFriends,
                                    events: model.events.all())
    }

    private var messageProblem: String? {
        guard isFriends, let text = ShareMessage.normalized(selection.message) else { return nil }
        return ShareMessage.looksLikeLink(text) ? tr("リンクやURLは、一言に入れられません。") : nil
    }

    private var canCreate: Bool {
        selection.hasStats && !sharing.isWorking && messageProblem == nil && (!isFriends || !chosen.isEmpty)
    }

    var body: some View {
        Form {
            if isFriends { whoSection }
            contentSection
            optionsSection
            preview
            footer
        }
        .compactForm()
        .environment(\.defaultMinListRowHeight, 40)
        .navigationTitle(isFriends ? tr("フレンドに記録を共有") : tr("記録をリンクで共有"))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: 入力

    private func header(_ title: String) -> some View {
        Text(title).font(.footnote.weight(.semibold)).foregroundStyle(Theme.accent).textCase(nil)
    }

    private var whoSection: some View {
        Section {
            if recipients.isEmpty {
                Text(tr("まだフレンドがいません。")).font(.footnote).foregroundStyle(.secondary)
            } else {
                ForEach(recipients) { friend in
                    Button {
                        if chosen.contains(friend.uid) { chosen.remove(friend.uid) } else { chosen.insert(friend.uid) }
                    } label: {
                        HStack(spacing: 10) {
                            AccountAvatar(name: friend.displayName, size: 28)
                            Text(friend.displayName).foregroundStyle(.primary).oneLine()
                            Spacer(minLength: 0)
                            Image(systemName: chosen.contains(friend.uid) ? "checkmark.circle.fill" : "circle")
                                .font(.title3).foregroundStyle(chosen.contains(friend.uid) ? Theme.accent : .secondary)
                        }
                        .frame(minHeight: 40)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(chosen.contains(friend.uid) ? .isSelected : [])
                }
            }
        } header: {
            HStack {
                header(tr("誰に共有する？"))
                Spacer()
                if recipients.count > 1 {
                    Button(chosen.count == recipients.count ? tr("すべて外す") : tr("全員を選ぶ")) {
                        chosen = chosen.count == recipients.count ? [] : Set(recipients.map(\.uid))
                    }
                    .font(.footnote.weight(.medium)).foregroundStyle(Theme.accent).textCase(nil)
                }
            }
        }
        .listRowBackground(Theme.card)
    }

    private var contentSection: some View {
        Section {
            Toggle(tr("ひと呼吸の結果"), isOn: $selection.counts)
            Toggle(tr("使いたかった目的"), isOn: $selection.purposes)
            Toggle(tr("使ったあとの感想"), isOn: $selection.feelings)
            Toggle(isOn: $selection.apps) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(tr("よく解除したアプリ"))
                    if let note = appsNote { Text(note).font(.caption).foregroundStyle(.secondary) }
                }
            }
            Toggle(tr("制限の管理"), isOn: $selection.restriction)
        } header: {
            header(tr("共有する記録"))
        }
        .listRowBackground(Theme.card)
    }

    /// アプリ名を読み取れないときだけ、短く理由を出す。
    private var appsNote: String? {
        guard selection.apps else { return nil }
        let availability = AppNameResolver.availability(sessions: allSessions, mode: model.mode, interval: nil)
        if availability.total > 0, availability.named == 0 { return tr("名前を読み取れません") }
        return nil
    }

    private var optionsSection: some View {
        Section {
            Picker(tr("期間"), selection: $period) {
                ForEach(SharePeriod.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            if isFriends {
                HStack(spacing: 8) {
                    TextField(tr("ひとこと（任意）"), text: $selection.message, axis: .vertical)
                        .lineLimit(1...2)
                        .onChange(of: selection.message) { _, value in
                            if value.count > ShareMessage.maxLength { selection.message = String(value.prefix(ShareMessage.maxLength)) }
                        }
                    Menu {
                        ForEach(SharePhrase.allCases) { phrase in Button(phrase.text) { selection.message = phrase.text } }
                        if !selection.message.isEmpty { Button(tr("消す"), role: .destructive) { selection.message = "" } }
                    } label: {
                        Image(systemName: "text.quote").foregroundStyle(Theme.accent).frame(width: 36, height: 36)
                    }
                    .accessibilityLabel(tr("定型文から選ぶ"))
                }
                if let problem = messageProblem { Text(problem).font(.caption).foregroundStyle(.red) }
            } else {
                Picker(tr("ひとこと"), selection: Binding(get: { selection.phrase?.rawValue ?? "" }, set: { selection.phrase = SharePhrase(rawValue: $0) })) {
                    Text(tr("なし")).tag("")
                    ForEach(SharePhrase.allCases) { Text($0.text).tag($0.rawValue) }
                }
            }
            Toggle(tr("表示名を出す"), isOn: $selection.showName)
            if isFriends {
                Toggle(tr("アプリを開いたとき、最新にする"), isOn: $standing)
            } else {
                Picker(tr("有効期間"), selection: $expiresInDays) {
                    Text(tr("1日")).tag(1); Text(tr("7日")).tag(7); Text(tr("30日")).tag(30)
                }
                .pickerStyle(.segmented)
            }
        } header: {
            header(tr("設定"))
        }
        .listRowBackground(Theme.card)
    }

    // MARK: 確認と実行

    /// 送る内容そのままを、グラフで見せる。長いときは、この枠の中でスクロールできる。
    private var preview: some View {
        Section {
            if let payload {
                ScrollView {
                    StatsChartsView(stats: ChartStats(payload: payload))
                        .padding(.vertical, 2)
                }
                .frame(height: 190)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)
            } else {
                Text(tr("項目を選ぶと、ここに表示されます。")).font(.footnote).foregroundStyle(.secondary)
                    .listRowBackground(Theme.card)
            }
        } header: {
            HStack {
                header(tr("共有される内容"))
                Spacer()
                Text(selection.showName ? (sharing.profile?.displayName ?? "") : tr("匿名")).font(.caption).foregroundStyle(.secondary).textCase(nil)
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
            }
        } else if done {
            CardSection {
                Label(tr("共有しました。"), systemImage: "checkmark.circle.fill").foregroundStyle(Theme.accent)
            }
        } else {
            PrimarySection {
                Button(isFriends ? tr("フレンドに記録を共有") : tr("リンクを作る")) { Task { await create() } }
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
                        HStack(spacing: 8) {
                            if let url = sharing.localURL(for: item) {
                                Link(destination: url) { Image(systemName: "safari") }.accessibilityLabel(tr("開く"))
                                ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }.accessibilityLabel(tr("送る"))
                                CopyChip(text: url.absoluteString)
                            }
                            Button { Task { rotated = await sharing.rotateShare(item) } } label: { Image(systemName: "arrow.triangle.2.circlepath") }
                                .accessibilityLabel(tr("作り直す"))
                            Button(role: .destructive) { confirmRevoke = item } label: { Image(systemName: "stop.circle") }
                                .accessibilityLabel(tr("停止"))
                        }
                        .buttonStyle(ChipButtonStyle())
                    }
                }
            }
            if let rotated {
                CardSection {
                    Label(tr("新しいリンクを作りました"), systemImage: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                    HStack(spacing: 8) {
                        ShareLink(item: rotated) { Image(systemName: "square.and.arrow.up") }.accessibilityLabel(tr("送る"))
                        Link(destination: rotated) { Image(systemName: "safari") }.accessibilityLabel(tr("開く"))
                        CopyChip(text: rotated.absoluteString)
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

/// アイコン。自分のもの（`isOwn`）は、設定に従う：Googleの写真があれば写真、なければ（または写真を使わない設定なら）選んだ色の丸に頭文字。
/// 相手のものは、頭文字だけ（相手の写真・色は、受け取らない）。画像はこの端末の表示だけに使い、サーバーには送らない。
struct AccountAvatar: View {
    let name: String
    var photoURL: URL? = nil
    var size: CGFloat = 32
    var isOwn = false
    private var settings: AvatarSettings { .shared }

    var body: some View {
        ZStack {
            if isOwn, let index = settings.symbolIndex, AvatarSettings.symbols.indices.contains(index) {
                Circle().fill(settings.fill(themeColor: Theme.accent))
                    .overlay(Image(systemName: AvatarSettings.symbols[index].name)
                        .font(.system(size: size * 0.48, weight: .medium)).foregroundStyle(.white))
            } else {
                initial
            }
            if isOwn, settings.showsPhoto(available: photoURL != nil), let photoURL {
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
            .fill(isOwn ? settings.fill(themeColor: Theme.accent) : Theme.accent)
            .overlay(
                Text(String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
                    .font(.system(size: size * 0.45, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            )
    }
}

/// プロフィール：アイコン（Googleの写真・頭文字・山や海などの12個）と色、表示名。保存は、いちばん下。
@MainActor
struct ProfileView: View {
    @Environment(SharingModel.self) private var sharing
    @State private var name = ""
    @State private var saved = false
    private var avatar: AvatarSettings { .shared }

    private var displayName: String { sharing.profile?.displayName ?? "" }
    private var hasPhoto: Bool { sharing.auth.photoURL != nil }
    private var usesPhoto: Bool { avatar.showsPhoto(available: hasPhoto) }
    private var usesInitial: Bool { !usesPhoto && avatar.symbolIndex == nil }
    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !trimmed.isEmpty && trimmed.count <= 20 && trimmed != displayName && !sharing.isWorking }

    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    AccountAvatar(name: name.isEmpty ? displayName : name, photoURL: sharing.auth.photoURL, size: 84, isOwn: true)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }

            CardSection { iconGrid }

            if !usesPhoto { CardSection { colorPicker } }

            CardSection {
                TextField(tr("表示名（1〜20文字）"), text: $name)
            }

            PrimarySection {
                Button {
                    Task { saved = await sharing.saveDisplayName(trimmed) }
                } label: {
                    Label(saved ? tr("保存しました") : tr("保存"), systemImage: saved ? "checkmark.circle.fill" : "square.and.arrow.down")
                }
                .disabled(!canSave && !saved)
            }
        }
        .compactForm()
        .animation(.easeInOut(duration: 0.3), value: usesPhoto)
        .navigationTitle(tr("プロフィール"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { name = displayName }
        .onChange(of: name) { _, new in if new != displayName { saved = false } }
    }

    // MARK: アイコン

    private var iconGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 10)], spacing: 10) {
            if hasPhoto {
                iconCell(selected: usesPhoto, label: tr("Googleの写真")) { avatar.selectPhoto() } content: {
                    AccountAvatar(name: displayName, photoURL: sharing.auth.photoURL, size: 40, isOwn: true)
                        .opacity(1)
                        .overlay(Circle().fill(.clear))
                        .background(photoPreview)
                }
            }
            iconCell(selected: usesInitial, label: tr("頭文字")) { avatar.selectInitial() } content: {
                Circle().fill(avatar.fill(themeColor: Theme.accent)).frame(width: 40, height: 40)
                    .overlay(Text(String(displayName.prefix(1)).uppercased()).font(.system(size: 18, weight: .semibold, design: .rounded)).foregroundStyle(.white))
            }
            ForEach(Array(AvatarSettings.symbols.enumerated()), id: \.offset) { index, symbol in
                iconCell(selected: avatar.symbolIndex == index && !usesPhoto, label: symbol.label) { avatar.selectSymbol(index) } content: {
                    Circle().fill(avatar.fill(themeColor: Theme.accent)).frame(width: 40, height: 40)
                        .overlay(Image(systemName: symbol.name).font(.system(size: 19, weight: .medium)).foregroundStyle(.white))
                }
            }
        }
    }

    /// 写真のセルは、写真そのものを丸く出す（設定の色や記号に左右されない）。
    private var photoPreview: some View {
        AsyncImage(url: sharing.auth.photoURL) { phase in
            if case .success(let image) = phase { image.resizable().scaledToFill() }
        }
        .frame(width: 40, height: 40)
        .clipShape(Circle())
    }

    private func iconCell<Content: View>(selected: Bool, label: String, action: @escaping () -> Void, @ViewBuilder content: () -> Content) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) { action() }
            saved = false
        } label: {
            content()
                .frame(width: 48, height: 48)
                .overlay(Circle().stroke(Theme.accent.opacity(selected ? 1 : 0), lineWidth: 2.5).padding(-2))
                .frame(width: 52, height: 52)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var colorPicker: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 12)], spacing: 12) {
            swatch(index: nil, color: Theme.accent)
            ForEach(Array(AvatarSettings.palette.enumerated()), id: \.offset) { index, hex in
                swatch(index: index, color: AvatarSettings.color(hex: hex))
            }
        }
        .padding(.vertical, 4)
    }

    private func swatch(index: Int?, color: Color) -> some View {
        let selected = avatar.colorIndex == index
        return Button {
            withAnimation(.easeInOut(duration: 0.25)) { avatar.colorIndex = index }
        } label: {
            Circle().fill(color).frame(width: 36, height: 36)
                .overlay(Image(systemName: "checkmark").font(.footnote.bold()).foregroundStyle(.white).opacity(selected ? 1 : 0))
                .overlay(Circle().stroke(.primary.opacity(selected ? 0.6 : 0), lineWidth: 2).padding(-4))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(index == nil ? tr("テーマの色") : tr("色 {0}", "\((index ?? 0) + 1)"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

func periodLabel(_ period: String) -> String {
    switch period {
    case "thisWeek": return tr("今週")
    case "lastWeek": return tr("先週")
    default: return tr("全期間")
    }
}
