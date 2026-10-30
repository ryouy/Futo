import FamilyControls
import ManagedSettings
import SwiftData
import SwiftUI

@MainActor
struct HomeView: View {
    @Bindable var model: AppModel
    @Environment(SharingModel.self) private var sharing
    @State private var sheet: HomeSheet?
    @State private var lockSeal = false
    @State private var lockSealUnlocking = false
    @State private var lockSealTask: Task<Void, Never>?

    private enum HomeSheet: Identifiable {
        case history, settings, picker
        var id: Self { self }
    }

    /// ホームは、画面全体をスクロールさせない。制限するものが多いときは、一覧の欄の中だけでスクロールする。
    /// 文字を大きくするなどで、どうしても収まらないときだけ、全体をスクロールできるようにする。
    var body: some View {
        GeometryReader { geo in
            let rows = visibleRows(forHeight: geo.size.height)
            ViewThatFits(in: .vertical) {
                page(rows: rows)
                ScrollView { page(rows: rows) }
            }
        }
        .background(Theme.background.ignoresSafeArea())
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
        // 制限がかかったとき（手動・一時解除や一時停止からの復帰）、鍵のアニメーションを見せる（合図は、AppModelが出す）
        .onChange(of: model.lockSealToken) { _, _ in showLockSeal() }
        .onChange(of: sheet) { _, value in model.homeSheetOpen = value != nil }
        .onDisappear {
            lockSealTask?.cancel()
            model.lockSealActive = false
        }
        .overlay {
            if lockSeal {
                LockSealView(unlocking: lockSealUnlocking)
                    .id(model.lockSealToken)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }        .sheet(item: $sheet) { item in
            sheetContent(item)
                .foregroundStyle(Theme.text)
                .environment(\.locale, LanguageStore.shared.language.locale)
                .presentationCornerRadius(32)
                .presentationBackground(Theme.background)
                .presentationDragIndicator(.visible)
        }
    }

    /// 画面の高さに合わせて、制限するものを何件まで丸ごと見せるか。多いときは、その次の1件を、下の1/3ほど見切れさせる。
    private func visibleRows(forHeight height: CGFloat) -> Int {
        var reserved: CGFloat = 300
        #if DEBUG
        reserved += 50
        #endif
        // 提案のカードが出ているときは、その分、一覧を短くする
        if model.suggestion != nil { reserved += 210 }
        return max(2, min(8, Int((height - reserved) / Self.rowHeight)))
    }

    private static let rowHeight: CGFloat = 48

    private func page(rows: Int) -> some View {
        VStack(spacing: 0) {
            scrollContent(rows: rows)
                .padding(.horizontal, 20)
                .padding(.top, 12)
            Spacer(minLength: 12)
            VStack(spacing: 12) {
                actions
                #if DEBUG
                debugSection
                #endif
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 12)
        }
    }

    private func scrollContent(rows: Int) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Text(tr("ふと")).font(.title2.weight(.bold)).foregroundStyle(Theme.accentText)
                Spacer()
                HStack(spacing: 0) {
                    Button { sheet = .history } label: {
                        Image(systemName: "note.text").font(.title3).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(tr("記録"))
                    Button { sheet = .settings } label: {
                        if sharing.isSignedIn, let name = sharing.profile?.displayName {
                            // ログイン中は、アカウントのアイコンで分かるようにする
                            AccountAvatar(name: name, size: 30, isOwn: true)
                                .overlay(alignment: .topTrailing) {
                                    // フレンドから新しい記録が届いているとき
                                    if sharing.hasUnseenRecords { NewBadge().offset(x: 3, y: -3) }
                                }
                                .frame(width: 44, height: 44)
                        } else {
                            Image(systemName: "gearshape").font(.title3).frame(width: 44, height: 44)
                        }
                    }
                    .accessibilityLabel(tr("設定とアカウント"))
                }
                .foregroundStyle(Theme.accentText)
                .tutorialTarget(.header)
            }

            if let suggestion = model.suggestion {
                SuggestionCardView(model: model, suggestion: suggestion)
                    .transition(.opacity)
            }
            statusCard(rows: rows)
        }
        .animation(.easeInOut(duration: 0.3), value: model.suggestion)
    }

    /// 鍵が閉まるアニメーションを、少しの間だけ大きく見せる（約2秒）。
    private func showLockSeal() {
        lockSealTask?.cancel()
        model.lockSealActive = true
        lockSealUnlocking = model.lockSealUnlocking
        withAnimation(.easeOut(duration: 0.25)) { lockSeal = true }
        lockSealTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.0))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.45)) { lockSeal = false }
            // 消えきってから、待たせていた画面（感想など）を出す
            try? await Task.sleep(for: .milliseconds(450))
            model.lockSealActive = false
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
        case .configured: return tr("")
        case .temporarilyUnlocked: return ""
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
    private func statusCard(rows: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Theme.accent.opacity(0.14)).frame(width: 40, height: 40)
                    Image(systemName: statusIcon)
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(Theme.accentText)
                }
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline).font(.headline.weight(.medium)).oneLine()
                    if !subline.isEmpty { Text(subline).font(.footnote).foregroundStyle(.secondary).oneLine(0.8) }
                }
                Spacer(minLength: 0)
                if model.targetCount > 0, model.canAddItems {
                    Button(action: addApps) {
                        Image(systemName: "plus")
                            .font(.body.weight(.medium))
                            .foregroundStyle(Theme.accentText)
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

    /// 変更できる間（制限オフ）だけ、各行にゴミ箱を出す。
    /// 多いときは、この欄の中でスクロールできる。最後に見える1件は、下の1/3ほどを見切れさせ、ぼかして、続きがあると伝える。
    private func appsSection(rows maxRows: Int) -> some View {
        let editable = !model.isTargetEditLocked
        return VStack(alignment: .leading, spacing: 0) {
            if model.targetCount > maxRows {
                ScrollView(.vertical, showsIndicators: false) {
                    appRows(editable: editable)
                }
                .frame(height: (CGFloat(maxRows) + 0.67) * Self.rowHeight)
                .mask(
                    VStack(spacing: 0) {
                        Rectangle()
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 44)
                    }
                )
            } else {
                appRows(editable: editable)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: editable)
    }

    private func appRows(editable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            do {
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
                        .foregroundStyle(Theme.accentText)
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
                .buttonStyle(FutoButtonStyle(prominent: false, bordered: true))
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
            DeviceAppPickerView(model: model)
        case .history:
            NavigationStack {
                RecordsView(mode: model.mode)
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(tr("閉じる")) { sheet = nil } } }
            }
            case .settings:
            NavigationStack {
                SettingsView(model: model)
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(tr("閉じる")) { sheet = nil } } }
            }
            }
    }

    #if DEBUG
    /// 開発用：朝夜の振り返り・通知・制限の解除を、時間を待たずに確かめる（Debugビルドにだけ存在する）。1列に並べる。
    private var debugSection: some View {
        VStack(alignment: .leading, spacing: 8) {
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

/// 錠前のつる（開いているときは、持ち上がって傾く）。
private struct ShackleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height, r = w / 2, k: CGFloat = 0.5523
        var path = Path()
        path.move(to: CGPoint(x: 0, y: h))
        path.addLine(to: CGPoint(x: 0, y: r))
        path.addCurve(to: CGPoint(x: r, y: 0), control1: CGPoint(x: 0, y: r - k * r), control2: CGPoint(x: r - k * r, y: 0))
        path.addCurve(to: CGPoint(x: w, y: r), control1: CGPoint(x: r + k * r, y: 0), control2: CGPoint(x: w, y: r - k * r))
        path.addLine(to: CGPoint(x: w, y: h - 14))   // 右の脚は短い（開くと本体から抜ける）
        return path
    }
}

