import SwiftUI

/// フレンド：招待・承認待ち・一覧・限定共有。承認されるまで、統計は見えない。
@MainActor
struct FriendsView: View {
    let model: AppModel
    @Environment(SharingModel.self) private var sharing
    @State private var code = ""
    @State private var removing: FriendsResponse.Friend?
    @State private var blocking: FriendsResponse.Friend?

    var body: some View {
        Form {
            inviteSection
            codeSection
            if !sharing.friends.incoming.isEmpty { incomingSection }
            if !sharing.friends.outgoing.isEmpty { outgoingSection }
            if !sharing.friends.friends.isEmpty {
                CardSection {
                    NavigationLink { CreateShareView(model: model, kind: .friends, recipients: sharing.friends.friends) } label: {
                        Label(tr("フレンドに記録を共有"), systemImage: "paperplane").foregroundStyle(Theme.accentText)
                    }
                    .frame(minHeight: 44)
                }
            }
            receivedSection
            // フレンド一覧は、いちばん下に置く
            friendsSection
            if let message = sharing.message { CardSection { Text(message).font(.footnote).foregroundStyle(.secondary) } }
        }
        .compactForm()
        .navigationTitle(tr("フレンド"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await sharing.loadFriends(); await sharing.loadFriendShares() }
        .confirmationDialog(tr("フレンドをやめますか？ 共有済みの記録も、見えなくなります"), isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button(tr("やめる"), role: .destructive) { if let f = removing { Task { await sharing.removeFriend(f) } } }
            Button(tr("キャンセル"), role: .cancel) {}
        }
        .confirmationDialog(tr("ブロックしますか？ 相手からの申請や、記録は届かなくなります"), isPresented: Binding(get: { blocking != nil }, set: { if !$0 { blocking = nil } }), titleVisibility: .visible) {
            Button(tr("ブロック"), role: .destructive) { if let f = blocking { Task { await sharing.block(uid: f.uid) } } }
            Button(tr("キャンセル"), role: .cancel) {}
        }
    }


    private func formatted(_ code: String) -> String {
        stride(from: 0, to: code.count, by: 4).map { start in
            String(code.dropFirst(start).prefix(4))
        }.joined(separator: "-")
    }

    private var inviteSection: some View {
        CardSection {
            if let invitation = sharing.invitation, let url = URL(string: invitation.url) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("招待コード")).font(.caption).foregroundStyle(.secondary)
                        Text(formatted(invitation.code)).font(.title3.monospaced().weight(.medium)).textSelection(.enabled)
                    }
                    Spacer(minLength: 0)
                    CopyIconButton(text: invitation.code)
                }
                Text(tr("期限：{0}", dateText(invitation.expiresAt))).font(.footnote).foregroundStyle(.secondary)
                // 送る・コピーは、1列に横並び
                HStack(spacing: 8) {
                    ShareLink(item: url, message: Text(tr("ふとのフレンド招待です　招待コード：{0}", formatted(invitation.code)))) {
                        Label(tr("送る"), systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(ChipButtonStyle())
                    CopyLabelButton(text: invitation.url)
                }
                QRSection(text: invitation.url)
                Button(role: .destructive) { Task { await sharing.cancelInvitation() } } label: { Label(tr("招待を取り消す"), systemImage: "xmark.circle") }
                    .buttonStyle(ChipButtonStyle())
            } else {
                Button { Task { await sharing.createInvitation() } } label: { Label(tr("フレンドを招待"), systemImage: "person.badge.plus") }
                    .buttonStyle(FutoButtonStyle()).disabled(sharing.isWorking)
            }
        }
    }

    private var codeSection: some View {
        CardSection {
            HStack(spacing: 8) {
                TextField(tr("招待コードを入力"), text: $code)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                // 貼り付けは、システムのボタンで（クリップボードの許可の確認が出ない）
                PasteButton(payloadType: String.self) { strings in
                    if let first = strings.first { code = String(first.prefix(40)) }
                }
                .labelStyle(.iconOnly)
                .buttonBorderShape(.circle)
                .accessibilityLabel(tr("貼り付け"))
                // コードが入ってから、右に「受け入れる」を出す
                if let normalized = InviteLink.normalizedCode(code) {
                    Button(tr("受け入れる")) {
                        Task { if await sharing.sendFriendRequest(code: normalized) { code = "" } }
                    }
                    .buttonStyle(ChipButtonStyle())
                    .fixedSize()
                    .disabled(sharing.isWorking)
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: InviteLink.normalizedCode(code) != nil)
        }
    }

    private var incomingSection: some View {
        CardSection {
            Text(tr("承認待ち")).font(.footnote).foregroundStyle(.secondary)
            ForEach(sharing.friends.incoming) { request in
                VStack(alignment: .leading, spacing: 8) {
                    Text(request.displayName).lineLimit(1).truncationMode(.tail)
                    HStack(spacing: 8) {
                        Button { Task { await sharing.respond(to: request, accept: true) } } label: { Label(tr("承認"), systemImage: "checkmark") }
                        Button(role: .destructive) { Task { await sharing.respond(to: request, accept: false) } } label: { Label(tr("見送る"), systemImage: "xmark") }
                    }
                    .buttonStyle(ChipButtonStyle())
                }
            }
        }
    }

    private var outgoingSection: some View {
        CardSection {
            Text(tr("返事待ち")).font(.footnote).foregroundStyle(.secondary)
            ForEach(sharing.friends.outgoing) { request in
                HStack {
                    Text(request.displayName).lineLimit(1).truncationMode(.tail)
                    Spacer()
                    Button(tr("取り消す"), role: .destructive) { Task { await sharing.cancelRequest(request) } }
                        .buttonStyle(ChipButtonStyle()).fixedSize()
                }
            }
        }
    }

    private var friendsSection: some View {
        CardSection {
            Text(tr("フレンド一覧")).font(.footnote).foregroundStyle(.secondary)
            if sharing.friends.friends.isEmpty { Text(tr("まだフレンドはいません")).foregroundStyle(.secondary) }
            ForEach(sharing.friends.friends) { friend in
                HStack(spacing: 12) {
                    AccountAvatar(name: friend.displayName, size: 32, spec: friend.avatar)
                    Text(friend.displayName).oneLine()
                    Spacer(minLength: 0)
                    Menu {
                        Button(tr("フレンドをやめる"), role: .destructive) { removing = friend }
                        Button(tr("ブロック"), role: .destructive) { blocking = friend }
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(Theme.accentText)
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .accessibilityLabel(tr("操作"))
                }
                .frame(minHeight: 44)
            }
        }
    }

    @ViewBuilder
    private var receivedSection: some View {
        if !sharing.receivedShares.isEmpty || sharing.sentShares.contains(where: { $0.status != "revoked" }) {
            if !sharing.receivedShares.isEmpty {
                // 送ってきた人ごとにまとめる。人を選んでから、いつの記録を見るか選ぶ
                CardSection {
                    Text(tr("届いた記録")).font(.footnote).foregroundStyle(.secondary)
                    ForEach(ReceivedGrouping.group(sharing.receivedShares)) { group in
                        NavigationLink { FriendRecordsListView(groupID: group.id) } label: {
                            HStack(spacing: 12) {
                                AccountAvatar(name: group.name ?? "?", size: 32, spec: group.avatar)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(group.name ?? tr("匿名")).oneLine()
                                    Text(tr("{0}件", "\(group.items.count)")).font(.footnote).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                if group.items.contains(where: { sharing.isUnseen($0) }) { NewBadge() }
                            }
                            .frame(minHeight: 44)
                        }
                    }
                }
            }
            if sharing.sentShares.contains(where: { $0.status != "revoked" }) {
                CardSection {
                    Text(tr("共有した記録")).font(.footnote).foregroundStyle(.secondary)
                    ForEach(sharing.sentShares.filter { $0.status != "revoked" }) { item in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(periodLabel(item.period) + (sharing.isStanding(item.id) != nil ? " · " + tr("継続中") : ""))
                                Text(tr("{0}人・期限 {1}", "\(item.recipientCount)", dateText(item.expiresAt))).font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if item.status == "active" {
                                if sharing.isStanding(item.id) != nil {
                                    Button(tr("更新")) { Task { await sharing.refreshStanding(sessions: model.sessions.all(), events: model.events.all(), mode: model.mode, force: true) } }
                                        .buttonStyle(ChipButtonStyle()).fixedSize().disabled(sharing.isWorking)
                                }
                                Button(tr("やめる"), role: .destructive) { Task { await sharing.revokeFriendShare(id: item.id) } }
                                    .buttonStyle(ChipButtonStyle()).fixedSize()
                            }
                        }
                    }
                }
            }
        }
    }
}

