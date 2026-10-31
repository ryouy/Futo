import SwiftUI

/// フレンド：招待・承認待ち・一覧・限定共有。承認されるまで、統計は見えない。
@MainActor
struct FriendsView: View {
    let model: AppModel
    @Environment(SharingModel.self) private var sharing
    @State private var code = ""
    @State private var deleting: FriendsResponse.Friend?
    @State private var revoking: SentFriendShare?
    @State private var previewing: SentFriendShare?
    @State private var page: Page = .friends

    /// 下のページ：左右にスライドして切り替える。多くなっても、それぞれのページの中で、スクロールできる。
    enum Page: Int, CaseIterable {
        case friends, received, sent

        var title: String {
            switch self {
            case .friends: return tr("フレンド")
            case .received: return tr("届いた記録")
            case .sent: return tr("共有した記録")
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            FutoTabPicker(items: Page.allCases, selection: $page, title: { $0.title },
                          badge: { $0 == .received && sharing.hasUnseenRecords })
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            TabView(selection: $page) {
                friendsPage.tag(Page.friends)
                receivedPage.tag(Page.received)
                sentPage.tag(Page.sent)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(tr("フレンド"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // 招待リンクから来たときは、コードを、入力欄に入れる
            if let incoming = sharing.pendingFriendCode {
                code = incoming
                page = .friends
                sharing.pendingFriendCode = nil
            }
            await sharing.loadFriends(); await sharing.loadFriendShares(); await sharing.loadBlocked()
        }
        .sheet(item: $previewing) { item in
            NavigationStack {
                FriendShareDetailView(id: item.id)
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(tr("閉じる")) { previewing = nil } } }
            }
            .environment(sharing)
            .presentationBackground(Theme.background)
        }
        .confirmationDialog(tr("この共有を削除しますか？\nフレンドは、見られなくなります"), isPresented: Binding(get: { revoking != nil }, set: { if !$0 { revoking = nil } }), titleVisibility: .visible) {
            Button(tr("削除"), role: .destructive) { if let item = revoking { Task { await sharing.revokeFriendShare(id: item.id) } } }
            Button(tr("キャンセル"), role: .cancel) {}
        }
        .confirmationDialog(tr("フレンドを削除しますか？\n相手は、あなたに申請できず、\n記録も届かなくなります"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button(tr("削除"), role: .destructive) { if let f = deleting { Task { await sharing.deleteFriend(f) } } }
            Button(tr("キャンセル"), role: .cancel) {}
        }
    }

    /// フレンド：招待・コード入力・承認待ち・一覧
    private var friendsPage: some View {
        Form {
            // フレンド一覧を、いちばん上に
            friendsSection
            if !sharing.friends.friends.isEmpty {
                CardSection {
                    NavigationLink { CreateShareView(model: model, kind: .friends, recipients: sharing.friends.friends) } label: {
                        Label(tr("フレンドに記録を共有"), systemImage: "paperplane").foregroundStyle(Theme.accentText)
                    }
                    .frame(minHeight: 44)
                }
            }
            if !sharing.friends.incoming.isEmpty { incomingSection }
            if !sharing.friends.outgoing.isEmpty { outgoingSection }
            inviteSection
            codeSection
            if !sharing.blocked.isEmpty { blockedSection }
            if let message = sharing.message { CardSection { Text(message).font(.footnote).foregroundStyle(.secondary) } }
        }
        .compactForm()
    }

    /// 届いた記録：送ってきた人ごと
    private var receivedPage: some View {
        Form {
            if sharing.receivedShares.isEmpty {
                emptyNote(tr("届いた記録は、まだありません"))
            } else {
                receivedSection
            }
        }
        .compactForm()
    }

    /// 共有した記録
    private var sentPage: some View {
        Form {
            if sharing.sentShares.contains(where: { $0.status != "revoked" }) {
                sentSection
            } else {
                emptyNote(tr("共有した記録は、まだありません"))
            }
        }
        .compactForm()
    }

    private func emptyNote(_ text: String) -> some View {
        Section {
            Text(text).font(.subheadline).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 0, trailing: 8))
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
                    ShareLink(item: url, message: Text(tr("ふとのフレンド招待です\n招待コード：{0}", formatted(invitation.code)))) {
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

    /// フレンド一覧：横にスライドして見る（1人ずつのカードが、横に並ぶ）。
    @ViewBuilder
    private var friendsSection: some View {
        CardSection {
            Text(tr("フレンド一覧")).font(.footnote).foregroundStyle(.secondary)
            if sharing.friends.friends.isEmpty {
                Text(tr("まだフレンドはいません")).foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(sharing.friends.friends) { friend in friendCard(friend) }
                    }
                    .padding(.vertical, 4)
                }
                .scrollClipDisabled()
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 12, trailing: 0))
            }
        }
    }

