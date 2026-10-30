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

/// 「名前 …… [時刻] [トグル]」の1行。時刻はトグルの左。オフのときは時刻を薄くして押せなくする。
struct TimeToggleRow: View {
    let title: String
    let isOn: Binding<Bool>
    var minute: Binding<Int>?

    var body: some View {
        HStack(spacing: 10) {
            Text(title).oneLine(0.8)
            Spacer(minLength: 8)
            if let minute {
                DatePicker("", selection: minuteBinding(get: { minute.wrappedValue }, set: { minute.wrappedValue = $0 }),
                           displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .disabled(!isOn.wrappedValue)
                    .opacity(isOn.wrappedValue ? 1 : 0.4)
            }
            Toggle(title, isOn: isOn).labelsHidden()
        }
        .frame(minHeight: 48)
    }
}

@MainActor
struct NotificationSettingsView: View {
    @Bindable var model: AppModel

    private func title(_ kind: NotificationKind) -> String {
        switch kind {
        case .morning: return tr("朝の振り返り")
        case .night: return tr("夜の振り返り")
        case .postUse: return tr("使ったあとの確認")
        case .outing: return tr("お出かけのおすすめ")
        }
    }

    private func row(_ kind: NotificationKind, minute: Binding<Int>? = nil) -> some View {
        TimeToggleRow(
            title: title(kind),
            isOn: Binding(
                get: { model.prefs.isNotificationOn(kind) },
                set: { on in
                    if on { model.requestEnableNotification(kind) } else { model.disableNotification(kind) }
                }),
            minute: minute)
    }

    var body: some View {
        Form {
            CardSection {
                row(.night, minute: bind(\.nightMinute))
                row(.morning, minute: bind(\.morningMinute))
                row(.outing, minute: bind(\.outingMinute))
                row(.postUse)
            }

            CardSection {
                HStack {
                    Text(tr("静かな時間"))
                    Spacer()
                    DatePicker(tr("はじまり"), selection: minuteBinding(
                        get: { model.prefs.quietStartMinute },
                        set: { value in model.updatePreferences { $0.quietStartMinute = value } }),
                        displayedComponents: .hourAndMinute)
                        .labelsHidden()
                    Text(tr("〜")).foregroundStyle(.secondary)
                    DatePicker(tr("おわり"), selection: minuteBinding(
                        get: { model.prefs.quietEndMinute },
                        set: { value in model.updatePreferences { $0.quietEndMinute = value } }),
                        displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
                .frame(minHeight: 44)
            }

            CardSection {
                TimeToggleRow(
                    title: tr("朝の振り返りカード"),
                    isOn: Binding(get: { model.prefs.morningEnabled },
                                  set: { on in model.updatePreferences { $0.morningEnabled = on } }),
                    minute: bind(\.morningMinute))
                TimeToggleRow(
                    title: tr("夜の振り返りカード"),
                    isOn: Binding(get: { model.prefs.nightEnabled },
                                  set: { on in model.updatePreferences { $0.nightEnabled = on } }),
                    minute: bind(\.nightMinute))
            }

            let warnings = NotificationPlanner.warnings(preferences: model.prefs)
            if !warnings.isEmpty {
                CardSection {
                    ForEach(warnings, id: \.self) { Text($0).font(.footnote) }
                }
            }

        }
        .compactForm()
        .alert(tr("通知を許可しますか？"), isPresented: Binding(
            get: { model.pendingNotificationEnable != nil },
            set: { if !$0 { model.pendingNotificationEnable = nil } }
        )) {
            Button(tr("許可を求める")) { model.confirmEnableNotification() }
            Button(tr("今はしない"), role: .cancel) { model.pendingNotificationEnable = nil }
        } message: {
            Text(tr("振り返りの時間をお知らせするために使います。許可しなくても、ほかの機能は使えます。"))
        }
        .alert(tr("通知"), isPresented: Binding(
            get: { model.notificationMessage != nil },
            set: { if !$0 { model.notificationMessage = nil } }
        )) {
            Button(tr("閉じる"), role: .cancel) {}
        } message: {
            Text(model.notificationMessage ?? "")
        }
    }

    private func bind(_ keyPath: WritableKeyPath<Preferences, Int>) -> Binding<Int> {
        Binding(get: { model.prefs[keyPath: keyPath] },
                set: { value in model.updatePreferences { $0[keyPath: keyPath] = value } })
    }
}
