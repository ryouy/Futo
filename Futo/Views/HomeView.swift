import SwiftData
import SwiftUI

@MainActor
struct HomeView: View {
    @Bindable var model: AppModel
    @Query private var sessions: [Session]
    @State private var showPicker = false
    @State private var confirmStop = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 8) {
                    LeafMark(size: 26)
                    Text("ふと").font(.largeTitle.weight(.medium)).foregroundStyle(Theme.accent)
                }

                statusCard
                targetCard
                actions
                countsCard
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
        .sheet(isPresented: $showPicker) { picker }
        .confirmationDialog(
            "選んだアプリの制限を終了しますか？ この試作では、自動で再開されません。",
            isPresented: $confirmStop, titleVisibility: .visible
        ) {
            Button("制限を終了", role: .destructive) { model.stopRestriction() }
            Button("キャンセル", role: .cancel) {}
        }
    }

    // MARK: 状態

    private var statusText: String {
        if model.mode == .device {
            switch model.permission {
            case .notDetermined: return "制限にはアクセスの許可が必要です"
            case .denied: return "制限にはアクセスの許可が必要です。設定アプリで許可を変更できます。"
            case .approved: break
            }
        }
        if model.targetCount == 0 { return "制限したいアプリを選んでください" }
        switch model.restriction {
        case .configured: return "選択したアプリへの制限を設定しています"
        case .temporarilyUnlocked(let until):
            return "一時的に使えるようにしています。選んだアプリの利用が約\(SharedState.unlockUsageMinutes)分に達するか、遅くとも\(until.formatted(date: .omitted, time: .shortened))までに、自動で制限に戻ります。"
        case .unverifiable: return "設定を確認できませんでした。もう一度お試しください"
        case .off: return "制限はオフです"
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(model.mode == .demo ? "デモモード" : "実機モード",
                  systemImage: model.mode == .demo ? "play.rectangle" : "iphone")
                .font(.subheadline.weight(.medium))
            Text(statusText).lineSpacing(4)
            if let error = model.permissionError {
                Text(error).font(.footnote)
            }
            if let notice = model.notice {
                Text(notice).font(.footnote).padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.softPeach, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            if case .temporarilyUnlocked = model.restriction {
                Text("一時解除は実機で検証中の試験機能です。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if model.mode == .device {
                Text("権限と設定の照合結果です。OS上でシールドが実際に表示されているかは、対象アプリを開いて確かめてください。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .card()
        .accessibilityElement(children: .combine)
    }

    private var targetCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("制限するアプリ").font(.subheadline.weight(.medium))
            if model.mode == .demo {
                Text(model.demo.targetName ?? "未選択")
            } else if model.targetCount == 0 {
                Text("未選択")
            } else {
                DeviceTargetLabels(selection: model.device.selection)
            }
        }
        .card()
    }

    // MARK: 操作

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 12) {
            if case .temporarilyUnlocked = model.restriction {
                Button("制限に戻す") { model.relockNow() }
                    .buttonStyle(FutoButtonStyle())
            } else if model.activeSession != nil {
                Button("ひと呼吸を再開") { model.resumeBreath() }
                    .buttonStyle(FutoButtonStyle())
                Button("この振り返りを終了") { model.endBreath() }
                    .buttonStyle(FutoButtonStyle(prominent: false))
            } else {
                primaryButton
            }
            if model.intendsRestriction {
                Button("制限を終了") { confirmStop = true }
                    .buttonStyle(FutoButtonStyle(prominent: false))
            }
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        if model.mode == .device, model.permission != .approved {
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

    private var countsCard: some View {
        let counts = DailyCounts.today(sessions: sessions, mode: model.mode)
        return VStack(alignment: .leading, spacing: 8) {
            Text("今日の記録").font(.subheadline.weight(.medium))
            HStack {
                Text("今日の見送り")
                Spacer()
                Text("\(counts.deferred)").font(.title3.monospacedDigit())
            }
            HStack {
                Text("今日の利用希望")
                Spacer()
                Text("\(counts.wantsToUse)").font(.title3.monospacedDigit())
            }
        }
        .card()
        .accessibilityElement(children: .combine)
    }
}
