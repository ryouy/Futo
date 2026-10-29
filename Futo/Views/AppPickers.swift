import FamilyControls
import ManagedSettings
import SwiftUI

/// 実機で選んだ対象のラベル表示。名前やbundle IDは取得せず、OS提供のラベルだけを使う。
struct DeviceTargetLabels: View {
    let selection: FamilyActivitySelection

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(selection.applicationTokens), id: \.self) { token in
                Label(token)
            }
        }
    }
}

/// 実機用：FamilyActivityPicker。アプリ単位のみ保存する。
@MainActor
struct DeviceAppPickerView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft: FamilyActivitySelection
    @State private var showUnsupported = false

    init(model: AppModel) {
        self.model = model
        _draft = State(initialValue: model.device.selection)
    }

    var body: some View {
        NavigationStack {
            FamilyActivityPicker(selection: $draft)
                .navigationTitle("制限するアプリ")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("キャンセル") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") { save() }
                    }
                }
                .alert("アプリを選び直してください", isPresented: $showUnsupported) {
                    Button("閉じる", role: .cancel) {}
                } message: {
                    Text("この試作では、カテゴリやWebサイトは対象外です。アプリを個別に選んでください。何も保存していません。")
                }
        }
    }

    private func save() {
        switch model.device.saveSelection(draft) {
        case .saved:
            model.didChangeDeviceSelection()
            dismiss()
        case .unsupportedItems:
            showUnsupported = true
        }
    }
}

/// デモ用：架空アプリから1つ選ぶ。Screen Timeは呼ばない。
@MainActor
struct DemoAppPickerView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(DemoRestrictionService.fictionalApps, id: \.self) { name in
                        Button {
                            model.selectDemoTarget(name)
                            dismiss()
                        } label: {
                            HStack {
                                Text(name).foregroundStyle(.primary)
                                Spacer()
                                if model.demo.targetName == name {
                                    Image(systemName: "checkmark").accessibilityLabel("選択中")
                                }
                            }
                            .frame(minHeight: 44)
                        }
                    }
                } footer: {
                    Text("デモ用の架空のアプリです。実際のアプリは制限されません。")
                }
            }
            .navigationTitle("制限するアプリ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
            }
        }
    }
}

/// 「使いたい」の後、制限中のアプリのうち、一時的に使えるようにするものを1つ以上選ぶ。
@MainActor
struct UnlockChooserView: View {
    let model: AppModel
    @State private var chosen: Set<ApplicationToken>

    init(model: AppModel) {
        self.model = model
        let all = model.device.selection.applicationTokens
        _chosen = State(initialValue: all.count == 1 ? all : [])
    }

    private var all: [ApplicationToken] { Array(model.device.selection.applicationTokens) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("どのアプリを使いますか？").font(.title2.weight(.medium))
                Text("選んだアプリだけを、一時的に使えるようにします。選ばなかったアプリは制限されたままです。")
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)

                ForEach(all, id: \.self) { token in
                    let isOn = chosen.contains(token)
                    Button {
                        if isOn { chosen.remove(token) } else { chosen.insert(token) }
                    } label: {
                        HStack {
                            Label(token).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(Theme.accent)
                        }
                        .frame(minHeight: 58)
                        .padding(.horizontal, 20)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(isOn ? Theme.accent : Theme.accent.opacity(0.10), lineWidth: isOn ? 2 : 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }

                if all.count > 1 {
                    Button(chosen.count == all.count ? "すべての選択を外す" : "すべて選ぶ") {
                        chosen = chosen.count == all.count ? [] : Set(all)
                    }
                    .buttonStyle(FutoButtonStyle(prominent: false))
                }

                Button("選んだアプリを一時的に使う") { model.unlockApps(chosen) }
                    .buttonStyle(FutoButtonStyle())
                    .disabled(chosen.isEmpty)
                Button("使わない") { model.declineUnlock() }
                    .buttonStyle(FutoButtonStyle(prominent: false))
            }
            .padding(20)
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}
