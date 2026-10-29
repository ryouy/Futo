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
        case history, settings, picker
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

    /// ホームは1画面に収める。通常は上下にスクロールしない。
    /// 朝夜のカードなどが加わって、どうしても収まらないときだけ、全体をスクロールできるようにする。
    var body: some View {
        GeometryReader { geo in
            let rows = visibleRows(forHeight: geo.size.height)
            ViewThatFits(in: .vertical) {
                mainContent(rows: rows)
                ScrollView { mainContent(rows: rows) }
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .demoBanner(model.mode)
        .toolbar(.hidden, for: .navigationBar)
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
                .foregroundStyle(Theme.text)
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

    /// 余裕があるときは、制限するものを多めに（最大8件）見せる。足りなければ3件まで減らす。
    private func visibleRows(forHeight height: CGFloat) -> Int {
        var reserved: CGFloat = 270
        #if DEBUG
        reserved += 80
        #endif
        if model.suggestion != nil || pendingReflection != nil { return 3 }
        return max(3, min(8, Int((height - reserved) / 48)))
    }

    private func mainContent(rows: Int) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Text("ふと").font(.title3.weight(.medium)).foregroundStyle(Theme.accent)
                Spacer()
                HStack(spacing: 0) {
                    Button { sheet = .history } label: {
                        Image(systemName: "clock").font(.title3).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("記録")
                    Button { sheet = .settings } label: {
                        Image(systemName: "gearshape").font(.title3).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("設定")
                }
                .foregroundStyle(Theme.accent)
                .tutorialTarget(.header)
            }

            if let suggestion = model.suggestion {
                SuggestionCardView(model: model, suggestion: suggestion)
                    .transition(.opacity)
            }
            if let session = pendingReflection {
                reflectionCard(session)
                    .transition(.opacity)
            }
            statusCard(rows: rows)
            actions
            Spacer(minLength: 0)
            #if DEBUG
            debugSection
            #endif
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .animation(.easeInOut(duration: 0.3), value: pendingReflection != nil)
        .animation(.easeInOut(duration: 0.3), value: model.suggestion)
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
        case .off: return "制限していません"
        }
    }

    private var subline: String {
        if needsPermission {
            return model.permission == .denied
                ? "設定アプリで許可をオンにしてください。"
                : "Screen Timeの許可が必要です。"
        }
        if model.targetCount == 0 { return "アプリやサイトを選びます。" }
        switch model.restriction {
        case .configured: return "選んだものは、ふだん使えません。"
        case .temporarilyUnlocked: return "終わったら、制限に戻します。"
        case .unverifiable: return "もう一度、かけ直してください。"
        case .off: return "かけておくのがおすすめです。"
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

    /// 状態（小さな錠と一言、右端に＋）・制限しているもの・お知らせを1枚にまとめる。
    private func statusCard(rows: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Theme.accent.opacity(0.14)).frame(width: 40, height: 40)
                    Image(systemName: statusIcon)
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(Theme.accent)
                }
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline).font(.headline.weight(.medium)).oneLine()
                    Text(subline).font(.footnote).foregroundStyle(.secondary).oneLine(0.8)
                }
                Spacer(minLength: 0)
                if model.targetCount > 0, model.canAddItems {
                    Button(action: addApps) {
                        Image(systemName: "plus")
                            .font(.body.weight(.medium))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(Theme.accent.opacity(0.14)))
                    }
                    .accessibilityLabel("追加")
                    .tutorialTarget(.plus)
                    .transition(.opacity)
                }
            }

            if model.targetCount > 0 {
                Divider()
                appsSection(rows: rows)
            }
            if let error = model.permissionError { Text(error).font(.footnote) }
            if let notice = model.notice {
                Text(notice).font(.footnote).padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.softPeach, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .card()
        .tutorialTarget(.status)
        .animation(.easeInOut(duration: 0.3), value: model.restriction)
        .animation(.easeInOut(duration: 0.3), value: model.targetCount)
    }

    // MARK: 制限するもの（状態の行の右端の＋で追加、各行の－で外す）

    /// 変更できる間（制限オフ・一時解除中）だけ「＋」と「－」を出す。多いときは、この欄の中でスクロールする。
    private func appsSection(rows maxRows: Int) -> some View {
        let editable = !model.isTargetEditLocked
        let rows = appRows(editable: editable)
        return VStack(alignment: .leading, spacing: 0) {
            if model.targetCount > maxRows {
                // 最後の行を半分だけ見せ、下端をぼかして、下にまだあることを伝える。
                ScrollHintList(height: (CGFloat(maxRows) - 0.5) * 48) { rows }
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
        // 右側（解除中の錠・－）の幅を決め、名前はそのぶん引いた幅に収める。
        let trailing: CGFloat = (unlocked ? 28 : 0) + (editable ? 44 : 0)
        return FixedWidthRow(height: 48, trailingWidth: trailing) {
            content()
                .lineLimit(1)
                .truncationMode(.tail)
        } trailing: {
            HStack(spacing: 4) {
                if unlocked {
                    Image(systemName: "lock.open.fill")
                        .foregroundStyle(Theme.accent)
                        .frame(width: 24)
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
        }
    }

    private func addApps() {
        guard model.canAddItems else { return }
        model.notice = nil
        sheet = .picker
    }

    // MARK: 操作（主操作は常に1つ）

    /// 主操作は常に1つで、状態のカードの真下に置く。
    /// 制限を強める操作（かける・使い終わる）は濃い色、緩める入口（ひと呼吸おいて使う）は薄い色にして、
    /// 「ふだんは制限中」を基本にしたこのアプリで、解除を前面に出しすぎない。
    private var actions: some View {
        VStack(spacing: 6) {
            primaryButton
        }
        .frame(maxWidth: .infinity)
        .tutorialTarget(.main)
    }

    @ViewBuilder
    private var primaryButton: some View {
        if isUnlocked {
            Button("使い終わる") { model.relockNow() }
                .buttonStyle(FutoButtonStyle())
        } else if needsPermission {
            Button("許可する") { Task { await model.requestPermission() } }
                .buttonStyle(FutoButtonStyle())
        } else if model.targetCount == 0 {
            Button("制限するものを選ぶ") { sheet = .picker }
                .buttonStyle(FutoButtonStyle())
        } else if model.restriction == .configured {
            Button("ひと呼吸おいて、使う") { model.beginBreath() }
                .buttonStyle(FutoButtonStyle(prominent: false))
        } else if model.restriction == .unverifiable {
            Button("制限をかけ直す") { model.startRestriction() }
                .buttonStyle(FutoButtonStyle())
        } else {
            Button("制限をかける") { model.startRestriction() }
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

private struct ScrollBottomKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// 高さを固定した縦スクロール。下にまだ続くときだけ、下端のぼかしと矢印で「スクロールできる」ことを伝える。
private struct ScrollHintList<Content: View>: View {
    let height: CGFloat
    @ViewBuilder var content: Content
    @State private var atBottom = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 0) {
                content
                Color.clear
                    .frame(height: 1)
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: ScrollBottomKey.self, value: proxy.frame(in: .named("scrollHintList")).maxY)
                    })
            }
        }
        .coordinateSpace(name: "scrollHintList")
        .onPreferenceChange(ScrollBottomKey.self) { atBottom = $0 <= height + 2 }
        .frame(height: height)
        .overlay(alignment: .bottom) {
            ZStack(alignment: .bottom) {
                LinearGradient(colors: [Theme.card.opacity(0), Theme.card], startPoint: .top, endPoint: .bottom)
                    .frame(height: 36)
                Image(systemName: "chevron.compact.down")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 2)
            }
            .opacity(atBottom ? 0 : 1)
            .animation(.easeInOut(duration: 0.2), value: atBottom)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
