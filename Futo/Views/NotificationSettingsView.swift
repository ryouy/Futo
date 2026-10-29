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
        case .night: return "夜の振り返り（おすすめ）"
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

    var body: some View {
        Form {
            Section {
                Text("通知は、使い方を振り返る手助けです。はじめは「夜の振り返り」だけがおすすめです。通知は初期状態ですべてオフで、1日に最大4件、3時間以上あけて送ります。")
                    .font(.footnote)
                    .lineSpacing(3)
            }

            Section {
                toggle(.night)
                if model.prefs.notifyNight {
                    timePicker("時刻", minute: bind(\.nightMinute))
                }
                toggle(.morning)
                if model.prefs.notifyMorning {
                    timePicker("時刻", minute: bind(\.morningMinute))
                }
                toggle(.postUse)
                toggle(.outing)
                if model.prefs.notifyOuting {
                    timePicker("時刻", minute: bind(\.outingMinute))
                }
            } header: {
                Text("送る通知")
            } footer: {
                Text("使ったあとの確認は、一時解除を始めたあと、1日に最大1回までです。朝夜の通知と近いときは送らず、次にアプリを開いたときに尋ねます。")
            }

            Section {
                timePicker("はじまり", minute: bind(\.quietStartMinute))
                timePicker("おわり", minute: bind(\.quietEndMinute))
            } header: {
                Text("静かな時間")
            } footer: {
                Text("この間の通知は送りません。翌朝にまとめて送ることもありません。")
            }

            let warnings = NotificationPlanner.warnings(preferences: model.prefs)
            if !warnings.isEmpty {
                Section("お知らせ") {
                    ForEach(warnings, id: \.self) { Text($0).font(.footnote) }
                }
            }

            Section {
                Text("通知は、アプリを開くたびに、今日と明日の分だけ予約し直します。OSの都合で、時刻ぴったりに届くとは限りません。通知から制限の解除や設定の変更はしません。ロック画面には、アプリ名や利用の内容は出しません。")
                    .font(.footnote)
                    .lineSpacing(3)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("通知")
        .navigationBarTitleDisplayMode(.inline)
        .alert("通知を許可しますか？", isPresented: Binding(
            get: { model.pendingNotificationEnable != nil },
            set: { if !$0 { model.pendingNotificationEnable = nil } }
        )) {
            Button("許可を求める") { model.confirmEnableNotification() }
            Button("今はしない", role: .cancel) { model.pendingNotificationEnable = nil }
        } message: {
            Text("振り返りの時間をお知らせするために使います。次の画面で、iPhoneの許可を求めます。許可しなくても、ほかの機能はそのまま使えます。")
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