/// 1人ぶんの、届いた記録の一覧。いつの記録を見るか選ぶ。
@MainActor
struct FriendRecordsListView: View {
    let groupID: String
    @Environment(SharingModel.self) private var sharing

    private var group: ReceivedGroup? { ReceivedGrouping.group(sharing.receivedShares).first { $0.id == groupID } }

    var body: some View {
        Form {
            if let group {
                CardSection {
                    ForEach(group.items) { item in
                        NavigationLink { FriendShareDetailView(id: item.id) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(periodLabel(item.period))
                                    Text(tr("更新 {0}", dateText(item.updatedAt ?? item.createdAt))).font(.footnote).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                if sharing.isUnseen(item) { NewBadge() }
                            }
                            .frame(minHeight: 44)
                        }
                    }
                }
            } else {
                CardSection { Text(tr("この記録は、もう見られません")).foregroundStyle(.secondary) }
            }
        }
        .compactForm()
        .navigationTitle(group?.name ?? tr("匿名"))
        .navigationBarTitleDisplayMode(.inline)
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
                    HStack(spacing: 12) {
                        AccountAvatar(name: detail.ownerName ?? "?", size: 40, spec: detail.ownerAvatar)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(detail.ownerName ?? tr("匿名")).font(.headline)
                            Text(periodLabel(s.period) + (s.isPartial ? " · " + tr("途中までの集計") : "")).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    Text(tr("更新 {0}", dateText(detail.updatedAt ?? detail.createdAt))).font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    StatsChartsView(stats: ChartStats(snapshot: s))
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        .listRowBackground(Color.clear)
                }
            } else if failed {
                CardSection { Text(sharing.message ?? tr("見られませんでした")).foregroundStyle(.secondary) }
            } else {
                CardSection { ProgressView() }
            }
        }
        .compactForm()
        .navigationTitle(tr("届いた記録"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            detail = await sharing.friendShareDetail(id: id)
            failed = detail == nil
            // 開いたので、この版は「見た」にする（バッジが消える）
            if let detail { sharing.markSeen(id: id, version: detail.updatedAt ?? detail.createdAt) }
        }
    }
}

/// 招待リンクから開いたときの確認。「受け入れる」を押してから送る（開いただけでは送らない）。
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
                        Text(sharing.isConfigured ? tr("招待を受け入れるには、ログインが必要です") : tr("共有の設定がまだ終わっていません"))
                        if sharing.isConfigured {
                            SignInButtons()
                        }
                    }
                } else if sent {
                    CardSection { Text(tr("受け入れました　相手が承認すると、フレンドになります")) }
                } else if let inviter {
                    CardSection {
                        Text(tr("{0} さんからの招待です", inviter.inviterName))
                        Button(tr("招待を受け入れる")) { Task { sent = await sharing.sendFriendRequest(token: token) } }
                            .buttonStyle(FutoButtonStyle()).disabled(sharing.isWorking)
                    }
                } else if loaded {
                    CardSection { Text(sharing.message ?? tr("この招待は、使えません")) }
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
