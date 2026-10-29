import SwiftUI

@MainActor
struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var confirmDelete = false
    @State private var confirmOff = false
    @State private var confirmLeaveDevice = false

    private var isDemo: Bool { model.mode == .demo }

    var body: some View {
        Form {
            Section {
                Toggle("いつも制限する", isOn: Binding(
                    get: { model.intendsRestriction },
                    set: { on in
                        if on { model.startRestriction() } else { confirmOff = true }
                    }))
                    .frame(minHeight: 44)
            } header: {
                Text("制限")
            } footer: {
                Text("ふだんは制限をかけておき、使いたいときだけ、ひと呼吸おいて解除します。オフにすると、自動ではオンに戻りません。")
            }

            Section("動作モード") {
                Toggle("デモモード", isOn: Binding(
                    get: { isDemo },
                    set: { wantsDemo in
                        if wantsDemo, model.mode == .device, model.device.intendsRestriction {
                            confirmLeaveDevice = true
                        } else {
                            model.switchMode(to: wantsDemo ? .demo : .device)
                        }
                    }
                ))
                .frame(minHeight: 44)
                Text(isDemo
                     ? "実際のアプリは制限しません。記録もデモ専用です。"
                     : "選んだものを実際に制限します。")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            if !isDemo {
                Section("アクセスの許可") {
                    LabeledContent("許可", value: permissionText)
                        .accessibilityElement(children: .combine)
                    Button(model.permission == .approved ? "再確認" : "許可する") {
                        if model.permission == .approved {
                            model.refresh()
                        } else {
                            Task { await model.requestPermission() }
                        }
                    }
                    .frame(minHeight: 44)
                    if let error = model.permissionError {
                        Text(error).font(.footnote)
                    }
                }
            }

            Section {
                Picker("待機時間", selection: Binding(
                    get: { model.prefs.effectiveWaitSeconds },
                    set: { value in model.updatePreferences { $0.waitSeconds = value } }
                )) {
                    ForEach(Preferences.waitOptions, id: \.self) { Text(durationText(seconds: $0)).tag($0) }
                }
                .frame(minHeight: 44)
            } header: {
                Text("ひと呼吸")
            } footer: {
                Text("使いたい気持ちを確かめるまでの待ち時間です。次のひと呼吸から変わります。")
            }

            Section {
                Toggle("朝の振り返り", isOn: Binding(
                    get: { model.prefs.morningEnabled },
                    set: { on in model.updatePreferences { $0.morningEnabled = on } }))
                    .frame(minHeight: 44)
                if model.prefs.morningEnabled {
                    DatePicker("時刻", selection: minuteBinding(
                        get: { model.prefs.morningMinute },
                        set: { value in model.updatePreferences { $0.morningMinute = value } }),
                        displayedComponents: .hourAndMinute)
                        .frame(minHeight: 44)
                }
                Toggle("夜の振り返り", isOn: Binding(
                    get: { model.prefs.nightEnabled },
                    set: { on in model.updatePreferences { $0.nightEnabled = on } }))
                    .frame(minHeight: 44)
                if model.prefs.nightEnabled {
                    DatePicker("時刻", selection: minuteBinding(
                        get: { model.prefs.nightMinute },
                        set: { value in model.updatePreferences { $0.nightMinute = value } }),
                        displayedComponents: .hourAndMinute)
                        .frame(minHeight: 44)
                }
                NavigationLink("通知") { NotificationSettingsView(model: model) }
                    .frame(minHeight: 44)
            } header: {
                Text("朝・夜の振り返り")
            } footer: {
                Text("設定した時刻から約6時間、ホームにカードを出します。日の区切りは午前4時で、深夜の記録は前日として数えます。カードは閉じられ、答えを求めることはありません。")
            }

            Section("テーマカラー") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 12)], spacing: 14) {
                    ForEach(ThemeColor.allCases) { option in
                        themeSwatch(option)
                    }
                }
                .padding(.vertical, 6)
            }

            Section {
                Button("すべての記録を削除", role: .destructive) { confirmDelete = true }
                    .frame(minHeight: 44)
            } header: {
                Text("記録")
            } footer: {
                Text("記録だけが消えます。制限の設定は変わりません。")
            }

            Section("この試作について") {
                Text("""
                一時解除と自動再制限は、実機のみの試験機能です。\
                制限は、「いつも制限する」をオフにすれば、いつでも外せます。\
                許可は、iPhoneの設定アプリから取り消せます。\
                ホームの状態は、許可と設定の照合結果です。シールドが出ているかは、対象アプリを開いて確かめてください。
                """)
                .font(.footnote)
            }

            #if DEBUG
            if !isDemo {
                Section {
                    Text(SharedState.lastEvent ?? "まだ記録はありません")
                        .font(.footnote)
                    Text(SharedState.isAvailable ? "App Group：利用できます" : "App Group：利用できません（未設定）")
                        .font(.footnote).foregroundStyle(.secondary)
                } header: {
                    Text("検証用：拡張の最後の動作")
                } footer: {
                    Text("Debugビルドのみ表示。待機の既定は10秒、一時解除の利用しきい値は\(SharedState.unlockUsageMinutes)分です。")
                }
            }
            #endif
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("設定")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "すべての記録を削除しますか？ 制限の設定は変わりません。進行中のひと呼吸は中断として閉じてから削除します。",
            isPresented: $confirmDelete, titleVisibility: .visible
        ) {
            Button("削除", role: .destructive) { model.deleteAllRecords() }
            Button("キャンセル", role: .cancel) {}
        }
        .confirmationDialog(
            "制限をオフにしますか？ 自動ではオンに戻りません。",
            isPresented: $confirmOff, titleVisibility: .visible
        ) {
            Button("オフにする", role: .destructive) { model.stopRestriction() }
            Button("キャンセル", role: .cancel) {}
        }
        .confirmationDialog(
            "実際の制限をオフにして、デモに切り替えますか？",
            isPresented: $confirmLeaveDevice, titleVisibility: .visible
        ) {
            Button("オフにして切り替える", role: .destructive) { model.switchMode(to: .demo) }
            Button("キャンセル", role: .cancel) {}
        }
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
                Text(option.name).font(.caption).foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var permissionText: String {
        switch model.permission {
        case .notDetermined: return "未確認"
        case .approved: return "許可済み"
        case .denied: return "許可されていません"
        }
    }
}
