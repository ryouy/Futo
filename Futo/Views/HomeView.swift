import FamilyControls
import ManagedSettings
import SwiftData
import SwiftUI

@MainActor
struct HomeView: View {
    @Bindable var model: AppModel
    @Environment(SharingModel.self) private var sharing
    @State private var sheet: HomeSheet?

    private enum HomeSheet: Identifiable {
        case history, settings, picker
        var id: Self { self }
    }

    /// 上は、状態と制限するものの一覧（多いときは自然に上下へスクロール）。
    /// 操作ボタンは下に固定して、一覧が長くても、いつでも押せる。
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                scrollContent
                    .padding(.top, 12)
            }
            .scrollBounceBehavior(.basedOnSize)
            // 一覧の下端は、カードの角に合わせて丸く切る（急に切れて見えないように）。下のボタンとの間は、あける。
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 26, bottomTrailingRadius: 26, topTrailingRadius: 0, style: .continuous))
            .padding(.horizontal, 20)
            VStack(spacing: 12) {
                actions
                #if DEBUG
                debugSection
                #endif
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)
        }
        .background(Theme.background.ignoresSafeArea())
        .demoBanner(model.mode)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: model.restriction) {
            // 一時解除中だけ、拡張による再制限を表示に反映するため定期的に再確認する（再制限そのものは拡張が行う）。
            // 一時解除中・一時停止中だけ、拡張による再制限を表示に反映するため定期的に再確認する。
            switch model.restriction {
            case .temporarilyUnlocked, .paused: break
            default: return
            }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                model.refresh()
            }
        }
        .onChange(of: model.restriction) { _, _ in model.notice = nil }
        .sheet(item: $sheet) { item in
            sheetContent(item)
                .foregroundStyle(Theme.text)
                .environment(\.locale, LanguageStore.shared.language.locale)
                .presentationCornerRadius(32)
                .presentationBackground(Theme.background)
                .presentationDragIndicator(.visible)
        }
    }

    private var scrollContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Text(tr("ふと")).font(.title3.weight(.medium)).foregroundStyle(Theme.accent)
                Spacer()
                HStack(spacing: 0) {
                    Button { sheet = .history } label: {
                        Image(systemName: "clock").font(.title3).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(tr("記録"))
                    Button { sheet = .settings } label: {
                        if sharing.isSignedIn, let name = sharing.profile?.displayName {
                            // ログイン中は、アカウントのアイコンで分かるようにする。小さな歯車で、押すと設定を開けると伝える
                            AccountAvatar(name: name, photoURL: sharing.auth.photoURL, size: 30, isOwn: true)
                                .overlay(alignment: .bottomTrailing) {
                                    Image(systemName: "gearshape.fill")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(Theme.onAccent)
                                        .frame(width: 15, height: 15)
                                        .background(Circle().fill(Theme.accent))
                                        .overlay(Circle().stroke(Color(uiColor: .systemBackground), lineWidth: 1.5))
                                        .offset(x: 4, y: 4)
                                }
                                .frame(width: 44, height: 44)
                        } else {
                            Image(systemName: "gearshape").font(.title3).frame(width: 44, height: 44)
                        }
                    }
                    .accessibilityLabel(tr("設定とアカウント"))
                }
                .foregroundStyle(Theme.accent)
                .tutorialTarget(.header)
            }

            if let suggestion = model.suggestion {
                SuggestionCardView(model: model, suggestion: suggestion)
                    .transition(.opacity)
            }
            statusCard
        }
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
        if needsPermission { return tr("許可が必要です") }
        if model.targetCount == 0 { return tr("制限するものを選びましょう") }
        switch model.restriction {
        case .configured: return tr("制限中")
        case .temporarilyUnlocked: return tr("一時的に使えます")
        case .paused: return tr("制限を一時停止中")
        case .unverifiable: return tr("状態を確認できません")
        case .off: return tr("制限していません")
        }
    }

    private var subline: String {
        if needsPermission {
            return model.permission == .denied
                ? tr("設定アプリで許可をオンにしてください。")
                : tr("Screen Timeの許可が必要です。")
        }
        if model.targetCount == 0 { return tr("アプリやサイトを選びます。") }
        switch model.restriction {
        case .configured: return tr("選んだものは、ふだん使えません。")
        case .temporarilyUnlocked: return tr("終わったら、制限に戻します。")
        case .paused(let until): return tr("{0} に、自動で戻ります。", until.formatted(date: .omitted, time: .shortened))
        case .unverifiable: return tr("もう一度、かけ直してください。")
        case .off: return tr("かけておくのがおすすめです。")
        }
    }

    private var statusIcon: String {
        if needsPermission { return "hand.raised" }
        if model.targetCount == 0 { return "lock.open" }
        switch model.restriction {
        case .configured: return "lock.fill"
        case .temporarilyUnlocked: return "lock.open.fill"
        case .paused: return "pause.circle"
        case .unverifiable: return "questionmark.circle"
        case .off: return "lock.open"
        }
    }

    /// 状態（小さな錠と一言、右端に＋）・制限しているもの・お知らせを1枚にまとめる。
    private var statusCard: some View {
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
                    .accessibilityLabel(tr("追加"))
                    .tutorialTarget(.plus)
                    .transition(.opacity)
                }
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
        .tutorialTarget(.status)
        .animation(.easeInOut(duration: 0.3), value: model.restriction)
        .animation(.easeInOut(duration: 0.3), value: model.targetCount)
    }

    // MARK: 制限するもの（状態の行の右端の＋で追加、各行の－で外す）

    /// 変更できる間（制限オフ）だけ、各行にゴミ箱を出す。多いときは、ホーム全体が自然にスクロールする。
    private var appsSection: some View {
        let editable = !model.isTargetEditLocked
        return VStack(alignment: .leading, spacing: 0) {
            appRows(editable: editable)
            if editable {
                Text(tr("ゴミ箱は、制限の対象から外すだけです。アプリは削除されません。"))
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.top, 6)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: editable)
    }

    private func appRows(editable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.mode == .demo {
                if let name = model.demo.targetName {
                    appRow(unlocked: false, editable: editable, onRemove: { model.removeDemoTarget() }) { Text(tr(name)) }
                }
            } else {
                ForEach(model.device.items.sortedItems) { item in
                    appRow(unlocked: model.unlockedItems.contains(item), editable: editable,
                           onRemove: { model.removeItem(item) }) { ItemLabel(item: item) }
                }
            }
        }
    }

    /// 1行：名前。解除中のものだけ開いた南京錠。変更できる間だけ、制限の対象から外すゴミ箱。
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
                        .accessibilityLabel(tr("一時解除中"))
                }
                if editable {
                    Button(action: onRemove) {
                        Image(systemName: "trash")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                    }
                    // 名前はOSが描画するラベルなので文字列として取れない。隣の名前と続けて読まれる。
                    .accessibilityLabel(tr("制限の対象から外す（アプリは削除されません）"))
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
        if model.isPaused {
            Button(tr("制限を再開する")) { model.resumeRestriction() }
                .buttonStyle(FutoButtonStyle())
        } else if isUnlocked {
            Button(tr("使い終わる")) { model.relockNow() }
                .buttonStyle(FutoButtonStyle())
        } else if needsPermission {
            Button(tr("許可する")) { Task { await model.requestPermission() } }
                .buttonStyle(FutoButtonStyle())
        } else if model.targetCount == 0 {
            Button(tr("制限するものを選ぶ")) { sheet = .picker }
                .buttonStyle(FutoButtonStyle())
        } else if model.restriction == .configured {
            Button(tr("ひと呼吸おいて、使う")) { model.beginBreath() }
                .buttonStyle(FutoButtonStyle(prominent: false))
        } else if model.restriction == .unverifiable {
            Button(tr("制限をかけ直す")) { model.startRestriction() }
                .buttonStyle(FutoButtonStyle())
        } else {
            Button(tr("制限をかける")) { model.startRestriction() }
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
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(tr("閉じる")) { sheet = nil } } }
            }
            .demoBanner(model.mode)
        case .settings:
            NavigationStack {
                SettingsView(model: model)
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(tr("閉じる")) { sheet = nil } } }
            }
            .demoBanner(model.mode)
        }
    }

    #if DEBUG
    /// 開発用：朝夜の振り返り・通知・制限の解除を、時間を待たずに確かめる（Debugビルドにだけ存在する）。1列に並べる。
    private var debugSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("開発用（Debugのみ）")).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button(tr("朝の振り返り")) { model.showReflectionNow(.morning) }
                Button(tr("夜の振り返り")) { model.showReflectionNow(.night) }
                Button(tr("お出かけ通知")) { model.sendTestNotification(.outing) }
                // 待機を省略して、本アプリの制限をすぐ解除する（記録には数えない）。
                Button("制限解除") { model.debugReleaseRestrictionNow() }
                    .tint(.orange)
            }
            .buttonStyle(FutoCompactButtonStyle())
        }
        .padding(.top, 4)
    }
    #endif
}