/// 描いた錠前。`progress` が 0 で開き、1 で閉じる。値を連続して動かすので、開いた鍵が、途切れずに閉じる。
private struct PadlockDrawing: View, Animatable {
    var progress: CGFloat
    var color: Color
    var keyColor: Color
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let open = 1 - progress
        // 南京錠。開いているときは、輪が少し持ち上がり、左の脚だけが本体に刺さったまま。閉じるときは、そこから真上から降りてくる。
        ZStack(alignment: .top) {
            ShackleShape()
                .stroke(color, style: StrokeStyle(lineWidth: 11, lineCap: .round))
                .frame(width: 50, height: 62)
                .offset(y: -15 * open)
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(color)
                .frame(width: 84, height: 62)
                .overlay {
                    VStack(spacing: 0) {
                        Circle().fill(keyColor).frame(width: 12, height: 12)
                        Capsule().fill(keyColor).frame(width: 5, height: 14).offset(y: -2)
                    }
                }
                .offset(y: 40)
        }
        .frame(width: 84, height: 102, alignment: .top)
    }
}

/// 制限がかかったときの、鍵のアニメーション。
/// 色の円の中で、開いた鍵が「カチッ」と閉まり（軽い振動つき）、輪が広がって、「制限しました」と出る。
/// 視差効果を減らす設定では、閉じた鍵と文字を、ふわっと出すだけ。
private struct LockSealView: View {
    /// true なら、制限が外れたときの、鍵が開くアニメーション
    var unlocking = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    @State private var progress: CGFloat
    @State private var squash = false
    @State private var ripple = false
    @State private var labelShown = false

