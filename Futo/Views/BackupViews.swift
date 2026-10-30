import SwiftUI

/// Google Driveへのバックアップと復元。手動で、必要なときだけ。
@MainActor
struct BackupView: View {
    @Environment(BackupModel.self) private var backup
    @State private var confirmDisconnect = false
    @State private var confirmDeleteRemote = false
    @State private var includeSettings = true

    var body: some View {
        Form {
            explanation
            if backup.isConnected { connected } else { notConnected }
            if let text = backup.message, !text.isEmpty { CardSection { Text(text).font(.footnote).foregroundStyle(.secondary) } }
            if let text = backup.resultMessage { CardSection { Label(text, systemImage: "checkmark.circle").foregroundStyle(Theme.accent) } }
        }
        .compactForm()
        .navigationTitle(tr("バックアップ"))
        .navigationBarTitleDisplayMode(.inline)
        .task { backup.syncConnection(); await backup.refresh() }
        .sheet(isPresented: Binding(get: { backup.preview != nil }, set: { if !$0 { backup.cancelRestore() } })) {
            restoreSheet
        }
        .confirmationDialog(tr("Driveの許可を取り消しますか？ Drive上のバックアップは、そのまま残ります。"), isPresented: $confirmDisconnect, titleVisibility: .visible) {
            Button(tr("取り消す"), role: .destructive) { Task { await backup.disconnect() } }
            Button(tr("キャンセル"), role: .cancel) {}
        }
        .confirmationDialog(tr("Drive上のバックアップを削除しますか？ 取り消せません。端末の記録は消えません。"), isPresented: $confirmDeleteRemote, titleVisibility: .visible) {
            Button(tr("削除する"), role: .destructive) { Task { await backup.deleteRemote() } }
            Button(tr("キャンセル"), role: .cancel) {}
        }
    }

    private var explanation: some View {
        CardSection {
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("記録と設定を、ふと専用の場所に"))
                Text(tr("Google Driveへ保存します。"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("ログインと同じ"))
                Text(tr("Googleアカウントを選んでください。"))
            }
            .font(.footnote).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var notConnected: some View {
        CardSection {
            Button { Task { await backup.connect() } } label: {
                Label(tr("バックアップを有効にする"), systemImage: "icloud.and.arrow.up")
            }
            .buttonStyle(FutoButtonStyle()).disabled(backup.isWorking)
        }
    }

    @ViewBuilder
    private var connected: some View {
        CardSection {
            if let remote = backup.remote, let date = remote.modifiedTime {
                HStack {
                    Text(tr("最後のバックアップ"))
                    Spacer(minLength: 8)
                    Text(BackupView.dateText(date)).monospacedDigit().foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            } else if backup.checkedRemote {
                Text(tr("まだバックアップはありません。")).foregroundStyle(.secondary)
            }
        }
        PrimarySection {
            Button { Task { await backup.backupNow() } } label: {
                if backup.isWorking {
                    ProgressView()
                } else {
                    Label(tr("今すぐバックアップ"), systemImage: "icloud.and.arrow.up")
                }
            }
            .disabled(backup.isWorking)
        }
        // 戻す・削除・許可の取り消しは、目立たせず、小さく並べる
        CardSection {
            Button { Task { await backup.prepareRestore() } } label: {
                Label(tr("バックアップから戻す"), systemImage: "icloud.and.arrow.down").font(.subheadline).foregroundStyle(Theme.accent)
            }
            .frame(minHeight: 38).disabled(backup.isWorking || backup.remote == nil)
            Button(role: .destructive) { confirmDeleteRemote = true } label: {
                Label(tr("Driveのバックアップを削除"), systemImage: "trash").font(.subheadline).foregroundStyle(.red)
            }
            .frame(minHeight: 38).disabled(backup.isWorking || backup.remote == nil)
            Button { confirmDisconnect = true } label: {
                Label(tr("Driveの許可を取り消す"), systemImage: "xmark.circle").font(.subheadline).foregroundStyle(Theme.accent)
            }
            .frame(minHeight: 38).disabled(backup.isWorking)
        }
    }

    /// 日時は「2026-10-31 18:20」の形（ハイフン区切り）。
    static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    private var restoreSheet: some View {
        NavigationStack {
            Form {
                if let p = backup.preview {
                    CardSection {
                        LabeledContent(tr("バックアップの日時"), value: BackupView.dateText(p.createdAt))
                        LabeledContent(tr("記録の件数"), value: "\(p.totalSessions)")
                        LabeledContent(tr("追加される記録"), value: "\(p.newSessions)")
                        if p.skippedSessions > 0 { LabeledContent(tr("すでにある記録"), value: "\(p.skippedSessions)") }
                        LabeledContent(tr("追加される振り返り"), value: "\(p.newCards)")
                    }
                    CardSection {
                        Toggle(tr("設定も戻す"), isOn: $includeSettings)
                        Text(tr("いま端末にある記録は、消えません。足りない記録だけが追加されます。"))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    CardSection {
                        Button(tr("戻す")) { backup.confirmRestore(includeSettings: includeSettings) }
                            .buttonStyle(FutoButtonStyle())
                    }
                }
            }
            .compactForm()
            .navigationTitle(tr("バックアップから戻す"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(tr("閉じる")) { backup.cancelRestore() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
