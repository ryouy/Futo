import SwiftUI

/// 設定。タブに分けて、それぞれ1画面に収める。
@MainActor
struct SettingsView: View {
    @Bindable var model: AppModel
    @Environment(SharingModel.self) private var sharing
    @Environment(AdsService.self) private var ads
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    private enum SettingsTab: Int, CaseIterable {
        case restriction, notification, account, other

        var title: String {
            switch self {
            case .restriction: return tr("制限")
            case .notification: return tr("通知")
            case .account: return tr("アカウント")
            case .other: return tr("その他")
            }
        }
    }
    @State private var tab: SettingsTab = .restriction

    /// 記録の画面と同じく、上にタブを出して切り替える。
    var body: some View {
        VStack(spacing: 0) {
            FutoTabPicker(items: SettingsTab.allCases, selection: $tab, title: { $0.title },
                          badge: { $0 == .account && sharing.hasUnseenRecords })
            .padding(.horizontal, 20)
            .padding(.bottom, 8)

            // 左右にスワイプして、タブを切り替えられる
            TabView(selection: $tab) {
                restrictionTab.tag(SettingsTab.restriction)
                NotificationSettingsView(model: model).tag(SettingsTab.notification)
                SharingTab(model: model).tag(SettingsTab.account)
                otherTab.tag(SettingsTab.other)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .background(Theme.background.ignoresSafeArea())
        // 招待リンクから来たときは、アカウントのタブを開く
        .onAppear { if sharing.openFriendsPending { tab = .account } }
        .onChange(of: sharing.friendsRequestID) { _, _ in tab = .account }
        // テーマカラーを変えた瞬間に、設定の中の色（言語の選択など）も変わるように
        .tint(Theme.accentText)
        .id(ThemeStore.shared.selectionKey)
        .navigationTitle(tr("設定"))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            tr("すべての記録を削除しますか？\n制限の設定は変わりません"),
            isPresented: $confirmDelete, titleVisibility: .visible
        ) {
            Button(tr("削除"), role: .destructive) { model.deleteAllRecords() }
            Button(tr("キャンセル"), role: .cancel) {}
        }
    }

    // MARK: 制限

    /// 制限：一時解除のルール → 制限の管理 → 許可。許可が済んでいないときだけ、許可を先頭に出す。
    private var restrictionTab: some View {
        Form {
            if model.permission != .approved { permissionSection }

            // ゆるめる変更（待機を短く・解除を長く）の決まりを、いつも、待機時間の上に出す
            DescribedSection(lines: [tr("ゆるめる変更は、1分後に反映されます")]) {
                Picker(tr("待機時間"), selection: Binding(
                    get: { model.prefs.pendingWaitSeconds ?? model.prefs.effectiveWaitSeconds },
                    set: { value in model.updatePreferences { $0.setWait(value) } }
                )) {
                    ForEach(Preferences.waitOptions, id: \.self) { Text(durationText(seconds: $0)).tag($0) }
                }
                .frame(minHeight: 44)
                Picker(tr("解除する時間"), selection: Binding(
                    get: { model.prefs.pendingUnlockMinutes ?? model.prefs.effectiveUnlockMinutes },
                    set: { value in model.updatePreferences { $0.setUnlockMinutes(value) } }
                )) {
                    ForEach(Preferences.unlockMinuteOptions, id: \.self) { Text(tr("{0}分", "\($0)")).tag($0) }
                }
                .frame(minHeight: 44)
            }

            CardSection {
                NavigationLink { RestrictionManagementView(model: model) } label: {
                    Label(tr("制限の管理"), systemImage: "lock.shield").foregroundStyle(Theme.accentText)
                }
                .frame(minHeight: 44)
            }

            if model.permission == .approved { permissionSection }
        }
        .compactForm()
        .task {
            // 1分たった変更を、本設定へ移す
            while !Task.isCancelled {
                if model.prefs.pendingWaitAt != nil || model.prefs.pendingUnlockAt != nil {
                    model.updatePreferences { $0.settlePending() }
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var permissionSection: some View {
        CardSection {
            LabeledContent(tr("許可"), value: permissionText)
            Button {
                if model.permission == .approved {
                    model.refresh()
                } else {
                    Task { await model.requestPermission() }
                }
            } label: {
                Label(model.permission == .approved ? tr("再確認") : tr("許可する"),
                      systemImage: model.permission == .approved ? "arrow.clockwise" : "hand.raised")
                    .foregroundStyle(Theme.accentText)
            }
            .frame(minHeight: 44)
            if let error = model.permissionError { Text(error).font(.footnote) }
        }
    }

    // MARK: その他

    /// 紹介サイト（共有・招待と同じドメインの /about）。課金のページへのリンクを取り除いた、アプリ用のページ。
    private var introSiteURL: URL? {
        (sharing.config.apiBaseURL ?? URL(string: "https://futo-share.vercel.app")).flatMap { URL(string: "about", relativeTo: $0)?.absoluteURL }
    }

    private var otherTab: some View {
        Form {
            Section {
                // 4色と、一番右の好きな色を、1列に並べる
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 14) {
                    ForEach(ThemeColor.allCases) { option in
                        themeSwatch(option)
                    }
                    // 一番右：好きな色
                    CustomColorWell(hex: ThemeStore.shared.customHex ?? "#196459", isSelected: ThemeStore.shared.isCustom, label: tr("好きな色")) { hex in
                        ThemeStore.shared.selectCustom(hex: hex)
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                }
                .padding(.vertical, 6)
            } header: {
                Text(tr("テーマカラー")).font(.footnote.weight(.semibold)).foregroundStyle(Theme.accentText).textCase(nil)
            }
            .listRowBackground(Theme.card)

            CardSection {
                // 選択肢は、どちらの言語で表示していても、その言語自身の名前で出す。
                Picker("言語 / Language", selection: Binding(
                    get: { LanguageStore.shared.language },
                    set: { model.changeLanguage($0) }
                )) {
                    ForEach(AppLanguage.allCases) { Text($0.displayName).tag($0) }
                }
                .frame(minHeight: 44)
            }

            // 広告の同意が必要な地域（EEA・英国など）だけ、選択をやり直す入口を出す
            if ads.privacyOptionsRequired {
                CardSection {
                    Button { Task { await ads.presentPrivacyOptions() } } label: {
                        Label(tr("広告のプライバシー設定"), systemImage: "hand.raised").foregroundStyle(Theme.accentText)
                    }
                    .frame(minHeight: 44)
                }
            }

            CardSection {
                NavigationLink { SupportView() } label: {
                    Label(tr("ふとを応援"), systemImage: "heart").foregroundStyle(Theme.accentText)
                }
                .frame(minHeight: 44)
                // ふとの紹介サイト（ブラウザで開く）
                if let site = introSiteURL {
                    Link(destination: site) {
                        Label(tr("ふとの紹介サイト"), systemImage: "safari").foregroundStyle(Theme.accentText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 44)
                }
            }

            CardSection {
                Button(role: .destructive) { confirmDelete = true } label: {
                    Label(tr("すべての記録を削除"), systemImage: "trash").foregroundStyle(.red)
                }
                .frame(minHeight: 44)
            }

            #if DEBUG
            // 開発用（Debugビルドにだけ存在する）：ハンマーの印の1つのメニューに、まとめてしまう
            CardSection {
                Menu {
                    Button(tr("朝の振り返り")) { model.showReflectionNow(.morning); dismiss() }
                    Button(tr("夜の振り返り")) { model.showReflectionNow(.night); dismiss() }
                    Button(tr("お出かけ通知")) { model.sendTestNotification(.outing) }
                    // 待機を省略して、本アプリの制限をすぐ解除する（記録には数えない）。
                    Button("制限解除") { model.debugReleaseRestrictionNow() }
                    Button(tr("初回説明をもう一度表示")) {
                        // 設定のシートが閉じきってから説明に切り替える（同時だと、シートと説明の配色が乱れる）。
                        dismiss()
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(700))
                            model.replayOnboardingForDebug()
                        }
                    }
                } label: {
                    Label("開発用", systemImage: "hammer").foregroundStyle(Theme.accentText)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
            }
            #endif
        }
        .compactForm()
    }

    private func themeSwatch(_ option: ThemeColor) -> some View {
        let selected = !ThemeStore.shared.isCustom && ThemeStore.shared.color == option
        let swatch = Color(uiColor: UIColor { trait in
            let hex = trait.userInterfaceStyle == .dark ? option.palette.accent.1 : option.palette.accent.0
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
        return Button {
            ThemeCrossfade.run { ThemeStore.shared.select(option) }
        } label: {
            Circle()
                .fill(swatch)
                .frame(width: 44, height: 44)
                .overlay(Circle().stroke(.primary.opacity(selected ? 0.7 : 0), lineWidth: 2).padding(-4))
                .overlay(Image(systemName: "checkmark").font(.footnote.bold())
                    .foregroundStyle(.white).opacity(selected ? 1 : 0))
                .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var permissionText: String {
        switch model.permission {
        case .notDetermined: return tr("未確認")
        case .approved: return tr("許可済み")
        case .denied: return tr("許可されていません")
        }
    }
}

extension View {
    /// 設定の各タブ：背景を揃え、中身が収まるときはバウンスさせない。
    func compactForm() -> some View {
        self.scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .scrollBounceBehavior(.basedOnSize)
    }
}
