import SwiftUI

/// 設定。タブに分けて、それぞれ1画面に収める。
@MainActor
struct SettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false
    @State private var confirmOff = false
    @State private var confirmLeaveDevice = false

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

    private var isDemo: Bool { model.mode == .demo }

    /// 記録の画面と同じく、上にタブを出して切り替える。
    var body: some View {
        VStack(spacing: 0) {
            Picker(tr("設定"), selection: $tab) {
                ForEach(SettingsTab.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
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
        .confirmationDialog(
            tr("制限をはずしますか？ 自動ではかけ直されません。"),
            isPresented: $confirmOff, titleVisibility: .visible
        ) {
            Button(tr("はずす"), role: .destructive) { model.stopRestriction() }
            Button(tr("キャンセル"), role: .cancel) {}
        }
        .confirmationDialog(
            tr("実際の制限をはずして、デモに切り替えますか？"),
            isPresented: $confirmLeaveDevice, titleVisibility: .visible
        ) {
            Button(tr("はずして切り替える"), role: .destructive) { model.switchMode(to: .demo) }
            Button(tr("キャンセル"), role: .cancel) {}
        }
    }

    // MARK: 制限

    private var restrictionTab: some View {
        Form {
            CardSection {
                Toggle(tr("いつも制限する"), isOn: Binding(
                    get: { model.intendsRestriction },
                    set: { on in
                        if on { model.startRestriction() } else { confirmOff = true }
                    }))
                    .frame(minHeight: 44)
                Toggle(tr("デモモード"), isOn: Binding(
                    get: { isDemo },
                    set: { wantsDemo in
                        if wantsDemo, model.mode == .device, model.device.intendsRestriction {
                            confirmLeaveDevice = true
                        } else {
                            model.switchMode(to: wantsDemo ? .demo : .device)
                        }
                    }))
                    .frame(minHeight: 44)
            }

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

            if !isDemo {
                CardSection {
                    LabeledContent(tr("許可"), value: permissionText)
                    Button(model.permission == .approved ? tr("再確認") : tr("許可する")) {
                        if model.permission == .approved {
                            model.refresh()
                        } else {
                            Task { await model.requestPermission() }
                        }
                    }
                    .frame(minHeight: 44)
                    if let error = model.permissionError { Text(error).font(.footnote) }
                }
            }
        }
        .compactForm()
    }

    // MARK: その他

    private var otherTab: some View {
        Form {
            CardSection {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 12)], spacing: 14) {
                    ForEach(ThemeColor.allCases) { option in
                        themeSwatch(option)
                    }
                }
                .padding(.vertical, 6)
            }

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
                Button(tr("すべての記録を削除"), role: .destructive) { confirmDelete = true }
                    .frame(minHeight: 44)
            }

            #if DEBUG
            CardSection {
                Button(tr("初回説明をもう一度表示")) {
                    // 設定のシートが閉じきってから説明に切り替える（同時だと、シートと説明の配色が乱れる）。
                    dismiss()
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(700))
                        model.replayOnboardingForDebug()
                    }
                }
                .frame(minHeight: 44)
            }
            if !isDemo {
                CardSection {
                    Text(SharedState.lastEvent ?? tr("拡張の記録はまだありません"))
                        .font(.subheadline)
                    Text(SharedState.isAvailable ? tr("App Group：利用できます") : tr("App Group：利用できません"))
                        .font(.subheadline)
                }
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
            VStack(spacing: 6) {
                Circle()
                    .fill(swatch)
                    .frame(width: 44, height: 44)
                    .overlay(Circle().stroke(.primary.opacity(selected ? 0.7 : 0), lineWidth: 2).padding(-4))
                    .overlay(Image(systemName: "checkmark").font(.footnote.bold())
                        .foregroundStyle(.white).opacity(selected ? 1 : 0))
                Text(option.name).font(.caption).foregroundStyle(.primary).oneLine()
            }
            .frame(maxWidth: .infinity, minHeight: 44)
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
