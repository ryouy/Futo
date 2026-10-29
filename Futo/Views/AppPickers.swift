import FamilyControls
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
