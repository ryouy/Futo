import SwiftUI

/// 0時からの分を、DatePickerで扱うためのBinding。
func minuteBinding(get: @escaping () -> Int, set: @escaping (Int) -> Void) -> Binding<Date> {
    Binding(
        get: {
            Calendar.current.date(byAdding: .minute, value: get(), to: Calendar.current.startOfDay(for: Date())) ?? Date()
        },
        set: { date in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            set((c.hour ?? 0) * 60 + (c.minute ?? 0))
        })
}

@MainActor
struct NotificationSettingsView: View {
    @Bindable var model: AppModel

    private func title(_ kind: NotificationKind) -> String {
        switch kind {
        case .morning: return "朝の振り返り"
        case .night: return "夜の振り返り"
        case .postUse: return "使ったあとの確認"
        case .outing: return "お出かけのおすすめ"
        }
    }

    private func toggle(_ kind: NotificationKind) -> some View {
        Toggle(title(kind), isOn: Binding(
            get: { model.prefs.isNotificationOn(kind) },
            set: { on in
                if on { model.requestEnableNotification(kind) } else { model.disableNotification(kind) }
            }))
            .frame(minHeight: 44)
    }

    private func timePicker(_ label: String, minute: Binding<Int>) -> some View {
        DatePicker(label, selection: minuteBinding(get: { minute.wrappedValue }, set: { minute.wrappedValue = $0 }),
                   displayedComponents: .hourAndMinute)
            .frame(minHeight: 44)
    }

    @State private var diagnostics: (status: String, pending: [String])?

    var body: some View {
        Form {
            Section {
                toggle(.night)
                if model.prefs.notifyNight { timePicker("時刻", minute: bind(\.nightMinute)) }
                toggle(.morning)
                if model.prefs.notifyMorning { timePicker("時刻", minute: bind(\.morningMinute)) }
                toggle(.postUse)
                toggle(.outing)
                if model.prefs.notifyOuting { timePicker("時刻", minute: bind(\.outingMinute)) }
            } header: {
                Text("通知（はじめは夜だけがおすすめ）")
            } footer: {
                Text("初期はすべてオフ。1日4件まで、3時間以上あけます。")
            }

            Section {
                HStack {
                    Text("静かな時間")
                    Spacer()
                    DatePicker("はじまり", selection: minuteBinding(
                        get: { model.prefs.quietStartMinute },
                        set: { value in model.updatePreferences { $0.quietStartMinute = value } }),
                        displayedComponents: .hourAndMinute)
                        .labelsHidden()
                    Text("〜").foregroundStyle(.secondary)
                    DatePicker("おわり", selection: minuteBinding(
                        get: { model.prefs.quietEndMinute },
                        set: { value in model.updatePreferences { $0.quietEndMinute = value } }),
                        displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
                .frame(minHeight: 44)
            } footer: {
                Text("この間は送りません。翌朝にまとめて送ることもありません。")
            }

            let warnings = NotificationPlanner.warnings(preferences: model.prefs)
            if !warnings.isEmpty {
                Section("お知らせ") {
                    ForEach(warnings, id: \.self) { Text($0).font(.footnote) }
                }
            }

            #if DEBUG
            Section {
                LabeledContent("許可", value: diagnostics?.status ?? "…")
                if let pending = diagnostics?.pending {
                    Text(pending.isEmpty ? "予約中の通知はありません" : pending.joined(separator: "\n"))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Button("更新") { Task { diagnostics = await model.notifications.diagnostics() } }
                    .frame(minHeight: 44)
            } header: {
                Text("検証用（Debugのみ）")
            }
            .task { diagnostics = await model.notifications.diagnostics() }
            #endif
        }
        .compactForm()
        .alert("通知を許可しますか？", isPresented: Binding(
            get: { model.pendingNotificationEnable != nil },
            set: { if !$0 { model.pendingNotificationEnable = nil } }
        )) {
            Button("許可を求める") { model.confirmEnableNotification() }
            Button("今はしない", role: .cancel) { model.pendingNotificationEnable = nil }
        } message: {
            Text("振り返りの時間をお知らせするために使います。許可しなくても、ほかの機能は使えます。")
        }
        .alert("通知", isPresented: Binding(
            get: { model.notificationMessage != nil },
            set: { if !$0 { model.notificationMessage = nil } }
        )) {
            Button("閉じる", role: .cancel) {}
        } message: {
            Text(model.notificationMessage ?? "")
        }
    }

    private func bind(_ keyPath: WritableKeyPath<Preferences, Int>) -> Binding<Int> {
        Binding(get: { model.prefs[keyPath: keyPath] },
                set: { value in model.updatePreferences { $0[keyPath: keyPath] = value } })
    }
}
