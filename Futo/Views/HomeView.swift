import FamilyControls
import ManagedSettings
import SwiftData
import SwiftUI

@MainActor
struct HomeView: View {
    @Bindable var model: AppModel
    @Query(sort: \Session.startedAt, order: .reverse) private var sessions: [Session]
    @State private var sheet: HomeSheet?
    @State private var confirmStop = false
    @State private var pendingRemoval: Removal?

    private enum HomeSheet: Identifiable {
        case history, settings, picker
        var id: Self { self }
    }

    private enum Removal: Identifiable {
        case demo
        case device(ApplicationToken)
        var id: String {
            switch self {
            case .demo: return "demo"
            case .device(let token): return "device-\(token.hashValue)"
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
                countsLine
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
            "選んだアプリの制限を終了しますか？ この試作では、自動で再開されません。",
            isPresented: $confirmStop, titleVisibility: .visible
        ) {
            Button("制限を終了", role: .destructive) { model.stopRestriction() }
            Button("キャンセル", role: .cancel) {}
        }
        .confirmationDialog(
            "このアプリを制限から外しますか？",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            titleVisibility: .visible,
            presenting: pendingRemoval
        ) { removal in
            Button("制限から外す", role: .destructive) {
                switch removal {
                case .demo: model.removeDemoTarget()
                case .device(let token): model.removeApp(token)
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

    private var statusText: String {
        if needsPermission {
            return model.permission == .denied ? "許可が必要です。設定アプリで変更できます。" : "許可が必要です"
        }
        if model.targetCount == 0 { return "制限するアプリを選んでください" }
        switch model.restriction {
        case .configured: return "制限中です"
        case .temporarilyUnlocked:
            return "一時的に使えます"
        case .unverifiable: return "状態を確認できませんでした。もう一度お試しください"
        case .off: return "制限はオフです"
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

    /// 状態・制限するアプリ・お知らせを1枚にまとめる。
    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: statusIcon)
                    .font(.title2)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 32)
                    .accessibilityHidden(true)
                Text(statusText).lineSpacing(4)
            }

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

    /// 変更できる間（制限オフ・一時解除中）は淡い面で包んで＋と－を出し、制限中は南京錠だけにする。
    private var appsSection: some View {
        let editable = !model.isTargetEditLocked
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("制限するアプリ").font(.footnote).foregroundStyle(.secondary)
                Spacer()
                if editable {
                    Button(action: addApps) {
                        Image(systemName: "plus")
                            .font(.title3)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("アプリを追加")
                } else {
                    Button(action: explainLock) {
                        Image(systemName: "lock.fill")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("制限中は変更できません")
                }
            }
            if model.mode == .demo {
                if let name = model.demo.targetName {
                    appRow(unlocked: false, editable: editable, onRemove: { pendingRemoval = .demo }) { Text(name) }
                }
            } else {
                ForEach(sortedTokens, id: \.self) { token in
                    appRow(unlocked: model.unlockedApps.contains(token), editable: editable,
                           onRemove: { pendingRemoval = .device(token) }) { Label(token) }
                        .transition(.opacity)
                }
            }
        }
        .padding(.horizontal, editable ? 12 : 0)
        .padding(.bottom, editable ? 4 : 0)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(editable ? Theme.accent.opacity(0.10) : Color.clear)
        )
        .animation(.easeInOut(duration: 0.3), value: editable)
        .animation(.easeInOut(duration: 0.3), value: sortedTokens.count)
    }

    private var sortedTokens: [ApplicationToken] {
        model.device.selection.applicationTokens.sorted { $0.hashValue < $1.hashValue }
    }

    /// 1行：アプリ名、南京錠（施錠／解除中）、変更できる間だけ目立たない－。
    private func appRow<Content: View>(unlocked: Bool, editable: Bool, onRemove: @escaping () -> Void,
                                       @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            content()
            Spacer()
            Image(systemName: unlocked ? "lock.open.fill" : "lock.fill")
                .foregroundStyle(unlocked ? Theme.accent : Color.secondary)
                .accessibilityLabel(unlocked ? "一時解除中" : "制限中")
            if editable {
                Button(action: onRemove) {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(.tertiary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("制限から外す")
            }
        }
        .frame(minHeight: 44)
    }

    private func addApps() {
        guard !model.isTargetEditLocked else { return explainLock() }
        model.notice = nil
        sheet = .picker
    }

    private func explainLock() {
        model.notice = "制限を解除している間だけ、変更できます。"
    }

    // MARK: 操作（主操作は常に1つ）

    private var actions: some View {
        VStack(spacing: 4) {
            if isUnlocked {
                Button("制限に戻す") { model.relockNow() }
                    .buttonStyle(FutoButtonStyle())
            } else if model.activeSession != nil {
                Button("ひと呼吸を続ける") { model.resumeBreath() }
                    .buttonStyle(FutoButtonStyle())
                Button("ひと呼吸をやめる") { model.endBreath() }
                    .buttonStyle(FutoTextButtonStyle())
            } else {
                primaryButton
            }
            if model.intendsRestriction {
                Button("制限を終了") { confirmStop = true }
                    .buttonStyle(FutoTextButtonStyle())
            }
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        if needsPermission {
            Button("許可する") { Task { await model.requestPermission() } }
                .buttonStyle(FutoButtonStyle())
        } else if model.targetCount == 0 {
            Button("アプリを選ぶ") { sheet = .picker }
                .buttonStyle(FutoButtonStyle())
        } else if model.restriction == .configured {
            Button("使う前に、ひと呼吸") { model.beginBreath() }
                .buttonStyle(FutoButtonStyle())
        } else {
            Button("制限を始める") { model.startRestriction() }
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

    // MARK: 今日の記録（控えめに1行）

    private var countsLine: some View {
        let counts = DailyCounts.today(sessions: sessions, mode: model.mode)
        return HStack {
            Text("今日やめた \(counts.deferred)")
            Spacer()
            Text("今日使いたかった \(counts.wantsToUse)")
        }
        .font(.footnote.monospacedDigit())
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }

    #if DEBUG
    /// 開発用：朝夜の振り返りと通知を、時間を待たずに確かめる（Debugビルドにだけ存在する）。
    private var debugSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("開発用（Debugのみ）").font(.caption).foregroundStyle(.secondary)
            Button("朝の振り返りをいま見る") { model.showReflectionNow(.morning) }
                .buttonStyle(FutoButtonStyle(prominent: false))
            Button("夜の振り返りをいま見る") { model.showReflectionNow(.night) }
                .buttonStyle(FutoButtonStyle(prominent: false))
            Button("お出かけ通知を3秒後に送る") { model.sendTestNotification(.outing) }
                .buttonStyle(FutoButtonStyle(prominent: false))
        }
        .padding(.top, 12)
    }
    #endif
}
