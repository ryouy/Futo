import SwiftUI

@MainActor
struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var showPicker = false
    @State private var confirmDelete = false
    @State private var confirmLeaveDevice = false

    private var isDemo: Bool { model.mode == .demo }

    var body: some View {
        Form {
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
                     ? "デモでは実際のアプリは制限しません。記録もデモ専用です。"
                     : "実機モードでは、Screen Timeで選んだアプリを実際に制限します。")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            if !isDemo {
                Section("アクセスの許可") {
                    LabeledContent("状態", value: permissionText)
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
                Button("制限するアプリを変更") { showPicker = true }
                    .frame(minHeight: 44)
                    .disabled(model.isTargetLocked || (!isDemo && model.permission != .approved))
            } header: {
                Text("制限するアプリ")
            } footer: {
                if !isDemo, !model.isTargetLocked {
                    Text("ホームの状態は、権限と設定の照合結果です。シールドが実際に出ているかは、対象アプリを開いて確かめてください。")
                } else if model.isTargetLocked {
                    Text("制限を終了してから変更してください。")
                } else if !isDemo, model.permission != .approved {
                    Text("先にアクセスを許可してください。")
                }
            }

            Section {
                Button("すべての記録を削除", role: .destructive) { confirmDelete = true }
                    .frame(minHeight: 44)
            } header: {
                Text("記録")
            } footer: {
                Text("削除するのは振り返りの記録だけです。制限の設定は変わりません。")
            }

            Section("この試作について") {
                Text("""
                一時解除と自動再制限は、実機のみの試験機能です。デモでは行いません。\
                制限はホームの「制限を終了」から、いつでも本人が終了できます。\
                Screen Timeの許可は、設定アプリからいつでも取り消せます。
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
                    Text("Debugビルドのみ表示。待機は10秒、一時解除の利用しきい値は\(SharedState.unlockUsageMinutes)分です。")
                }
            }
            #endif
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("設定")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPicker) {
            if isDemo { DemoAppPickerView(model: model) } else { DeviceAppPickerView(model: model) }
        }
        .confirmationDialog(
            "すべての記録を削除しますか？ 振り返りの記録だけが消え、制限の設定は変わりません。進行中の振り返りは中断として閉じてから削除します。",
            isPresented: $confirmDelete, titleVisibility: .visible
        ) {
            Button("削除", role: .destructive) { model.deleteAllRecords() }
            Button("キャンセル", role: .cancel) {}
        }
        .confirmationDialog(
            "実際の制限を終了して、デモに切り替えますか？",
            isPresented: $confirmLeaveDevice, titleVisibility: .visible
        ) {
            Button("制限を終了して切り替える", role: .destructive) { model.switchMode(to: .demo) }
            Button("キャンセル", role: .cancel) {}
        }
    }

    private var permissionText: String {
        switch model.permission {
        case .notDetermined: return "未確認"
        case .approved: return "許可済み"
        case .denied: return "許可されていません"
        }
    }
}
