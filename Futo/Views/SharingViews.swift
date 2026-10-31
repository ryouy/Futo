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
                    Text(tr("共有の機能は、まだ使えません"))
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
        .confirmationDialog(tr("ログアウトしますか？ 共有中のリンクは、そのまま有効です"), isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button(tr("ログアウト"), role: .destructive) { sharing.signOut() }
            Button(tr("キャンセル"), role: .cancel) {}
        }
        .confirmationDialog(tr("アカウントと、共有・フレンドのデータをすべて削除しますか？ 取り消せません　端末の記録は消えません"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(tr("削除する"), role: .destructive) { Task { _ = await sharing.deleteAccount() } }
            Button(tr("キャンセル"), role: .cancel) {}
        }
    }

    private var signedOut: some View {
        Group {
            CardSection {
                Text(tr("ログインすると、選んだ記録だけを、リンクやフレンドに共有できます"))
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
            CardSection { Text(tr("ログインの確認が必要です")) }
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
                    AccountAvatar(name: sharing.profile?.displayName ?? "", size: 48, isOwn: true)
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
                Label(tr("記録をリンクで共有"), systemImage: "link").foregroundStyle(Theme.accentText)
            }.frame(minHeight: 44)
            NavigationLink { FriendsView(model: model) } label: {
                HStack {
                    Label(tr("フレンド"), systemImage: "person.2").foregroundStyle(Theme.accentText)
                    if sharing.hasUnseenRecords { NewBadge() }
                }
            }.frame(minHeight: 44)
            NavigationLink { BackupView() } label: {
                Label(tr("バックアップ"), systemImage: "icloud").foregroundStyle(Theme.accentText)
            }.frame(minHeight: 44)
        }
        CardSection {
            Button { confirmSignOut = true } label: {
                Label(tr("ログアウト"), systemImage: "rectangle.portrait.and.arrow.right").foregroundStyle(Theme.accentText)
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
    @State private var period: SharePeriod = .thisWeek
    @State private var selection = ShareSelection()
    @State private var expiresInDays = 7
    @State private var chosen: Set<String> = []
    @State private var created: URL?
    @State private var done = false
    @State private var standing = true

    private var isFriends: Bool { kind == .friends }

    private var payload: SharePayload? {
        try? sharing.previewPayload(sessions: allSessions, mode: model.mode, period: period, selection: selection,
                                    expiresInDays: isFriends ? nil : expiresInDays,
                                    recipientUids: isFriends ? Array(chosen) : nil, allowsMessage: true,
                                    events: model.events.all())
    }

    private var messageProblem: String? {
        guard let text = ShareMessage.normalized(selection.message) else { return nil }
        return ShareMessage.looksLikeLink(text) ? tr("リンクやURLは、一言に入れられません") : nil
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
        Text(title).font(.footnote.weight(.semibold)).foregroundStyle(Theme.accentText).textCase(nil)
    }

    private var whoSection: some View {
        Section {
            if recipients.isEmpty {
                Text(tr("まだフレンドがいません")).font(.footnote).foregroundStyle(.secondary)
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
                                .font(.title3).foregroundStyle(chosen.contains(friend.uid) ? Theme.accentText : .secondary)
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
                    .font(.footnote.weight(.medium)).foregroundStyle(Theme.accentText).textCase(nil)
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
                    Image(systemName: "text.quote").foregroundStyle(Theme.accentText).frame(width: 36, height: 36)
                }
                .accessibilityLabel(tr("定型文から選ぶ"))
            }
            if let problem = messageProblem { Text(problem).font(.caption).foregroundStyle(.red) }
            Toggle(tr("ニックネームを出す"), isOn: $selection.showName)
            if isFriends {
                Toggle(tr("アプリを開いたとき、最新にする"), isOn: $standing)
            } else {
                Picker(tr("リンクの期限"), selection: $expiresInDays) {
                    Text(tr("1日後")).tag(1); Text(tr("7日後")).tag(7); Text(tr("30日後")).tag(30)
                }
                .pickerStyle(.menu)
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
                Text(tr("項目を選ぶと、ここに表示されます")).font(.footnote).foregroundStyle(.secondary)
                    .listRowBackground(Theme.card)
            }
        } header: {
            HStack {
                header(tr("共有される内容"))
                Spacer()
                Text(selection.showName ? (sharing.profile?.displayName ?? "") : tr("匿名")).lineLimit(1).truncationMode(.tail).font(.caption).foregroundStyle(.secondary).textCase(nil)
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if let created {
            CardSection {
                HStack(spacing: 8) {
                    Label(tr("リンクを作りました"), systemImage: "checkmark.circle.fill").foregroundStyle(Theme.accentText)
                    Spacer(minLength: 0)
                    CopyIconButton(text: created.absoluteString)
                }
                HStack(spacing: 8) {
                    ShareLink(item: created) { Label(tr("送る"), systemImage: "square.and.arrow.up") }.buttonStyle(ChipButtonStyle())
                    Link(destination: created) { Label(tr("開く"), systemImage: "safari") }.buttonStyle(ChipButtonStyle())
                }
                QRSection(text: created.absoluteString)
            }
        } else if done {
            CardSection {
                Label(tr("共有しました"), systemImage: "checkmark.circle.fill").foregroundStyle(Theme.accentText)
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
/// QRコード：押すと作る（切り替えのトグルではなく、ボタン）。作っている間は、QRのアイコンが動いて、作成中だと分かるようにする。
struct QRSection: View {
    let text: String
    private enum Phase { case idle, making, shown }
    @State private var phase: Phase = .idle
    @State private var image: UIImage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 8) {
            switch phase {
            case .idle:
                Button { make() } label: {
                    Label(tr("QRコードを作る"), systemImage: "qrcode").foregroundStyle(Theme.accentText)
                }
                .buttonStyle(ChipButtonStyle())
            case .making:
                HStack(spacing: 8) {
                    Image(systemName: "qrcode")
                        .symbolEffect(.variableColor.iterative.reversing, isActive: !reduceMotion)
                    Text(tr("作成中…"))
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.accentText)
                .frame(maxWidth: .infinity, minHeight: 40)
                .accessibilityLabel(tr("QRコードを作成中"))
            case .shown:
                if let image {
                    Image(uiImage: image).interpolation(.none).resizable().scaledToFit().frame(width: 180, height: 180)
                        .accessibilityLabel(tr("QRコード"))
                        .transition(.opacity)
                }
                Button { withAnimation(.easeInOut(duration: 0.25)) { phase = .idle; image = nil } } label: {
                    Text(tr("閉じる")).font(.subheadline).foregroundStyle(Theme.accentText)
                        .frame(minHeight: 36).padding(.horizontal, 12)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.25), value: phase)
    }

    private func make() {
        phase = .making
        let value = text
        Task { @MainActor in
            // 作成の様子が伝わるよう、少しだけ間を置く
            async let made = Task.detached(priority: .userInitiated) { QRImage.make(value) }.value
            try? await Task.sleep(for: .milliseconds(900))
            image = await made
            phase = image == nil ? .idle : .shown
        }
    }
}

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
                    Label(tr("新しいリンクを作る"), systemImage: "plus.circle").foregroundStyle(Theme.accentText)
                }.frame(minHeight: 44)
            }
            if sharing.shares.allSatisfy({ $0.status == "revoked" }) {
                CardSection { Text(tr("共有中のリンクはありません")).foregroundStyle(.secondary) }
            }
            ForEach(sharing.shares.filter { $0.status != "revoked" }) { item in
                CardSection {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(periodLabel(item.period)).font(.headline)
                        Text(tr("期限：{0}", dateText(item.expiresAt))).font(.footnote).foregroundStyle(.secondary)
                            .lineLimit(1).minimumScaleFactor(0.8)
                        Spacer(minLength: 4)
                        Text(statusText(item.status)).font(.footnote.weight(.medium))
                            .foregroundStyle(item.status == "active" ? Theme.accentText : .secondary)
                    }
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
                    Label(tr("新しいリンクを作りました"), systemImage: "checkmark.circle.fill").foregroundStyle(Theme.accentText)
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
    return DateText.dayTime(date)
}

/// アイコン。自分のもの（`isOwn`）は、設定に従う：選んだアイコン（山・海・魚など）、または何も描かない無印。色はテーマの4色から選んだもの。
/// 相手のものは、頭文字だけ（相手のアイコン・色は、受け取らない）。
struct AccountAvatar: View {
    let name: String
    var size: CGFloat = 32
    var isOwn = false
    private var settings: AvatarSettings { .shared }

    static var themeChoices: [Color] { ThemeColor.allCases.map(\.swatchColor) }

    var body: some View {
        Circle()
            .fill(isOwn ? settings.fill(choices: Self.themeChoices, themeColor: Theme.accent) : Theme.accent)
            .frame(width: size, height: size)
            .overlay {
                if isOwn {
                    // 自分のアイコン：選んだ絵。初期は、何も描かない無印
                    if let index = settings.symbolIndex, AvatarSettings.symbols.indices.contains(index) {
                        Image(systemName: AvatarSettings.symbols[index].name)
                            .font(.system(size: size * 0.48, weight: .medium)).foregroundStyle(.white)
                    }
                } else {
                    Text(String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
                        .font(.system(size: size * 0.45, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
            .accessibilityHidden(true)
    }
}

/// 入力中のニックネーム（参照型。入力のたびに、親の画面を組み直さないため）。
final class NameDraft { var text = "" }

/// ニックネームの入力欄。入力の状態は、この欄の中だけで持つ（フォーカスしてからキーボードが出るまでを速くする）。
struct NicknameField: View {
    let initial: String
    let placeholder: String
    let onChange: (String) -> Void
    @State private var text = ""

    var body: some View {
        TextField(placeholder, text: $text)
            .submitLabel(.done)
            .onAppear { text = initial }
            .onChange(of: text) { _, new in
                if new.count > 20 { text = String(new.prefix(20)) } else { onChange(new) }
            }
    }
}

/// プロフィール：表示名（上）→ アイコン（頭文字・山や海などの10個）→ 色（テーマの4色）→ 保存（いちばん下）。
@MainActor
struct ProfileView: View {
    @Environment(SharingModel.self) private var sharing
    /// 入力中の文字。1文字ごとに画面全体を組み直さないよう、参照で持つ（入力欄の中だけが更新される）。
    @State private var draft = NameDraft()
    @State private var saveTask: Task<Void, Never>?
    private var avatar: AvatarSettings { .shared }

    private var displayName: String { sharing.profile?.displayName ?? "" }
    private var trimmed: String { String(draft.text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(20)) }

    /// 入力が止まって少したったら、自動で保存する（保存ボタンは置かない）。空・変わっていないときは保存しない。
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            await commit()
        }
    }

    @MainActor
    private func commit() async {
        let text = trimmed
        guard !text.isEmpty, text != displayName else { return }
        _ = await sharing.saveDisplayName(text)
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    AccountAvatar(name: displayName, size: 84, isOwn: true)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }

            Section {
                NicknameField(initial: displayName, placeholder: tr("例：ふとさん")) { text in
                    draft.text = text
                    scheduleSave()
                }
            } header: {
                formHeader(tr("ニックネーム"))
            }
            .listRowBackground(Theme.card)

            Section { iconGrid } header: { formHeader(tr("アイコン")) }
                .listRowBackground(Theme.card)

            Section { colorPicker } header: { formHeader(tr("アイコンの色")) }
                .listRowBackground(Theme.card)

        }
        .compactForm()
        .navigationTitle(tr("プロフィール"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { draft.text = displayName }
        .onDisappear {
            // 画面を閉じるときにも、入力中の分を保存する
            saveTask?.cancel()
            let text = trimmed
            if !text.isEmpty, text != displayName { Task { _ = await sharing.saveDisplayName(text) } }
        }
    }

    private func formHeader(_ title: String) -> some View {
        Text(title).font(.footnote.weight(.semibold)).foregroundStyle(Theme.accentText).textCase(nil)
    }

    // MARK: アイコン

    private var iconGrid: some View {
        let fill = avatar.fill(choices: AccountAvatar.themeChoices, themeColor: Theme.accent)
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 10)], spacing: 10) {
            iconCell(selected: avatar.symbolIndex == nil, label: tr("無印")) { avatar.selectPlain() } content: {
                Circle().fill(fill).frame(width: 40, height: 40)
            }
            ForEach(Array(AvatarSettings.symbols.enumerated()), id: \.offset) { index, symbol in
                iconCell(selected: avatar.symbolIndex == index, label: symbol.label) { avatar.selectSymbol(index) } content: {
                    Circle().fill(fill).frame(width: 40, height: 40)
                        .overlay(Image(systemName: symbol.name).font(.system(size: 19, weight: .medium)).foregroundStyle(.white))
                }
            }
        }
    }

    private func iconCell<Content: View>(selected: Bool, label: String, action: @escaping () -> Void, @ViewBuilder content: () -> Content) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) { action() }
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

    // MARK: 色（テーマの4色）

    private var colorPicker: some View {
        HStack(spacing: 16) {
            ForEach(Array(ThemeColor.allCases.enumerated()), id: \.offset) { index, option in
                swatch(index: index, option: option)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    /// 色を選んでいなければ、いまのテーマの色に印が付く。
    private func swatch(index: Int, option: ThemeColor) -> some View {
        let selected = avatar.colorIndex == index || (avatar.colorIndex == nil && ThemeStore.shared.color == option)
        return Button {
            withAnimation(.easeInOut(duration: 0.25)) { avatar.colorIndex = index }
        } label: {
            Circle().fill(option.swatchColor).frame(width: 36, height: 36)
                .overlay(Image(systemName: "checkmark").font(.footnote.bold()).foregroundStyle(.white).opacity(selected ? 1 : 0))
                .overlay(Circle().stroke(.primary.opacity(selected ? 0.6 : 0), lineWidth: 2).padding(-4))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.name)
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
