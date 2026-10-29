import FamilyControls
import ManagedSettings
import SwiftData
import SwiftUI

@MainActor
struct HomeView: View {
    @Bindable var model: AppModel
    @Query(sort: \Session.startedAt, order: .reverse) private var sessions: [Session]
    @State private var showPicker = false
    @State private var confirmStop = false
    @State private var pendingRemoval: Removal?

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

                if let session = pendingReflection { reflectionCard(session) }
                statusCard
                actions
                countsLine
            }
            .padding(20)
        }
        .background(Theme.background.ignoresSafeArea())
        .demoBanner(model.mode)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { HistoryView(mode: model.mode).demoBanner(model.mode) } label: {
                    Label("履歴", systemImage: "clock")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { SettingsView(model: model).demoBanner(model.mode) } label: {
                    Label("設定", systemImage: "gearshape")
                }
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
        .sheet(isPresented: $showPicker) { picker }
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
        case .temporarilyUnlocked(let until):
            return "いま一時的に使えます。約\(SharedState.unlockUsageMinutes)分使うか、\(until.formatted(date: .omitted, time: .shortened))になると、制限に戻ります。"
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
    }

    // MARK: 制限するアプリ（右上の＋で追加、各行の－で外す）

    private var appsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("制限するアプリ").font(.footnote).foregroundStyle(.secondary)
                Spacer()
                Button(action: addApps) {
                    Image(systemName: "plus")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("アプリを追加")
            }
            if model.mode == .demo {
                if let name = model.demo.targetName {
                    appRow(unlocked: false, onRemove: { requestRemoval(.demo) }) { Text(name) }
                }
            } else {
                ForEach(sortedTokens, id: \.self) { token in
                    appRow(unlocked: model.unlockedApps.contains(token),
                           onRemove: { requestRemoval(.device(token)) }) { Label(token) }
                }
            }
        }
    }

    private var sortedTokens: [ApplicationToken] {
        model.device.selection.applicationTokens.sorted { $0.hashValue < $1.hashValue }
    }

    /// 1行：アプリ名、南京錠（施錠／解除中）、目立たない－。
    private func appRow<Content: View>(unlocked: Bool, onRemove: @escaping () -> Void,
                                       @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            content()
            Spacer()
            if unlocked {
                Text("解除中").font(.caption).foregroundStyle(Theme.accent)
            }
            Image(systemName: unlocked ? "lock.open.fill" : "lock.fill")
                .foregroundStyle(unlocked ? Theme.accent : Color.secondary)
                .accessibilityLabel(unlocked ? "一時解除中" : "制限中")
            Button(action: onRemove) {
                Image(systemName: "minus.circle")
                    .foregroundStyle(.tertiary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("制限から外す")
        }
        .frame(minHeight: 44)
    }

    private func addApps() {
        if model.isTargetEditLocked {
            model.notice = "一時解除が終わってから変更してください。"
        } else {
            model.notice = nil
            showPicker = true
        }
    }

    private func requestRemoval(_ removal: Removal) {
        if model.isTargetEditLocked {
            model.notice = "一時解除が終わってから変更してください。"
        } else {
            pendingRemoval = removal
        }
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
            Button("アプリを選ぶ") { showPicker = true }
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
    private var picker: some View {
        if model.mode == .demo {
            DemoAppPickerView(model: model)
        } else {
            DeviceAppPickerView(model: model)
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
}