    private func friendCard(_ friend: FriendsResponse.Friend) -> some View {
        VStack(spacing: 6) {
            AccountAvatar(name: friend.displayName, size: 56, spec: friend.avatar)
            Text(friend.displayName).font(.footnote.weight(.medium)).lineLimit(1).truncationMode(.tail)
                .frame(width: 84)
            // 削除は、関係を終わらせて、ブロックもする（まとめて1つのボタン）
            Button { deleting = friend } label: {
                Image(systemName: "trash").font(.footnote).foregroundStyle(.secondary)
                    .frame(width: 44, height: 32).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tr("フレンドを削除"))
        }
        .frame(width: 92)
        .padding(.vertical, 10)
        .background(Theme.softBlue.opacity(0.5), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// 届いた記録：送ってきた人ごとにまとめる。人を選んでから、いつの記録を見るか選ぶ。
    private var receivedSection: some View {
        CardSection {
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

    private var sentSection: some View {
        CardSection {
            ForEach(sharing.sentShares.filter { $0.status != "revoked" }) { item in
                HStack {
                    VStack(alignment: .leading) {
                        Text(periodLabel(item.period) + (sharing.isStanding(item.id) != nil ? " · " + tr("継続中") : ""))
                        Text(tr("{0}人・期限 {1}", "\(item.recipientCount)", dateText(item.expiresAt))).font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if item.status == "active" {
                        // 共有している中身を、その場で確かめる（フレンドに見える形で）
                        Button { previewing = item } label: { Image(systemName: "eye") }
                            .buttonStyle(ChipButtonStyle()).frame(width: 56)
                            .accessibilityLabel(tr("中身を見る"))
                        if sharing.isStanding(item.id) != nil {
                            Button(tr("更新")) { Task { await sharing.refreshStanding(sessions: model.sessions.all(), events: model.events.all(), mode: model.mode, force: true) } }
                                .buttonStyle(ChipButtonStyle()).fixedSize().disabled(sharing.isWorking)
                        }
                        Button(role: .destructive) { revoking = item } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(ChipButtonStyle()).frame(width: 56)
                        .accessibilityLabel(tr("削除"))
                    }
                }
            }
        }
    }

    /// 削除したフレンド（ブロック中）。ここから、解除できる。
    private var blockedSection: some View {
        CardSection {
            Text(tr("削除したフレンド")).font(.footnote).foregroundStyle(.secondary)
            ForEach(sharing.blocked) { user in
                HStack(spacing: 12) {
                    AccountAvatar(name: user.displayName, size: 32, spec: user.avatar)
                    Text(user.displayName).oneLine()
                    Spacer(minLength: 0)
                    Button(tr("ブロックを解除")) { Task { await sharing.unblock(user) } }
                        .buttonStyle(ChipButtonStyle()).fixedSize()
                }
                .frame(minHeight: 44)
            }
        }
    }
}

/// 1人ぶんの、届いた記録の一覧。いつの記録を見るか選ぶ。
@MainActor
struct FriendRecordsListView: View {
    let groupID: String
    @Environment(SharingModel.self) private var sharing
    @State private var confirmDeleteAll = false
    @State private var deletingRecord: ReceivedFriendShare?

    private var group: ReceivedGroup? { ReceivedGrouping.group(sharing.receivedShares).first { $0.id == groupID } }

    var body: some View {
        Form {
            if let group {
                CardSection {
                    ForEach(group.items) { item in
                        // 左：記録（押すと中身）。右：この記録の削除ボタン
                        HStack(spacing: 8) {
                            NavigationLink { FriendShareDetailView(id: item.id) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(periodLabel(item.period))
                                        Text(tr("更新 {0}", dateText(item.updatedAt ?? item.createdAt))).font(.footnote).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                    if sharing.isUnseen(item) { NewBadge() }
                                }
                            }
                            Button { deletingRecord = item } label: {
                                Image(systemName: "trash").font(.body).foregroundStyle(.secondary)
                                    .frame(width: 44, height: 44).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(tr("この記録を削除"))
                        }
                        .frame(minHeight: 44)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(tr("削除"), role: .destructive) { deletingRecord = item }
                        }
                    }
                }
                CardSection {
                    Button(role: .destructive) { confirmDeleteAll = true } label: {
                        Label(tr("この人の記録を、すべて削除"), systemImage: "trash").foregroundStyle(.red)
                    }
                    .frame(minHeight: 44)
                }
            } else {
                CardSection { Text(tr("この記録は、もう見られません")).foregroundStyle(.secondary) }
            }
        }
        .compactForm()
        .navigationTitle(group?.name ?? tr("匿名"))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(tr("この記録を削除しますか？\n相手の共有は、消えません"), isPresented: Binding(get: { deletingRecord != nil }, set: { if !$0 { deletingRecord = nil } }), titleVisibility: .visible) {
            Button(tr("削除"), role: .destructive) { if let item = deletingRecord { Task { await sharing.removeReceived(ids: [item.id]) } } }
            Button(tr("キャンセル"), role: .cancel) {}
        }
        .confirmationDialog(tr("この人の記録を、すべて削除しますか？\n相手の共有は、消えません"), isPresented: $confirmDeleteAll, titleVisibility: .visible) {
            Button(tr("削除"), role: .destructive) {
                if let group { Task { await sharing.removeReceived(ids: group.items.map(\.id)) } }
            }
            Button(tr("キャンセル"), role: .cancel) {}
        }
    }
}

/// フレンドから届いた統計。サーバーが、権限・期限・ブロックを確認してから返す。
@MainActor
struct FriendShareDetailView: View {
    let id: String
    @Environment(SharingModel.self) private var sharing
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false
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
        .navigationTitle(detail?.isOwner == true ? tr("共有した記録") : tr("届いた記録"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if detail != nil, detail?.isOwner == false {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { confirmDelete = true } label: { Image(systemName: "trash") }
                        .accessibilityLabel(tr("この記録を削除"))
                }
            }
        }
        .confirmationDialog(tr("この記録を削除しますか？\n相手の共有は、消えません"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(tr("削除"), role: .destructive) {
                Task { await sharing.removeReceived(ids: [id]); dismiss() }
            }
            Button(tr("キャンセル"), role: .cancel) {}
        }
        .task {
            detail = await sharing.friendShareDetail(id: id)
            failed = detail == nil
            // 開いたので、この版は「見た」にする（バッジが消える）
            if let detail, !detail.isOwner { sharing.markSeen(id: id, version: detail.updatedAt ?? detail.createdAt) }
        }
    }
}