    init(unlocking: Bool = false) {
        self.unlocking = unlocking
        _progress = State(initialValue: unlocking ? 1 : 0)
    }

    var body: some View {
        ZStack {
            // 後ろを、うっすらぼかす（鍵と「制限しました」が見分けやすく、後ろの画面も、少し見える）
            Rectangle().fill(.regularMaterial).ignoresSafeArea()
                .opacity(shown ? 0.8 : 0)
            VStack(spacing: 18) {
                ZStack {
                    Circle().stroke(Theme.accent.opacity(ripple ? 0 : 0.5), lineWidth: 4)
                        .scaleEffect(ripple ? 1.5 : 1)
                    Circle().fill(Theme.accent)
                    PadlockDrawing(progress: progress, color: Theme.onAccent, keyColor: Theme.accent)
                        .scaleEffect(x: 1, y: squash ? 0.94 : 1, anchor: .bottom)
                        .scaleEffect(0.95)
                }
                .frame(width: 176, height: 176)
                .scaleEffect(reduceMotion ? 1 : (shown ? 1 : 0.78))

                Text(unlocking ? tr("解除しました") : tr("制限しました"))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.accentText)
                    .opacity(labelShown ? 1 : 0)
                    .offset(y: labelShown || reduceMotion ? 0 : 6)
            }
            .opacity(shown ? 1 : 0)
        }
        .accessibilityElement()
        .accessibilityLabel(unlocking ? tr("制限が解除されました") : tr("制限がかかりました"))
        .task {
            if reduceMotion {
                progress = unlocking ? 0 : 1
                withAnimation(.easeOut(duration: 0.3)) { shown = true; labelShown = true }
                return
            }
            // 現れる（開いた鍵）→ 閉まる＋振動 → 輪と文字、を、1つの流れで続ける
            withAnimation(.easeOut(duration: 0.3)) { shown = true }
            try? await Task.sleep(for: .milliseconds(420))
            if unlocking {
                // 閉じた鍵が、真上にすっと持ち上がって、開く
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(duration: 0.55, bounce: 0.25)) { progress = 0 }
                withAnimation(.easeOut(duration: 0.7)) { ripple = true }
                try? await Task.sleep(for: .milliseconds(350))
                withAnimation(.easeOut(duration: 0.35)) { labelShown = true }
                return
            }
            withAnimation(.spring(duration: 0.5, bounce: 0.35)) { progress = 1 }
            try? await Task.sleep(for: .milliseconds(230))
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.easeOut(duration: 0.12)) { squash = true }
            withAnimation(.easeOut(duration: 0.7)) { ripple = true }
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(.spring(duration: 0.3, bounce: 0.4)) { squash = false }
            withAnimation(.easeOut(duration: 0.35)) { labelShown = true }
        }
    }
}
