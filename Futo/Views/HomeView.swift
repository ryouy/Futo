import FamilyControls
import ManagedSettings
import SwiftData
import SwiftUI

@MainActor
struct HomeView: View {
    @Bindable var model: AppModel
    @Query(sort: \Session.startedAt, order: .reverse) private var sessions: [Session]
    @State private var sheet: HomeSheet?
    @State private var pendingRemoval: Removal?

    private enum HomeSheet: Identifiable {
        case history, settings, picker, todayDeferred, todayWants
        var id: Self { self }
    }

    private enum Removal: Identifiable {
        case demo
        case device(RestrictedItem)
        var id: String {
            switch self {
            case .demo: return "demo"
            case .device(let item): return "device-\(item.id)"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 8) {
                    LeafMark(size: 26)
                    Text("ふと").font(.largeTitle.weight(.medium)).foregroundStyle(Theme.accent)
                }

                ForEach(model.visibleCards, id: \.key) { card in
                    ReflectionCardView(card: card) { model.dismissCard(card) }
                        .transition(.opacity)
                }
                if let suggestion = model.suggestion {
                    SuggestionCardView(model: model, suggestion: suggestion)
                        .transition(.opacity)
                }
                if let session = pendingReflection {
                    reflectionCard(session)
                        .transition(.opacity)
                }
                statusCard
                actions
                countsRow
                #if DEBUG
                debugSection
                #endif
            }
            .padding(20)
            .animation(.easeInOut(duration: 0.3), value: pendingReflection != nil)
            .animation(.easeInOut(duration: 0.3), value: model.visibleCards.map(\.key))
            .animation(.easeInOut(duration: 0.3), value: model.suggestion)
        }
        .background(Theme.background.ignoresSafeArea())
        .demoBanner(model.mode)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { sheet = .history } label: { Label("履歴", systemImage: "clock") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { sheet = .settings } label: { Label("設定", systemImage: "gearshape") }
            }
        }
        .task(id: model.restriction) {
            // 一時解除中だけ、拡張による再制限を表示に反映するため定期的に再確認する（再制限そのものは拡張が行う）。
            guard case .temporarilyUnlocked = model.restriction else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                model.refresh()
            }
        }
        .onChange(of: model.restriction) { _, _ in model.notice = nil }
        .sheet(item: $sheet) { item in
            sheetContent(item)
                .presentationCornerRadius(32)
                .presentationBackground(Theme.background)
                .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            "制限から外しますか？",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            titleVisibility: .visible,
            presenting: pendingRemoval
        ) { removal in
            Button("制限から外す", role: .destructive) {
                switch removal {
                case .demo: model.removeDemoTarget()
                case .device(let item): model.removeItem(item)
                }
            }
            Button("キャンセル", role: .cancel) {}
        }
    }

    // MARK: 状態

    private var isUnlocked: Bool {
        if case .temporarilyUnlocked = model.restriction { return true }
        return false
    }

    private var needsPermission: Bool {
        model.mode == .device && model.permission != .approved
    }

    /// 画面中央に大きく出す、いまの状態。「ふだんは制限中」が基本の姿。
    private var headline: String {
        if needsPermission { return "許可が必要です" }
        if model.targetCount == 0 { return "制限するものを選びましょう" }
        switch model.restriction {
        case .configured: return "制限中"
        case .temporarilyUnlocked: return "一時的に使えます"
        case .unverifiable: return "状態を確認できません"
        case .off: return "制限はオフです"
        }
    }

    private var subline: String {
        if needsPermission {
            return model.permission == .denied
                ? "iPhoneの設定アプリで、Screen Timeの許可をオンにしてください。"
                : "制限をかけるために、Screen Timeの許可が必要です。"
        }
        if model.targetCount == 0 { return "ふだん開きすぎてしまうアプリやサイトを選びます。" }
        switch model.restriction {
        case .configured: return "ふだんは、選んだものを使えません。使いたいときは、ひと呼吸おいてから。"
        case .temporarilyUnlocked: return "使い終わったら、制限に戻します。"
        case .unverifiable: return "もう一度、制限をオンにしてみてください。"
        case .off: return "ふだんは制限をオンにしておくと、ふと開くのを防げます。"
        }
    }

    private var statusIcon: String {
        if needsPermission { return "hand.raised" }
        if model.targetCount == 0 { return "lock.open" }
        switch model.restriction {
        case .configured: return "lock.fill"
        case .temporarilyUnlocked: return "lock.open.fill"
        case .unverifiable: return "questionmark.circle"
        case .off: return "lock.open"
        }
    }

    /// 状態（大きな錠と一言）・制限しているもの・お知らせを1枚にまとめる。
    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 10) {
                ZStack {
                    Circle().fill(Theme.accent.opacity(0.14)).frame(width: 88, height: 88)
                    Image(systemName: statusIcon)
                        .font(.system(size: 36, weight: .regular))
                        .foregroundStyle(Theme.accent)
                }
                .accessibilityHidden(true)
                Text(headline).font(.title2.weight(.medium))
                Text(subline)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)

            if model.targetCount > 0 {
                Divider()
                appsSection
            }
            if let error = model.permissionError { Text(error).font(.footnote) }
            if let notice = model.notice {
                Text(notice).font(.footnote).padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.softPeach, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .card()
        .animation(.easeInOut(duration: 0.3), value: model.restriction)
        .animation(.easeInOut(duration: 0.3), value: model.targetCount)
    }

    // MARK: 制限するアプリ（右上の＋で追加、各行の－で外す）

    /// 変更できる間（制限オフ・一時解除中）だけ「＋」と「－」を出す。多いときは、この欄の中でスクロールする。
    private var appsSection: some View {
        let editable = !model.isTargetEditLocked
        let rows = appRows(editable: editable)
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("制限しているもの").font(.footnote).foregroundStyle(.secondary)
                Spacer()
                if editable {
                    Button(action: addApps) {
                        Image(systemName: "plus")
                            .font(.title3)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("追加")
                }
            }
            .frame(minHeight: 32)

            if model.targetCount > 4 {
                ScrollView(.vertical, showsIndicators: true) { rows }
                    .frame(height: 4 * 48)
            } else {
                rows
            }
        }
        .animation(.easeInOut(duration: 0.3), value: editable)
    }

    private func appRows(editable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.mode == .demo {
                if let name = model.demo.targetName {
                    appRow(unlocked: false, editable: editable, onRemove: { pendingRemoval = .demo }) { Text(name) }
                }
            } else {
                ForEach(model.device.items.sortedItems) { item in
                    appRow(unlocked: model.unlockedItems.contains(item), editable: editable,
                           onRemove: { pendingRemoval = .device(item) }) { ItemLabel(item: item) }
                }
            }
        }
    }

    /// 1行：名前。解除中のものだけ開いた南京錠。変更できる間だけ目立たない－。
    private func appRow<Content: View>(unlocked: Bool, editable: Bool, onRemove: @escaping () -> Void,
                                       @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            content()
            Spacer()
            if unlocked {
                Image(systemName: "lock.open.fill")
                    .foregroundStyle(Theme.accent)
                    .accessibilityLabel("一時解除中")
            }
            if editable {
                Button(action: onRemove) {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(.tertiary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("制限から外す")
            }
        }
        .frame(minHeight: 48)
    }

    private func addApps() {
        guard !model.isTargetEditLocked else { return }
        model.notice = nil
        sheet = .picker
    }

    // MARK: 操作（主操作は常に1つ）

    private var actions: some View {
        VStack(spacing: 6) {
            if isUnlocked {
                Button("使い終わる") { model.relockNow() }
                    .buttonStyle(FutoButtonStyle())
                Text("押すと、すぐ制限に戻ります。")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                primaryButton
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var primaryButton: some View {
        if needsPermission {
            Button("許可する") { Task { await model.requestPermission() } }
                .buttonStyle(FutoButtonStyle())
        } else if model.targetCount == 0 {
            Button("制限するものを選ぶ") { sheet = .picker }
                .buttonStyle(FutoButtonStyle())
        } else if model.restriction == .configured {
            Button("使う前に、ひと呼吸") { model.beginBreath() }
                .buttonStyle(FutoButtonStyle())
        } else {
            Button("制限をオンにする") { model.startRestriction() }
                .buttonStyle(FutoButtonStyle())
        }
    }

    @ViewBuilder
    private func sheetContent(_ item: HomeSheet) -> some View {
        switch item {
        case .picker:
            if model.mode == .demo { DemoAppPickerView(model: model) } else { DeviceAppPickerView(model: model) }
        case .history:
            NavigationStack {
                RecordsView(mode: model.mode)
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("閉じる") { sheet = nil } } }
            }
            .demoBanner(model.mode)
        case .settings:
            NavigationStack {
                SettingsView(model: model)
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("閉じる") { sheet = nil } } }
            }
            .demoBanner(model.mode)
        case .todayDeferred, .todayWants:
            NavigationStack {
                TodayDetailView(mode: model.mode, kind: item == .todayDeferred ? .deferred : .wantsToUse)
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("閉じる") { sheet = nil } } }
            }
            .demoBanner(model.mode)
        }
    }

    // MARK: 一時解除のあとの感想

    /// 一時解除が終わり（再制限され）、まだ感想を尋ねていない直近のSession。
    private var pendingReflection: Session? {
        guard !isUnlocked else { return nil }
        return sessions.first {
            $0.mode == model.mode && $0.phase == .completed
                && $0.temporaryUnlockStartedAt != nil && $0.reflection == nil
        }
    }

    private func reflectionCard(_ session: Session) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("さっきの時間は、どうでしたか？").font(.headline.weight(.medium))
            Text("答えなくても大丈夫です。")
                .font(.footnote).foregroundStyle(.secondary)
            ForEach([Reflection.satisfied, .neutral, .wishedLess], id: \.self) { reflection in
                Button(reflection.label) { model.answerReflection(session, reflection) }
                    .buttonStyle(FutoButtonStyle(prominent: false))
            }
            Button("答えない") { model.answerReflection(session, .skipped) }
                .buttonStyle(FutoTextButtonStyle())
        }
        .card(tint: Theme.softBlue)
    }

    // MARK: やめた／使いたかった（小さなボタン。押すと今日の中身）

    private var countsRow: some View {
        let counts = DailyCounts.today(sessions: sessions, mode: model.mode)
        return HStack(spacing: 8) {
            countChip("やめた", counts.deferred, .todayDeferred)
            countChip("使いたかった", counts.wantsToUse, .todayWants)
            Spacer()
        }
    }

    private func countChip(_ title: String, _ value: Int, _ target: HomeSheet) -> some View {
        Button { sheet = target } label: {
            HStack(spacing: 6) {
                Text(title)
                Text("\(value)").monospacedDigit().foregroundStyle(.primary)
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .frame(minHeight: 36)
            .background(Capsule().fill(Theme.accent.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("今日の記録を開きます")
    }

    #if DEBUG
    /// 開発用：朝夜の振り返りと通知を、時間を待たずに確かめる（Debugビルドにだけ存在する）。
    private var debugSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("開発用（Debugのみ）").font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 8) {
                Button("朝の振り返り") { model.showReflectionNow(.morning) }
                Button("夜の振り返り") { model.showReflectionNow(.night) }
                Button("お出かけ通知") { model.sendTestNotification(.outing) }
            }
            .buttonStyle(FutoCompactButtonStyle())
        }
        .padding(.top, 12)
    }
    #endif
}
