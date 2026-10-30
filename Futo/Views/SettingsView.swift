import SwiftUI

/// 設定。タブに分けて、それぞれ1画面に収める。
@MainActor
struct SettingsView: View {
    @Bindable var model: AppModel
    @Environment(SharingModel.self) private var sharing
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
            Picker(tr("設定"), selection: $tab) {
                ForEach(SettingsTab.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .overlay(alignment: .topLeading) {
                // 「アカウント」（3番目）の右上に、新しい記録があるしるし
                if sharing.hasUnseenRecords {
                    GeometryReader { geo in
                        NewBadge(size: 9).position(x: geo.size.width * 0.75 - 6, y: 5)
                    }
                    .allowsHitTesting(false)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)

            switch tab {
            case .restriction: restrictionTab
            case .notification: NotificationSettingsView(model: model)
            case .account: SharingTab(model: model)
            case .other: otherTab
            }
        }
        .background(Theme.background.ignoresSafeArea())
        // テーマカラーを変えた瞬間に、設定の中の色（言語の選択など）も変わるように
        .tint(Theme.accent)
        .id(ThemeStore.shared.color)
        .animation(.easeInOut(duration: 0.25), value: tab)
        .navigationTitle(tr("設定"))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            tr("すべての記録を削除しますか？ 制限の設定は変わりません。"),
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

            CardSection {
                Picker(tr("待機時間"), selection: Binding(
                    get: { model.prefs.effectiveWaitSeconds },
                    set: { value in model.updatePreferences { $0.waitSeconds = value } }
                )) {
                    ForEach(Preferences.waitOptions, id: \.self) { Text(durationText(seconds: $0)).tag($0) }
                }
                .frame(minHeight: 44)
                Picker(tr("解除する時間"), selection: Binding(
                    get: { model.prefs.effectiveUnlockMinutes },
                    set: { value in model.updatePreferences { $0.unlockMinutes = value } }
                )) {
                    ForEach(Preferences.unlockMinuteOptions, id: \.self) { Text(tr("{0}分", "\($0)")).tag($0) }
                }
                .frame(minHeight: 44)
            }

            CardSection {
                NavigationLink { RestrictionManagementView(model: model) } label: {
                    Label(tr("制限の管理"), systemImage: "lock.shield").foregroundStyle(Theme.accent)
                }
                .frame(minHeight: 44)
            }

            if model.permission == .approved { permissionSection }
        }
        .compactForm()
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
                    .foregroundStyle(Theme.accent)
            }
            .frame(minHeight: 44)
            if let error = model.permissionError { Text(error).font(.footnote) }
        }
    }

    // MARK: その他

    private var otherTab: some View {
        Form {
            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 12)], spacing: 14) {
                    ForEach(ThemeColor.allCases) { option in
                        themeSwatch(option)
                    }
                }
                .padding(.vertical, 6)
            } header: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("テーマカラー")).font(.footnote.weight(.semibold)).foregroundStyle(Theme.accent)
                    Text(tr("アプリ全体の色を変えます")).font(.caption).foregroundStyle(.secondary)
                }
                .textCase(nil)
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

            CardSection {
                Button(role: .destructive) { confirmDelete = true } label: {
                    Label(tr("すべての記録を削除"), systemImage: "trash").foregroundStyle(.red)
                }
                .frame(minHeight: 44)
            }

            #if DEBUG
            CardSection {
                Button {
                    // 設定のシートが閉じきってから説明に切り替える（同時だと、シートと説明の配色が乱れる）。
                    dismiss()
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(700))
                        model.replayOnboardingForDebug()
                    }
                } label: {
                    Label(tr("初回説明をもう一度表示"), systemImage: "arrow.counterclockwise").foregroundStyle(Theme.accent)
                }
                .frame(minHeight: 44)
            }
            #endif
        }
        .compactForm()
    }

    private func themeSwatch(_ option: ThemeColor) -> some View {
        let selected = ThemeStore.shared.color == option
        let swatch = Color(uiColor: UIColor { trait in
            let hex = trait.userInterfaceStyle == .dark ? option.palette.accent.1 : option.palette.accent.0
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
        return Button {
            withAnimation(.easeInOut(duration: 0.3)) { ThemeStore.shared.select(option) }
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
