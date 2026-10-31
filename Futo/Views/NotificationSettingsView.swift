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
        case .outing: return tr("お出かけの誘い")
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

    /// お出かけのおすすめ：1行に、名前・「n回/日」・オン/オフ（トグルの左に回数）。時刻は、ランダムに（できるだけ均等に）決まる。
    private var outingRow: some View {
        HStack(spacing: 10) {
            // 1行に収まらないときは、「お出かけの」の次の行に「誘い」を置く（途中で、不自然に折れない）
            ViewThatFits(in: .horizontal) {
                Text(title(.outing)).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 0) {
                    Text(tr("お出かけの"))
                    Text(tr("誘い"))
                }
            }
            Spacer(minLength: 8)
            if model.prefs.notifyOuting {
                Picker(tr("1日の回数"), selection: Binding(
                    get: { model.prefs.outingPerDay },
                    set: { value in model.updatePreferences { $0.outingPerDay = value } }
                )) {
                    ForEach(1...6, id: \.self) { Text(tr("{0}回/日", "\($0)")).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
            Toggle(title(.outing), isOn: Binding(
                get: { model.prefs.isNotificationOn(.outing) },
                set: { on in
                    if on { model.requestEnableNotification(.outing) } else { model.disableNotification(.outing) }
                }))
                .labelsHidden()
        }
        .frame(minHeight: 44)
    }

    var body: some View {
        Form {
            // 通知が未許可のとき、ここから許可できる（決めていなければ許可を求め、断っていれば設定アプリへ）
            if model.notificationStatus == .denied {
                CardSection {
                    Text(tr("通知がオフです　設定アプリで許可できます")).font(.subheadline)
                    Button(tr("設定アプリを開く")) {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .buttonStyle(FutoButtonStyle())
                }
            } else if model.notificationStatus == .notDetermined {
                CardSection {
                    Text(tr("通知はまだ許可されていません")).font(.subheadline)
                    Button(tr("通知を許可する")) { model.requestNotificationPermission(enableDefaults: false) }
                        .buttonStyle(FutoButtonStyle())
                }
            }
            CardSection {
                row(.night, minute: bind(\.nightMinute))
                row(.morning, minute: bind(\.morningMinute))
                outingRow
                row(.postUse)
            }

            let warnings = NotificationPlanner.warnings(preferences: model.prefs)
            if !warnings.isEmpty {
                CardSection {
                    ForEach(warnings, id: \.self) { Text($0).font(.footnote) }
                }
            }

        }
        .compactForm()
        .task { model.refreshNotificationStatus() }
        .alert(tr("通知を許可しますか？"), isPresented: Binding(
            get: { model.pendingNotificationEnable != nil },
            set: { if !$0 { model.pendingNotificationEnable = nil } }
        )) {
            Button(tr("許可を求める")) { model.confirmEnableNotification() }
            Button(tr("今はしない"), role: .cancel) { model.pendingNotificationEnable = nil }
        } message: {
            Text(tr("振り返りの時間をお知らせするために使います　許可しなくても、ほかの機能は使えます"))
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
