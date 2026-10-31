import FamilyControls
import ManagedSettings
import SwiftUI

/// 制限するもの1つぶんのラベル。名前やアイコンはOSが描画し、アプリ側は名前を取得しない。
struct ItemLabel: View, Equatable {
    let item: RestrictedItem

    var body: some View {
        // 名前（長いURLなど）は、収まらなければ「…」で省略する
        Group {
            switch item {
            case .app(let token): Label(token)
            case .category(let token): Label(token)
            case .web(let token): Label(token)
            }
        }
        .lineLimit(1)
        .truncationMode(.tail)
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
                            let removedSelf = model.device.saveSelection(draft, additiveOnly: model.isTargetEditLocked)
                            model.didChangeDeviceSelection()
                            if removedSelf { model.notice = tr("「ふと」自身は、制限できません") }
                            dismiss()
                        }
                    }
                }
        }
    }
}

/// デモのアプリのアイコン（グラデーションの角丸に白い記号）。
struct DemoAppIcon: View {
    let app: DemoApp
    var size: CGFloat = 32

    private func color(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
            .fill(LinearGradient(colors: [color(app.top), color(app.bottom)], startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            .overlay(Image(systemName: app.symbol).font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(.white))
            .accessibilityHidden(true)
    }
}

/// デモ用：制限中のアプリを開いたときに出る、OSの画面（シールド）の再現。
/// 実機では、OSが同じ内容を表示する（`FutoShieldConfiguration`）。
struct DemoShieldView: View {
    let app: DemoApp
    @Environment(\.dismiss) private var dismiss

    private func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(red: 0x19 / 255, green: 0x64 / 255, blue: 0x59 / 255))
                .frame(width: 112, height: 112)
                .overlay(Image("Logo").resizable().scaledToFit().padding(18))
                .padding(.bottom, 24)
            Text(tr("使う前に、ひと呼吸"))
                .font(.title2.weight(.bold))
                .foregroundStyle(dynamic(0x124A42, 0xFCF8F0))
                .padding(.bottom, 10)
            Text(tr("今、何に使いたいですか\n『ふと』で少し立ち止まれます\nホーム画面から開いてください"))
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(dynamic(0x4F5F5A, 0xD9D4C8))
            Spacer()
            Button { dismiss() } label: {
                Text(tr("ホームに戻る"))
                    .font(.headline)
                    .foregroundStyle(dynamic(0xFCF8F0, 0x124A42))
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(Capsule().fill(dynamic(0x196459, 0xFCF8F0)))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(dynamic(0xFCF8F0, 0x10312C).ignoresSafeArea())
        .accessibilityLabel(app.name)
    }
}

/// デモ用：アプリから選ぶ。Screen Timeは呼ばない。
@MainActor
struct DemoAppPickerView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(DemoApp.catalog) { app in
                        let name = app.name
                        let on = model.demo.targets.contains(name)
                        Button {
                            model.setDemoTarget(name, selected: !on)
                        } label: {
                            HStack(spacing: 12) {
                                DemoAppIcon(app: app, size: 32)
                                Text(name).foregroundStyle(.primary)
                                Spacer()
                                if on { Image(systemName: "checkmark").accessibilityLabel(tr("選択中")) }
                            }
                            .frame(minHeight: 44)
                        }
                    }
                } footer: {
                    Text(tr("デモ用のアプリです。実際のアプリは制限されません。"))
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
