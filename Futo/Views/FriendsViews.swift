import SwiftUI

/// フレンド：招待・承認待ち・一覧・限定共有。承認されるまで、統計は見えない。
@MainActor
struct FriendsView: View {
    let model: AppModel
    @Environment(SharingModel.self) private var sharing
    @State private var code = ""
    @State private var removing: FriendsResponse.Friend?
    @State private var blocking: FriendsResponse.Friend?
    @State private var reporting: FriendsResponse.Friend?

    var body: some View {
        Form {
            inviteSection
            codeSection
            if !sharing.friends.incoming.isEmpty { incomingSection }
            if !sharing.friends.outgoing.isEmpty { outgoingSection }
            friendsSection
            if !sharing.friends.friends.isEmpty {
                CardSection {
                    NavigationLink(tr("フレンドに共有")) { CreateShareView(model: model, kind: .friends, recipients: sharing.friends.friends) }.frame(minHeight: 44)
                }
            }
            receivedSection
            if let message = sharing.message { CardSection { Text(message).font(.footnote).foregroundStyle(.secondary) } }
        }
        .compactForm()
        .navigationTitle(tr("フレンド"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await sharing.loadFriends(); await sharing.loadFriendShares() }
        .confirmationDialog(tr("フレンドをやめますか？ 共有済みの統計も、見えなくなります。"), isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button(tr("やめる"), role: .destructive) { if let f = removing { Task { await sharing.removeFriend(f) } } }
            Button(tr("キャンセル"), role: .cancel) {}
        }
        .confirmationDialog(tr("ブロックしますか？ 相手からの申請や、統計は届かなくなります。"), isPresented: Binding(get: { blocking != nil }, set: { if !$0 { blocking = nil } }), titleVisibility: .visible) {
            Button(tr("ブロック"), role: .destructive) { if let f = blocking { Task { await sharing.block(uid: f.uid) } } }
            Button(tr("キャンセル"), role: .cancel) {}
        }
        .confirmationDialog(tr("報告の理由"), isPresented: Binding(get: { reporting != nil }, set: { if !$0 { reporting = nil } }), titleVisibility: .visible) {
            Button(tr("不適切な内容")) { send(report: "inappropriate") }
            Button(tr("嫌がらせ")) { send(report: "harassment") }
            Button(tr("迷惑行為")) { send(report: "spam") }
            Button(tr("その他")) { send(report: "other") }
            Button(tr("キャンセル"), role: .cancel) {}
        }
    }

    private func send(report reason: String) {
        guard let f = reporting else { return }
        Task { _ = await sharing.report(targetType: "user", targetId: f.uid, reason: reason) }
    }

    private var inviteSection: some View {
        CardSection {
            if let invitation = sharing.invitation, let url = URL(string: invitation.url) {
                Text(tr("招待コード：{0}", invitation.code)).font(.body.monospaced()).textSelection(.enabled)
                Text(tr("期限：{0}", dateText(invitation.expiresAt))).font(.footnote).foregroundStyle(.secondary)
                ShareLink(item: url) { Text(tr("招待リンクを送る")) }.frame(minHeight: 44)
                QRImage(text: invitation.url).frame(maxWidth: .infinity).padding(.vertical, 6)
                Text(tr("招待リンクは、統計の共有リンクとは別です。相手が申請し、あなたが承認するまで、統計は見えません。"))
                    .font(.footnote).foregroundStyle(.secondary)
                Button(tr("招待を取り消す"), role: .destructive) { Task { await sharing.cancelInvitation() } }.frame(minHeight: 44)
            } else {
                Button(tr("フレンドを招待")) { Task { await sharing.createInvitation() } }
                    .frame(minHeight: 44).disabled(sharing.isWorking)
            }
        }
    }

    private var codeSection: some View {
        CardSection {
            TextField(tr("招待コードを入力"), text: $code)
                .textInputAutocapitalization(.characters).autocorrectionDisabled()
            Button(tr("申請する")) {
                if let normalized = InviteLink.normalizedCode(code) {
                    Task { if await sharing.sendFriendRequest(code: normalized) { code = "" } }
                }
            }
            .frame(minHeight: 44)
            .disabled(InviteLink.normalizedCode(code) == nil || sharing.isWorking)
        }
    }

    private var incomingSection: some View {
        CardSection {
            Text(tr("承認待ちの申請")).font(.footnote).foregroundStyle(.secondary)
            ForEach(sharing.friends.incoming) { request in
                VStack(alignment: .leading, spacing: 8) {
                    Text(request.displayName)
                    HStack {
                        Button(tr("承認")) { Task { await sharing.respond(to: request, accept: true) } }
                        Spacer()
                        Button(tr("見送る"), role: .destructive) { Task { await sharing.respond(to: request, accept: false) } }
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    private var outgoingSection: some View {
        CardSection {
            Text(tr("送った申請")).font(.footnote).foregroundStyle(.secondary)
            ForEach(sharing.friends.outgoing) { request in
                HStack {
                    Text(request.displayName)
                    Spacer()
                    Button(tr("取り消す"), role: .destructive) { Task { await sharing.cancelRequest(request) } }.buttonStyle(.borderless)
                }
            }
        }
    }

    private var friendsSection: some View {
        CardSection {
            if sharing.friends.friends.isEmpty { Text(tr("まだフレンドはいません。")).foregroundStyle(.secondary) }
            ForEach(sharing.friends.friends) { friend in
                Text(friend.displayName)
                    .frame(minHeight: 44, alignment: .leading)
                    .contextMenu {
                        Button(tr("フレンドをやめる"), role: .destructive) { removing = friend }
                        Button(tr("ブロック"), role: .destructive) { blocking = friend }
                        Button(tr("報告")) { reporting = friend }
                    }
            }
        }
    }

    @ViewBuilder
    private var receivedSection: some View {
        if !sharing.receivedShares.isEmpty || !sharing.sentShares.isEmpty {
            CardSection {
                Text(tr("届いた統計")).font(.footnote).foregroundStyle(.secondary)
                ForEach(sharing.receivedShares) { item in
                    NavigationLink { FriendShareDetailView(id: item.id) } label: {
                        VStack(alignment: .leading) {
                            Text(item.ownerName ?? tr("匿名"))
                            Text(item.period == "thisWeek" ? tr("今週") : tr("先週")).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if !sharing.sentShares.isEmpty {
                CardSection {
                    Text(tr("共有したもの")).font(.footnote).foregroundStyle(.secondary)
                    ForEach(sharing.sentShares) { item in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(item.period == "thisWeek" ? tr("今週") : tr("先週"))
                                Text(tr("{0}人・期限 {1}", "\(item.recipientCount)", dateText(item.expiresAt))).font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if item.status == "active" {
                                Button(tr("やめる"), role: .destructive) { Task { await sharing.revokeFriendShare(id: item.id) } }.buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// フレンドから届いた統計。サーバーが、権限・期限・ブロックを確認してから返す。
@MainActor
struct FriendShareDetailView: View {
    let id: String
    @Environment(SharingModel.self) private var sharing
    @State private var detail: FriendShareDetail?
    @State private var failed = false

    var body: some View {
        Form {
            if let detail {
                let s = detail.stats
                CardSection {
                    LabeledContent(tr("送り主"), value: detail.ownerName ?? tr("匿名"))
                    LabeledContent(tr("期間"), value: s.period == "thisWeek" ? tr("今週") : tr("先週"))
                    if s.isPartial { Text(tr("途中までの集計です。")).font(.footnote).foregroundStyle(.secondary) }
                }
                if let c = s.counts {
                    CardSection { LabeledContent(tr("使いたい / やめておく / 中断"), value: "\(c.wantsToUse) / \(c.deferred) / \(c.interrupted)") }
                }
                if let p = s.purposes {
                    CardSection {
                        LabeledContent(tr("連絡"), value: "\(p.contact)"); LabeledContent(tr("調べもの"), value: "\(p.research)")
                        LabeledContent(tr("気分転換"), value: "\(p.break)"); LabeledContent(tr("理由なし"), value: "\(p.noReason)")
                        LabeledContent(tr("未回答"), value: "\(p.unanswered)")
                    }
                }
                if let f = s.feelings {
                    CardSection { LabeledContent(tr("気持ち（回答 {0} 件）", "\(f.answered)"), value: "\(f.satisfied) / \(f.neutral) / \(f.wishedLess)") }
                }
                if let phrase = s.phrase { CardSection { Text(phrase) } }
            } else if failed {
                CardSection { Text(sharing.message ?? tr("見られませんでした。")).foregroundStyle(.secondary) }
            } else {
                CardSection { ProgressView() }
            }
        }
        .compactForm()
        .navigationTitle(tr("届いた統計"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            detail = await sharing.friendShareDetail(id: id)
            failed = detail == nil
        }
    }
}

/// 招待リンクから開いたときの確認。申請は、確認してから送る（開いただけでは送らない）。
@MainActor
struct InviteLandingView: View {
    let token: String
    @Environment(SharingModel.self) private var sharing
    @Environment(\.dismiss) private var dismiss
    @State private var inviter: PublicInvitationResponse?
    @State private var loaded = false
    @State private var sent = false

    var body: some View {
        NavigationStack {
            Form {
                if !sharing.isConfigured || !sharing.isSignedIn {
                    CardSection {
                        Text(sharing.isConfigured ? tr("フレンドの申請には、ログインが必要です。") : tr("共有の設定がまだ終わっていません。"))
                        if sharing.isConfigured {
                            Button { Task { await sharing.signIn() } } label: { Label(tr("Googleでログイン"), systemImage: "person.crop.circle.badge.checkmark") }.frame(minHeight: 44)
                        }
                    }
                } else if sent {
                    CardSection { Text(tr("申請しました。承認されると、フレンドになります。")) }
                } else if let inviter {
                    CardSection {
                        Text(tr("{0} さんからの招待です。", inviter.inviterName))
                        Text(tr("申請して、相手が承認するまで、統計は見えません。")).font(.footnote).foregroundStyle(.secondary)
                        Button(tr("フレンドに申請する")) { Task { sent = await sharing.sendFriendRequest(token: token) } }
                            .frame(minHeight: 44).disabled(sharing.isWorking)
                    }
                } else if loaded {
                    CardSection { Text(sharing.message ?? tr("この招待は、使えません。")) }
                } else {
                    CardSection { ProgressView() }
                }
                if let message = sharing.message, inviter != nil { CardSection { Text(message).font(.footnote) } }
            }
            .compactForm()
            .navigationTitle(tr("フレンドの招待"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(tr("閉じる")) { dismiss() } } }
            .task {
                if sharing.isConfigured { inviter = await sharing.previewInvitation(token: token) }
                loaded = true
            }
        }
    }
}
