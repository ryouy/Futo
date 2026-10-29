import FamilyControls
import ManagedSettings
import SwiftUI

/// 制限するもの1つぶんのラベル。名前やアイコンはOSが描画し、アプリ側は名前を取得しない。
struct ItemLabel: View, Equatable {
    let item: RestrictedItem

    var body: some View {
        switch item {
        case .app(let token): Label(token)
        case .category(let token): Label(token)
        case .web(let token): Label(token)
        }
    }
}

/// 実機用：FamilyActivityPicker。アプリ・カテゴリ・ウェブサイトを選べる。
@MainActor
struct DeviceAppPickerView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft: FamilyActivitySelection

    init(model: AppModel) {
        self.model = model
        _draft = State(initialValue: model.device.selection)
    }

    var body: some View {
        NavigationStack {
            FamilyActivityPicker(selection: $draft)
                .navigationTitle(tr("制限するもの"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(tr("キャンセル")) { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(tr("保存")) {
                            // 制限中は、追加だけ。外したものは元に戻る。
                            model.device.saveSelection(draft, additiveOnly: model.isTargetEditLocked)
                            model.didChangeDeviceSelection()
                            dismiss()
                        }
                    }
                }
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
                                Text(tr(name)).foregroundStyle(.primary)
                                Spacer()
                                if model.demo.targetName == name {
                                    Image(systemName: "checkmark").accessibilityLabel(tr("選択中"))
                                }
                            }
                            .frame(minHeight: 44)
                        }
                    }
                } footer: {
                    Text(tr("デモ用の架空のアプリです。実際のアプリは制限されません。"))
                }
            }
            .navigationTitle(tr("制限するもの"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("閉じる")) { dismiss() } }
            }
        }
    }
}

/// 「使いたい」の後、制限中のものから、一時的に使えるようにするものを1つ以上選ぶ。
/// 決定の操作は画面下に固定し、選択肢と混ざらないようにする。
@MainActor
struct UnlockChooserView: View {
    let model: AppModel
    @State private var chosen: Set<RestrictedItem>

    init(model: AppModel) {
        self.model = model
        let all = model.device.items.sortedItems
        self.all = all
        _chosen = State(initialValue: all.count == 1 ? Set(all) : [])
    }

    /// 表示のたびに作り直さない（OSが描画するラベルの再読み込みで、選ぶたびにもたつくのを防ぐ）。
    private let all: [RestrictedItem]

    var body: some View {
        VStack(spacing: 0) {
            CenteredScroll {
                VStack(spacing: 14) {
                    Text(tr("どれを使いますか？"))
                        .font(.title2.weight(.medium))
                        .oneLine()
                        .padding(.bottom, 6)

                    if all.count > 1 {
                        HStack {
                            Spacer()
                            Button(chosen.count == all.count ? tr("選択を外す") : tr("すべて選ぶ")) {
                                chosen = chosen.count == all.count ? [] : Set(all)
                            }
                            .font(.subheadline.weight(.medium))
                            .frame(minHeight: 44)
                        }
                    }
                    ForEach(all) { item in
                        ChoiceRow(isOn: chosen.contains(item)) {
                            if chosen.contains(item) { chosen.remove(item) } else { chosen.insert(item) }
                        } content: {
                            ItemLabel(item: item).equatable()
                        }
                    }
                }
            }

            VStack(spacing: 4) {
                // 使う側は薄く、やめる側は濃く。
                Button(tr("選んだものを使う")) { model.unlockItems(RestrictedItems(items: Array(chosen))) }
                    .buttonStyle(FutoButtonStyle(prominent: false))
                    .disabled(chosen.isEmpty)
                Button(tr("やめておく")) { model.declineUnlock() }
                    .buttonStyle(FutoButtonStyle())
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}
