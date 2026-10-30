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
            CardSection {
                Button { Task { await sharing.signIn() } } label: {
                    Label(tr("Googleでログイン"), systemImage: "person.crop.circle.badge.checkmark")
                }
                .frame(minHeight: 44)
                    .disabled(sharing.isWorking)
            }
        }
    }

    private var needsReauth: some View {
        CardSection {
            Text(tr("ログインの確認が必要です。"))
            Button(tr("もう一度ログイン")) { Task { await sharing.signIn() } }.frame(minHeight: 44)
            Button(tr("ログアウト"), role: .destructive) { sharing.signOut() }.frame(minHeight: 44)
        }
    }

    @ViewBuilder
    private var signedIn: some View {
        CardSection {
            HStack(spacing: 14) {
                AccountAvatar(name: sharing.profile?.displayName ?? "", size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(sharing.profile?.displayName ?? "…").font(.headline).oneLine()
                    Text(tr("Googleでログイン中")).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
            Button { nameDraft = sharing.profile?.displayName ?? ""; editingName = true } label: {
                Label(tr("表示名を変える"), systemImage: "pencil").tint(Theme.accent)
            }
            .frame(minHeight: 44)
        }
        CardSection {
            NavigationLink { CreateShareView(model: model, kind: .web) } label: {
                Label(tr("統計をリンクで共有"), systemImage: "link").foregroundStyle(Theme.accent)
            }.frame(minHeight: 44)
            NavigationLink { SharedLinksView() } label: {
                Label(tr("共有中のリンク"), systemImage: "list.bullet").foregroundStyle(Theme.accent)
            }.frame(minHeight: 44)
        }
        CardSection {
            NavigationLink { FriendsView(model: model) } label: {
                Label(tr("フレンド"), systemImage: "person.2").foregroundStyle(Theme.accent)
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

    private var payload: SharePayload? {
        try? sharing.previewPayload(sessions: allSessions, mode: model.mode, period: period, selection: selection,
                                    expiresInDays: kind == .web ? expiresInDays : nil,
                                    recipientUids: kind == .friends ? Array(chosen) : nil)
    }

    private var canCreate: Bool {
        selection.hasStats && !sharing.isWorking && (kind == .web || !chosen.isEmpty)
    }

    var body: some View {
        Form {
            CardSection {
                Text(tr("選んだ項目だけが、共有されます。記録の一覧や、アプリ名は含まれません。"))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            CardSection {
                Picker(tr("期間"), selection: $period) {
                    ForEach(SharePeriod.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            CardSection {
                Toggle(tr("回数（使いたい・やめておく・中断）"), isOn: $selection.counts)
                Toggle(tr("使いたかった目的の内訳"), isOn: $selection.purposes)
                Toggle(tr("使ったあとの気持ち"), isOn: $selection.feelings)
            }
            CardSection {
                Toggle(tr("表示名を出す"), isOn: $selection.showName)
                Picker(tr("ひとこと"), selection: Binding(get: { selection.phrase?.rawValue ?? "" }, set: { selection.phrase = SharePhrase(rawValue: $0) })) {
                    Text(tr("なし")).tag("")
                    ForEach(SharePhrase.allCases) { Text($0.text).tag($0.rawValue) }
                }
            }
            if kind == .web {
                CardSection {
                    Picker(tr("有効期間"), selection: $expiresInDays) {
                        Text(tr("1日")).tag(1); Text(tr("7日")).tag(7); Text(tr("30日")).tag(30)
                    }
                }
            } else {
                CardSection {
                    ForEach(recipients) { friend in
                        Toggle(friend.displayName, isOn: Binding(get: { chosen.contains(friend.uid) }, set: { on in
                            if on { chosen.insert(friend.uid) } else { chosen.remove(friend.uid) }
                        }))
                    }
                }
            }
            preview
            if let created {
                CardSection {
                    Text(created.absoluteString).font(.footnote).textSelection(.enabled)
                    ShareLink(item: created) { Text(tr("リンクを送る")) }.frame(minHeight: 44)
                    QRImage(text: created.absoluteString).frame(maxWidth: .infinity).padding(.vertical, 6)
                    Text(tr("リンクを知っている人は、期限まで見られます。転送されることもあります。やめたいときは「共有中のリンク」から止めてください。"))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } else if done {
                CardSection { Text(tr("共有しました。")) }
            } else {
                CardSection {
                    Button(kind == .web ? tr("リンクを作る") : tr("フレンドに共有")) { Task { await create() } }
                        .frame(minHeight: 44)
                        .disabled(!canCreate)
                    if let message = sharing.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                }
            }
        }
        .compactForm()
        .navigationTitle(kind == .web ? tr("リンクで共有") : tr("フレンドに共有"))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// 送る内容そのままを、先に見せる。
    private var preview: some View {
        CardSection {
            Text(tr("共有される内容")).font(.footnote).foregroundStyle(.secondary)
            if let payload {
                if let c = payload.counts {
                    LabeledContent(tr("使いたい / やめておく / 中断"), value: "\(c.wantsToUse) / \(c.deferred) / \(c.interrupted)")
                }
                if let p = payload.purposes {
                    LabeledContent(tr("目的"), value: tr("連絡 {0}・調べもの {1}・気分転換 {2}・理由なし {3}・未回答 {4}", "\(p.contact)", "\(p.research)", "\(p.break)", "\(p.noReason)", "\(p.unanswered)"))
                }
                if let f = payload.feelings {
                    let answered = f.satisfied + f.neutral + f.wishedLess
                    LabeledContent(tr("気持ち（回答 {0} 件）", "\(answered)"), value: "\(f.satisfied) / \(f.neutral) / \(f.wishedLess)")
                }
                if payload.isPartial { Text(tr("今週はまだ途中です。")).font(.footnote).foregroundStyle(.secondary) }
                Text(selection.showName ? tr("表示名：{0}", sharing.profile?.displayName ?? "") : tr("表示名：匿名"))
                    .font(.footnote)
            } else {
                Text(tr("項目を選ぶと、ここに表示されます。")).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func create() async {
        guard let payload else { return }
        switch kind {
        case .web: created = await sharing.createWebShare(payload)
        case .friends: done = await sharing.createFriendShare(payload)
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
    @Environment(SharingModel.self) private var sharing
    @State private var confirmRevoke: ShareListItem?
    @State private var rotated: URL?

    var body: some View {
        Form {
            if sharing.shares.isEmpty {
                CardSection { Text(tr("共有中のリンクはありません。")).foregroundStyle(.secondary) }
            }
            ForEach(sharing.shares) { item in
                CardSection {
                    LabeledContent(item.period == "thisWeek" ? tr("今週") : tr("先週"), value: statusText(item.status))
                    Text(tr("期限：{0}", dateText(item.expiresAt))).font(.footnote).foregroundStyle(.secondary)
                    if item.status == "active" {
                        if let url = sharing.localURL(for: item) {
                            ShareLink(item: url) { Text(tr("リンクを送る")) }.frame(minHeight: 44)
                        }
                        Button(tr("リンクを作り直す")) { Task { rotated = await sharing.rotateShare(item) } }.frame(minHeight: 44)
                        Button(tr("共有をやめる"), role: .destructive) { confirmRevoke = item }.frame(minHeight: 44)
                    }
                }
            }
            if let rotated {
                CardSection {
                    Text(tr("新しいリンクです。古いリンクは、使えなくなりました。")).font(.footnote)
                    ShareLink(item: rotated) { Text(tr("新しいリンクを送る")) }.frame(minHeight: 44)
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

/// ログイン中のしるし。名前の頭文字を、テーマ色の丸に載せる（Googleの写真は取得しない）。
struct AccountAvatar: View {
    let name: String
    var size: CGFloat = 32

    var body: some View {
        Circle()
            .fill(Theme.accent)
            .frame(width: size, height: size)
            .overlay(
                Text(String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
                    .font(.system(size: size * 0.45, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            )
            .accessibilityHidden(true)
    }
}
