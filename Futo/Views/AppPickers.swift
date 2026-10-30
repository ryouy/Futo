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

/// 「使いたい」の後、制限中のものから、一時的に使えるようにするものを1つ以上選ぶ。
/// 決定の操作は画面下に固定し、選択肢と混ざらないようにする。
@MainActor
struct UnlockChooserView: View {
    let model: AppModel
    @State private var chosen: Set<RestrictedItem>
    @State private var decision: Decision?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private enum Decision { case use, decline }

    /// 選んだことを少しの間だけ見せてから進む（もう一方がうすれる）。連打しても、1回だけ。
    private func decide(_ value: Decision) {
        guard decision == nil else { return }
        withAnimation(.easeInOut(duration: reduceMotion ? 0.15 : 0.2)) { decision = value }
        let picked = chosen
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            if value == .use { model.unlockItems(RestrictedItems(items: Array(picked))) } else { model.declineUnlock() }
        }
    }

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
            // ホームの一覧と同じく、下は、ぼかして見切れさせる（ボタンと接しないように）
            .mask(
                VStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 32)
                }
            )
            .padding(.bottom, 8)

            VStack(spacing: 4) {
                // 使う側は薄く、やめる側は濃く。
                Button(tr("選んだものを使う")) { decide(.use) }
                    .buttonStyle(FutoButtonStyle(prominent: false))
                    .disabled(chosen.isEmpty)
                    .opacity(decision == .decline ? 0.3 : 1)
                    .scaleEffect(decision == .use && !reduceMotion ? 0.97 : 1)
                Button(tr("やめておく")) { decide(.decline) }
                    .buttonStyle(FutoButtonStyle())
                    .opacity(decision == .use ? 0.3 : 1)
                    .scaleEffect(decision == .decline && !reduceMotion ? 0.97 : 1)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}
